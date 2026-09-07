import Foundation

enum RecordingStatus: String, Codable {
    case recording      // capture in progress
    case recorded       // captured, not transcribed yet
    case transcribing   // transcription in progress
    case done           // transcript ready
    case failed         // something went wrong
}

struct RecordingMeta: Codable {
    var date: Date
    var language: String
    var duration: TimeInterval?
    var status: RecordingStatus
    var errorMessage: String?
}

struct Recording: Identifiable {
    let folder: URL
    var meta: RecordingMeta

    var id: String { folder.lastPathComponent }
    var movieURL: URL { folder.appendingPathComponent("recording.mov") }
    var transcriptURL: URL { folder.appendingPathComponent("transcript.txt") }
    var subtitlesURL: URL { folder.appendingPathComponent("transcript.srt") }
    var summaryURL: URL { folder.appendingPathComponent("summary.md") }

    var hasTranscript: Bool {
        FileManager.default.fileExists(atPath: transcriptURL.path)
    }

    var hasSummary: Bool {
        FileManager.default.fileExists(atPath: summaryURL.path)
    }
}

enum RecordingStore {
    static var baseFolder: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingNoter", isDirectory: true)
    }

    static func newRecordingFolder(date: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let folder = baseFolder.appendingPathComponent(formatter.string(from: date), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func saveMeta(_ meta: RecordingMeta, in folder: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(meta) {
            try? data.write(to: folder.appendingPathComponent("meta.json"))
        }
    }

    static func loadAll() -> [Recording] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(
            at: baseFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var result: [Recording] = []
        for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let metaURL = folder.appendingPathComponent("meta.json")
            let movieURL = folder.appendingPathComponent("recording.mov")

            var meta: RecordingMeta
            if let data = try? Data(contentsOf: metaURL),
               let decoded = try? decoder.decode(RecordingMeta.self, from: data) {
                meta = decoded
            } else if fm.fileExists(atPath: movieURL.path) {
                // Video without metadata (a crash before the save, say) — reconstruct it.
                let created = (try? movieURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                meta = RecordingMeta(date: created, language: "uk", duration: nil, status: .recorded)
                saveMeta(meta, in: folder)
            } else {
                // Empty folder left by a failed start — drop it.
                let contents = (try? fm.contentsOfDirectory(atPath: folder.path))?
                    .filter { $0 != ".DS_Store" } ?? []
                if contents.isEmpty {
                    try? fm.removeItem(at: folder)
                }
                continue
            }

            // If the app died mid-recording or mid-transcription, let the user retry.
            if meta.status == .transcribing || meta.status == .recording {
                meta.status = .recorded
            }
            result.append(Recording(folder: folder, meta: meta))
        }
        return result.sorted { $0.meta.date > $1.meta.date }
    }
}
