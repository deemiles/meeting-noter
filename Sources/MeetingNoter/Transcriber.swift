import Foundation
import AVFoundation

/// How far along a transcription is, for the menu to show something other than a spinner.
struct TranscriptionProgress: Equatable, Sendable {
    var trackIndex: Int
    var trackCount: Int
    /// Progress within the current track, 0...1.
    var fraction: Double

    /// Progress across every track, 0...1.
    var overall: Double {
        (Double(trackIndex) + fraction) / Double(max(trackCount, 1))
    }
}

enum TranscriberError: LocalizedError {
    case noAudioTracks
    case whisperNotFound
    case modelNotFound
    case stalled
    case processFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .noAudioTracks:
            return "The recording has no audio tracks."
        case .whisperNotFound:
            return "whisper-cli is missing from the app bundle — try reinstalling Meeting Noter."
        case .modelNotFound:
            return "No Whisper model yet — open the Meeting Noter menu and download one."
        case .stalled:
            return "Transcription stopped responding and was cancelled — press retry to start over."
        case .processFailed(let tool, let code, let output):
            return "\(tool) exited with code \(code): \(output.suffix(300))"
        }
    }
}

enum TranscriptLanguage: String, CaseIterable, Identifiable {
    case ukrainian = "uk"
    case english = "en"
    case spanish = "es"
    case german = "de"
    case russian = "ru"

    var id: String { rawValue }

    /// Endonyms — a language picker reads better in the language it offers.
    var title: String {
        switch self {
        case .ukrainian: return "Українська"
        case .english: return "English"
        case .spanish: return "Español"
        case .german: return "Deutsch"
        case .russian: return "Русский"
        }
    }

    /// Speaker labels: (system audio, microphone).
    var speakerLabels: (others: String, me: String) {
        switch self {
        case .ukrainian: return ("Співрозмовник", "Ви")
        case .english: return ("Them", "Me")
        case .spanish: return ("Interlocutor", "Yo")
        case .german: return ("Gesprächspartner", "Ich")
        case .russian: return ("Собеседник", "Вы")
        }
    }

    /// Section headings used when the summary is flattened into a chat message.
    var summaryHeadings: (topics: String, decisions: String, actions: String) {
        switch self {
        case .ukrainian: return ("Теми", "Рішення", "Завдання")
        case .english: return ("Topics", "Decisions", "Action items")
        case .spanish: return ("Temas", "Decisiones", "Tareas")
        case .german: return ("Themen", "Entscheidungen", "Aufgaben")
        case .russian: return ("Темы", "Решения", "Задачи")
        }
    }

    /// Short duration unit for the copied-notes header.
    var minutesUnit: String {
        switch self {
        case .ukrainian: return "хв"
        case .english: return "min"
        case .spanish: return "min"
        case .german: return "Min."
        case .russian: return "мин"
        }
    }

    /// Title line for a copied summary, e.g. "Нотатки зустрічі".
    var notesTitle: String {
        switch self {
        case .ukrainian: return "Нотатки зустрічі"
        case .english: return "Meeting notes"
        case .spanish: return "Notas de la reunión"
        case .german: return "Besprechungsnotizen"
        case .russian: return "Заметки встречи"
        }
    }
}

