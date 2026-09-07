import Foundation
import AVFoundation

enum TranscriberError: LocalizedError {
    case noAudioTracks
    case whisperNotFound
    case modelNotFound
    case processFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .noAudioTracks:
            return "The recording has no audio tracks."
        case .whisperNotFound:
            return "whisper-cli not found — install it: brew install whisper-cpp"
        case .modelNotFound:
            return "No Whisper model in ~/Library/Application Support/MeetingNoter/models"
        case .processFailed(let tool, let code, let output):
            return "\(tool) exited with code \(code): \(output.suffix(300))"
        }
    }
}

enum TranscriptLanguage: String, CaseIterable, Identifiable {
    case russian = "ru"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        }
    }

    /// Speaker labels: (system audio, microphone).
    var speakerLabels: (others: String, me: String) {
        switch self {
        case .russian: return ("Собеседник", "Вы")
        case .english: return ("Them", "Me")
        }
    }
}

/// Pipeline: .mov → each audio track on its own (normalize → 16 kHz mono WAV → whisper)
/// → merge segments by timecode with speaker labels. The tracks are NEVER mixed down:
/// a raw mic summed with system audio interferes with itself and wrecks recognition quality.
enum Transcriber {
    static var whisperCLI: URL? {
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }

    static var modelsFolder: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingNoter/models", isDirectory: true)
    }

    static var model: URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: modelsFolder, includingPropertiesForKeys: nil
        )) ?? []
        // Pick the largest .bin — that is normally the main model.
        return files
            .filter { $0.pathExtension == "bin" }
            .max { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let r = (try? rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return l < r
            }
    }

    static var isReady: Bool { whisperCLI != nil && model != nil }

    struct Segment {
        let startMs: Int
        let endMs: Int
        let speaker: String?
        let text: String
    }

    /// Produces the transcript; returns the transcript.txt URL.
    static func transcribe(movie movieURL: URL, language: TranscriptLanguage, into folder: URL) async throws -> URL {
        guard let whisper = whisperCLI else { throw TranscriberError.whisperNotFound }
        guard let model else { throw TranscriberError.modelNotFound }

        let asset = AVURLAsset(url: movieURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw TranscriberError.noAudioTracks }

        // Track order in the file: 0 is system audio, 1 is the microphone.
        let labels = language.speakerLabels
        func speaker(for index: Int) -> String? {
            guard audioTracks.count >= 2 else { return nil }
            return index == 0 ? labels.others : labels.me
        }

        var segments: [Segment] = []
        for (index, track) in audioTracks.enumerated() {
            let wavURL = folder.appendingPathComponent("track-\(index).wav")
            let jsonURL = folder.appendingPathComponent("track-\(index).json")
            defer {
                try? FileManager.default.removeItem(at: wavURL)
                try? FileManager.default.removeItem(at: jsonURL)
            }

            let peak = try exportNormalizedTrack(asset: asset, track: track, to: wavURL)
            if peak < 0.001 { continue } // silence — whisper hallucinates on it

            try await run(whisper.path, [
                "-m", model.path,
                "-f", wavURL.path,
                "-l", language.rawValue,
                "-bs", "5",
                "-oj",
                "-of", folder.appendingPathComponent("track-\(index)").path,
                "-np",
            ])

            segments += try parseSegments(jsonURL: jsonURL, speaker: speaker(for: index))
        }

        segments = segments
            .filter { !$0.text.isEmpty && !isHallucination($0.text) }
            .sorted { $0.startMs < $1.startMs }

        let transcriptURL = folder.appendingPathComponent("transcript.txt")
        try plainText(segments).write(to: transcriptURL, atomically: true, encoding: .utf8)
        try srtText(segments).write(
            to: folder.appendingPathComponent("transcript.srt"),
            atomically: true, encoding: .utf8
        )
        return transcriptURL
    }

    // MARK: - Track extraction

    private static let pcm16kMonoFloat: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    private static func floatSamples(_ sampleBuffer: CMSampleBuffer) -> [Float] {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return [] }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = [Float](repeating: 0, count: length / 4)
        data.withUnsafeMutableBytes { ptr in
            _ = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
        }
        return data
    }

    /// Two-pass export: measure peak → normalize to 0.85 (system audio often runs past full
    /// scale and clips when written to a 16-bit WAV, while a quiet mic disappears instead).
    /// Returns the track's original peak.
    private static func exportNormalizedTrack(asset: AVAsset, track: AVAssetTrack, to wavURL: URL) throws -> Float {
        var peak: Float = 0
        let peakReader = try AVAssetReader(asset: asset)
        let peakOutput = AVAssetReaderTrackOutput(track: track, outputSettings: pcm16kMonoFloat)
        peakReader.add(peakOutput)
        peakReader.startReading()
        while let sampleBuffer = peakOutput.copyNextSampleBuffer() {
            for sample in floatSamples(sampleBuffer) { peak = max(peak, abs(sample)) }
        }
        guard peak >= 0.001 else { return peak }
        let gain = min(0.85 / peak, 30)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: pcm16kMonoFloat)
        reader.add(output)
        reader.startReading()

        try? FileManager.default.removeItem(at: wavURL)
        let wavFile = try AVAudioFile(forWriting: wavURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
        ) else { throw TranscriberError.processFailed("AVAudioFormat", -1, "could not create the format") }

        while let sampleBuffer = output.copyNextSampleBuffer() {
            var data = floatSamples(sampleBuffer)
            guard !data.isEmpty else { continue }
            for index in data.indices {
                data[index] = max(-1, min(1, data[index] * gain))
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count)) else { continue }
            buffer.frameLength = AVAudioFrameCount(data.count)
            data.withUnsafeBufferPointer { ptr in
                buffer.floatChannelData!.pointee.update(from: ptr.baseAddress!, count: data.count)
            }
            try wavFile.write(from: buffer)
        }
        if reader.status == .failed {
            throw TranscriberError.processFailed("AVAssetReader", -1, reader.error?.localizedDescription ?? "")
        }
        return peak
    }

    // MARK: - Parsing whisper output

    private struct WhisperOutput: Decodable {
        struct Item: Decodable {
            struct Offsets: Decodable {
                let from: Int
                let to: Int
            }
            let offsets: Offsets
            let text: String
        }
        let transcription: [Item]
    }

    private static func parseSegments(jsonURL: URL, speaker: String?) throws -> [Segment] {
        let data = try Data(contentsOf: jsonURL)
        let output = try JSONDecoder().decode(WhisperOutput.self, from: data)
        return output.transcription.map {
            Segment(
                startMs: $0.offsets.from,
                endMs: $0.offsets.to,
                speaker: speaker,
                text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    /// Whisper's stock hallucinations on silence and noise.
    private static let hallucinationMarkers = [
        "субтитр", "dimatorzok", "продолжение следует", "редактор субтитров",
        "thanks for watching", "thank you for watching", "subtitles by",
    ]

    private static func isHallucination(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return hallucinationMarkers.contains { lowered.contains($0) }
    }

    // MARK: - Formatting

    private static func clockTime(_ ms: Int) -> String {
        let seconds = ms / 1000
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private static func srtTime(_ ms: Int) -> String {
        String(
            format: "%02d:%02d:%02d,%03d",
            ms / 3_600_000, (ms % 3_600_000) / 60_000, (ms % 60_000) / 1000, ms % 1000
        )
    }

    private static func plainText(_ segments: [Segment]) -> String {
        segments.map { segment in
            let speakerPrefix = segment.speaker.map { "\($0): " } ?? ""
            return "[\(clockTime(segment.startMs))] \(speakerPrefix)\(segment.text)"
        }
        .joined(separator: "\n")
    }

    private static func srtText(_ segments: [Segment]) -> String {
        segments.enumerated().map { index, segment in
            let speakerPrefix = segment.speaker.map { "\($0): " } ?? ""
            return "\(index + 1)\n\(srtTime(segment.startMs)) --> \(srtTime(segment.endMs))\n\(speakerPrefix)\(segment.text)\n"
        }
        .joined(separator: "\n")
    }

    // MARK: - Running processes

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: TranscriberError.processFailed(
                        (executable as NSString).lastPathComponent,
                        process.terminationStatus,
                        output
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
