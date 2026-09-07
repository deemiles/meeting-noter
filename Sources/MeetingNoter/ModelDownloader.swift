import Foundation

/// Whisper models the app can fetch on first launch, so the user never touches a terminal.
enum WhisperModel: String, CaseIterable, Identifiable {
    case turbo = "ggml-large-v3-turbo.bin"
    case small = "ggml-small.bin"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .turbo: return "Large v3 Turbo"
        case .small: return "Small"
        }
    }

    var subtitle: String {
        switch self {
        case .turbo: return "1.5 GB · best accuracy · recommended"
        case .small: return "466 MB · faster download, rougher transcripts"
        }
    }

    var url: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(rawValue)")!
    }
}

/// Downloads a Whisper model into Application Support with progress, resuming is not
/// attempted — a failed download is simply discarded and can be retried.
@MainActor
final class ModelDownloader: NSObject, ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var downloading: WhisperModel?
    @Published var error: String?

    private var task: URLSessionDownloadTask?
    private lazy var session: URLSession = URLSession(
        configuration: .default, delegate: self, delegateQueue: nil
    )

    var isDownloading: Bool { downloading != nil }

    /// Human-readable progress for the UI, e.g. "412 MB of 1.5 GB".
    @Published private(set) var progressText = ""

    func download(_ model: WhisperModel) {
        guard downloading == nil else { return }
        error = nil
        progress = 0
        progressText = ""
        downloading = model

        try? FileManager.default.createDirectory(
            at: Transcriber.modelsFolder, withIntermediateDirectories: true
        )
        let task = session.downloadTask(with: model.url)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        downloading = nil
        progress = 0
        progressText = ""
    }

    fileprivate func finish(movingFrom location: URL) {
        guard let model = downloading else { return }
        let destination = Transcriber.modelsFolder.appendingPathComponent(model.rawValue)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            self.error = "Could not save the model: \(error.localizedDescription)"
        }
        downloading = nil
        task = nil
        progress = 0
        progressText = ""
    }

    fileprivate func fail(_ message: String) {
        error = message
        downloading = nil
        task = nil
        progress = 0
        progressText = ""
    }

    fileprivate func update(written: Int64, total: Int64) {
        guard total > 0 else { return }
        progress = Double(written) / Double(total)
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        progressText = "\(formatter.string(fromByteCount: written)) of \(formatter.string(fromByteCount: total))"
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The temp file disappears when this method returns, so move it synchronously here.
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: staged)
        Task { @MainActor in self.finish(movingFrom: staged) }
    }

    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            self.update(written: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let message = (error as NSError).code == NSURLErrorCancelled
            ? "" : error.localizedDescription
        Task { @MainActor in
            if message.isEmpty { self.cancel() } else { self.fail(message) }
        }
    }
}