/// Pipeline: .mov → each audio track on its own (normalize → 16 kHz mono WAV → whisper)
/// → merge segments by timecode with speaker labels. The tracks are NEVER mixed down:
/// a raw mic summed with system audio interferes with itself and wrecks recognition quality.
enum Transcriber {
    /// The app ships its own statically linked whisper-cli, so a plain download works with
    /// no Homebrew involved. A system install still wins nothing — the bundled one is tried
    /// first — but the fallbacks keep `swift run` working during development.
    static var whisperCLI: URL? {
        var candidates: [String] = []
        if let bundled = Bundle.main.url(forResource: "whisper-cli", withExtension: nil) {
            candidates.append(bundled.path)
        }
        candidates += [
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
    /// `onProgress` fires as whisper works through each track.
    static func transcribe(
        movie movieURL: URL,
        language: TranscriptLanguage,
        into folder: URL,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)? = nil
    ) async throws -> URL {
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
        let trackCount = audioTracks.count
        for (index, track) in audioTracks.enumerated() {
            try Task.checkCancellation()

            let wavURL = folder.appendingPathComponent("track-\(index).wav")
            let jsonURL = folder.appendingPathComponent("track-\(index).json")
            defer {
                try? FileManager.default.removeItem(at: wavURL)
                try? FileManager.default.removeItem(at: jsonURL)
            }

            onProgress?(TranscriptionProgress(trackIndex: index, trackCount: trackCount, fraction: 0))

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
                "-pp",   // progress lines, so the menu can show more than a spinner
            ]) { fraction in
                onProgress?(TranscriptionProgress(
                    trackIndex: index, trackCount: trackCount, fraction: fraction
                ))
            }

            segments += try parseSegments(jsonURL: jsonURL, speaker: speaker(for: index))
        }
        onProgress?(TranscriptionProgress(trackIndex: trackCount, trackCount: trackCount, fraction: 0))

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

    /// Thread-safe accumulator: the pipe is drained on a background queue while the
    /// process runs, and read again once it exits.
    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
        }

        var string: String {
            lock.lock(); defer { lock.unlock() }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    /// whisper prints "whisper_print_progress_callback: progress =  36%".
    private static func parseProgress(_ text: String) -> [Double] {
        text.components(separatedBy: .newlines).compactMap { line in
            guard line.contains("progress ="),
                  let range = line.range(of: #"\d+%"#, options: .regularExpression),
                  let percent = Double(line[range].dropLast())
            else { return nil }
            return percent / 100
        }
    }

    /// Kill a run that has produced nothing for this long. whisper is steady about
    /// printing progress, so silence means it is wedged, not merely slow.
    private static let stallTimeout: TimeInterval = 15 * 60

    @discardableResult
    private static func run(
        _ executable: String,
        _ arguments: [String],
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collected = OutputBuffer()
        let lastOutput = OutputClock()

        // Drain the pipe as the child writes it. Reading only from terminationHandler
        // deadlocks: once a child fills the 64 KB pipe buffer it blocks on write and never
        // exits, so the handler never runs. An hour-long meeting was enough to hit that.
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            collected.append(chunk)
            lastOutput.touch()
            if let onProgress, let text = String(data: chunk, encoding: .utf8) {
                for fraction in parseProgress(text) { onProgress(fraction) }
            }
        }

        // Watchdog for a genuinely wedged process, so a stuck run fails loudly
        // instead of spinning for a day.
        // A dispatch timer rather than a Timer: this runs on a background task, and a
        // run-loop timer would depend on the main thread staying responsive.
        let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        watchdog.schedule(deadline: .now() + 60, repeating: 60)
        watchdog.setEventHandler {
            if lastOutput.secondsSinceLastOutput > stallTimeout, process.isRunning {
                process.terminate()
            }
        }
        watchdog.resume()

        defer {
            watchdog.cancel()
            pipe.fileHandleForReading.readabilityHandler = nil
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                process.terminationHandler = { process in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    let rest = pipe.fileHandleForReading.availableData
                    if !rest.isEmpty { collected.append(rest) }
                    let output = collected.string

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else if process.terminationReason == .uncaughtSignal {
                        // terminate() was called: either the task was cancelled or the
                        // watchdog fired.
                        let stalled = lastOutput.secondsSinceLastOutput > stallTimeout
                        continuation.resume(throwing: stalled
                            ? TranscriberError.stalled
                            : CancellationError())
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
        } onCancel: {
            process.terminate()
        }
    }

    /// Timestamp of the last byte the child produced, readable from any thread.
    private final class OutputClock: @unchecked Sendable {
        private let lock = NSLock()
        private var last = Date()

        func touch() {
            lock.lock(); defer { lock.unlock() }
            last = Date()
        }

        var secondsSinceLastOutput: TimeInterval {
            lock.lock(); defer { lock.unlock() }
            return Date().timeIntervalSince(last)
        }
    }
}
