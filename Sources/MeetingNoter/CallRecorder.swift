import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia

enum CaptureSource: String, CaseIterable, Identifiable {
    case slack
    case meet
    case fullScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slack: return "Slack"
        case .meet: return "Meet"
        case .fullScreen: return "Screen"
        }
    }

    var icon: String {
        switch self {
        case .slack: return "number.square.fill"
        case .meet: return "video.square.fill"
        case .fullScreen: return "rectangle.inset.filled"
        }
    }
}

enum RecorderError: LocalizedError {
    case slackNotRunning
    case meetNotFound
    case noDisplay
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .slackNotRunning:
            return "Slack isn't running — open Slack and try again (or pick “Screen”)."
        case .meetNotFound:
            return "No Google Meet tab found in any browser — open the meeting and try again."
        case .noDisplay:
            return "No display available for recording."
        case .writerFailed(let message):
            return "File write failed: \(message)"
        }
    }
}

/// Records the Slack window (or the whole screen) plus system audio and microphone into a single .mov.
final class CallRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?

    private let videoQueue = DispatchQueue(label: "noter.video")
    private let audioQueue = DispatchQueue(label: "noter.audio")
    private let micQueue = DispatchQueue(label: "noter.mic")

    private let sessionLock = NSLock()
    private var sessionStarted = false

    private let outputURL: URL
    var onStreamStopped: ((Error?) -> Void)?

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    // MARK: - Start

    func start(source: CaptureSource) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter = try Self.makeFilter(source: source, content: content)

        let scale = CGFloat(filter.pointPixelScale)
        var width = Int(filter.contentRect.width * scale)
        var height = Int(filter.contentRect.height * scale)
        width -= width % 2
        height -= height % 2
        width = max(width, 2)
        height = max(height, 2)

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 15) // 15 fps is plenty for a call
        config.queueDepth = 6
        config.showsCursor = true
        config.capturesAudio = true              // what the other side says
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.captureMicrophone = true          // your own voice

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        videoInput.expectsMediaDataInRealTime = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 160_000,
        ]
        let systemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        systemAudioInput.expectsMediaDataInRealTime = true
        let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        micInput.expectsMediaDataInRealTime = true

        for input in [videoInput, systemAudioInput, micInput] where writer.canAdd(input) {
            writer.add(input)
        }
        guard writer.startWriting() else {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "startWriting")
        }

        self.writer = writer
        self.videoInput = videoInput
        self.systemAudioInput = systemAudioInput
        self.micInput = micInput

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: micQueue)
        self.stream = stream

        try await stream.startCapture()
    }

    /// Browsers we search for a Google Meet tab.
    private static let browserBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser", // Arc
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    private static func makeFilter(source: CaptureSource, content: SCShareableContent) throws -> SCContentFilter {
        switch source {
        case .fullScreen:
            guard let display = content.displays.first else { throw RecorderError.noDisplay }
            return SCContentFilter(display: display, excludingWindows: [])

        case .slack:
            guard let slack = content.applications.first(where: {
                $0.bundleIdentifier.lowercased().contains("slack")
            }) else { throw RecorderError.slackNotRunning }
            return try appFilter(for: slack, content: content)

        case .meet:
            // A Meet tab title looks like "Meet – abc-defg-hij".
            let meetWindow = content.windows.first { window in
                guard window.isOnScreen,
                      let app = window.owningApplication,
                      browserBundleIDs.contains(app.bundleIdentifier)
                else { return false }
                let title = (window.title ?? "").lowercased()
                return title.hasPrefix("meet") || title.contains("google meet") || title.contains("meet.google.com")
            }
            guard let browser = meetWindow?.owningApplication else { throw RecorderError.meetNotFound }
            return try appFilter(for: browser, content: content)
        }
    }

    /// Filter for "every window of the app on its display": video is the app windows, audio is the app only.
    private static func appFilter(for app: SCRunningApplication, content: SCShareableContent) throws -> SCContentFilter {
        let appWindow = content.windows.first {
            $0.owningApplication?.bundleIdentifier == app.bundleIdentifier && $0.isOnScreen
        }
        let display = content.displays.first { display in
            guard let window = appWindow else { return false }
            return display.frame.intersects(window.frame)
        } ?? content.displays.first

        guard let display else { throw RecorderError.noDisplay }
        return SCContentFilter(display: display, including: [app], exceptingWindows: [])
    }

    // MARK: - Stop

    func stop() async throws -> URL {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil

        // Let the queues drain their last samples.
        videoQueue.sync {}
        audioQueue.sync {}
        micQueue.sync {}

        guard let writer else { return outputURL }
        if sessionStarted {
            videoInput?.markAsFinished()
            systemAudioInput?.markAsFinished()
            micInput?.markAsFinished()
            await writer.finishWriting()
        } else {
            writer.cancelWriting()
            throw RecorderError.writerFailed("No frames captured — check the Screen Recording permission.")
        }
        if writer.status == .failed {
            throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
        }
        return outputURL
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            handleVideo(sampleBuffer)
        case .audio:
            append(sampleBuffer, to: systemAudioInput)
        case .microphone:
            append(sampleBuffer, to: micInput)
        @unknown default:
            break
        }
    }

    private func handleVideo(_ sampleBuffer: CMSampleBuffer) {
        // Only complete frames get written.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              statusRaw == SCFrameStatus.complete.rawValue
        else { return }

        startSessionIfNeeded(at: sampleBuffer.presentationTimeStamp)
        append(sampleBuffer, to: videoInput)
    }

    private func startSessionIfNeeded(at time: CMTime) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        guard !sessionStarted, let writer, writer.status == .writing else { return }
        writer.startSession(atSourceTime: time)
        sessionStarted = true
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?) {
        sessionLock.lock()
        let started = sessionStarted
        sessionLock.unlock()
        guard started, let input, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamStopped?(error)
    }
}
