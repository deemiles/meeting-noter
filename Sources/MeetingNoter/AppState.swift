import Foundation
import SwiftUI
import AppKit
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording(since: Date)
        case stopping
    }

    @Published var phase: Phase = .idle
    @Published var recordings: [Recording] = []
    @Published var lastError: String?
    @Published var elapsedText = ""
    @Published var searchQuery = ""
    @Published var summarizing: Set<String> = []
    @Published var viewingRecording: Recording?
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    @AppStorage("language") private var languageRaw = TranscriptLanguage.ukrainian.rawValue
    @AppStorage("source") private var sourceRaw = CaptureSource.slack.rawValue
    @AppStorage("sounds") var soundsEnabled = true

    var language: TranscriptLanguage {
        get { TranscriptLanguage(rawValue: languageRaw) ?? .ukrainian }
        set { languageRaw = newValue.rawValue }
    }

    var source: CaptureSource {
        get { CaptureSource(rawValue: sourceRaw) ?? .slack }
        set { sourceRaw = newValue.rawValue }
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var filteredRecordings: [Recording] { filterRecordings(searchQuery) }

    func filterRecordings(_ query: String) -> [Recording] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return recordings }
        return recordings.filter { recording in
            recording.id.lowercased().contains(query)
                || transcriptText(for: recording).lowercased().contains(query)
        }
    }

    private var recorder: CallRecorder?
    private var currentFolder: URL?
    private var timer: Timer?
    private var hotKey: HotKeyManager?
    private var transcriptCache: [String: String] = [:]

    init() {
        recordings = RecordingStore.loadAll()
        Task { await Summarizer.detect() }
        hotKey = HotKeyManager { [weak self] in
            Task { @MainActor in self?.toggleRecording() }
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        switch phase {
        case .idle: startRecording()
        case .recording: stopRecording()
        case .stopping: break
        }
    }

    func startRecording() {
        guard case .idle = phase else { return }
        lastError = nil
        Task {
            guard let folder = try? RecordingStore.newRecordingFolder() else {
                lastError = "Could not create the recording folder."
                return
            }
            do {
                let recorder = CallRecorder(outputURL: folder.appendingPathComponent("recording.mov"))
                recorder.onStreamStopped = { [weak self] error in
                    Task { @MainActor in
                        // The stream died from the outside (a revoked permission, for instance).
                        guard let self, self.isRecording else { return }
                        self.lastError = error?.localizedDescription
                        self.stopRecording()
                    }
                }
                try await recorder.start(source: source)

                self.recorder = recorder
                self.currentFolder = folder
                self.phase = .recording(since: Date())
                self.startTimer(since: Date())
                self.playSound("Pop")

                let meta = RecordingMeta(date: Date(), language: language.rawValue, duration: nil, status: .recording)
                RecordingStore.saveMeta(meta, in: folder)
            } catch {
                self.lastError = error.localizedDescription
                self.phase = .idle
                // Recording never started — do not keep the empty folder.
                let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?
                    .filter { $0 != ".DS_Store" } ?? []
                if contents.isEmpty {
                    try? FileManager.default.removeItem(at: folder)
                }
            }
        }
    }

    func stopRecording() {
        guard case .recording(let since) = phase, let recorder, let folder = currentFolder else { return }
        phase = .stopping
        stopTimer()
        let recordedLanguage = language

        Task {
            var meta = RecordingMeta(
                date: since,
                language: recordedLanguage.rawValue,
                duration: Date().timeIntervalSince(since),
                status: .recorded
            )
            do {
                _ = try await recorder.stop()
            } catch {
                meta.status = .failed
                meta.errorMessage = error.localizedDescription
                lastError = error.localizedDescription
            }
            RecordingStore.saveMeta(meta, in: folder)

            self.recorder = nil
            self.currentFolder = nil
            self.phase = .idle
            self.playSound("Glass")

            var recording = Recording(folder: folder, meta: meta)
            recordings.insert(recording, at: 0)

            if meta.status == .recorded {
                recording = await transcribe(recording, language: recordedLanguage)
            }
        }
    }

    // MARK: - Transcription

    @discardableResult
    func transcribe(_ recording: Recording, language: TranscriptLanguage) async -> Recording {
        var updated = recording
        updated.meta.status = .transcribing
        updated.meta.errorMessage = nil
        apply(updated)

        do {
            _ = try await Transcriber.transcribe(
                movie: recording.movieURL,
                language: language,
                into: recording.folder
            )
            updated.meta.status = .done
        } catch {
            updated.meta.status = .failed
            updated.meta.errorMessage = error.localizedDescription
        }
        apply(updated)
        return updated
    }

    func retryTranscription(_ recording: Recording) {
        let language = TranscriptLanguage(rawValue: recording.meta.language) ?? self.language
        Task { await transcribe(recording, language: language) }
    }

    // MARK: - Summary

    func generateSummary(_ recording: Recording) {
        guard !summarizing.contains(recording.id), recording.hasTranscript else { return }
        summarizing.insert(recording.id)
        let language = TranscriptLanguage(rawValue: recording.meta.language) ?? self.language
        Task {
            do {
                _ = try await Summarizer.summarize(
                    transcriptURL: recording.transcriptURL,
                    language: language,
                    into: recording.folder
                )
            } catch {
                lastError = error.localizedDescription
            }
            summarizing.remove(recording.id)
            refreshViewer(recording)
        }
    }

    // MARK: - List

    private func apply(_ recording: Recording) {
        RecordingStore.saveMeta(recording.meta, in: recording.folder)
        transcriptCache[recording.id] = nil
        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index] = recording
        }
        refreshViewer(recording)
    }

    private func refreshViewer(_ recording: Recording) {
        if viewingRecording?.id == recording.id {
            viewingRecording = recordings.first { $0.id == recording.id } ?? recording
        } else {
            objectWillChange.send() // refresh the summary buttons in the list
        }
    }

    func transcriptText(for recording: Recording) -> String {
        if let cached = transcriptCache[recording.id] { return cached }
        let text = (try? String(contentsOf: recording.transcriptURL, encoding: .utf8)) ?? ""
        transcriptCache[recording.id] = text
        return text
    }

    func summaryText(for recording: Recording) -> String? {
        guard recording.hasSummary else { return nil }
        return try? String(contentsOf: recording.summaryURL, encoding: .utf8)
    }

    func delete(_ recording: Recording) {
        try? FileManager.default.trashItem(at: recording.folder, resultingItemURL: nil)
        recordings.removeAll { $0.id == recording.id }
        transcriptCache[recording.id] = nil
        if viewingRecording?.id == recording.id {
            viewingRecording = nil
        }
    }

    // MARK: - Settings

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Helpers

    private func startTimer(since: Date) {
        elapsedText = "00:00"
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .recording(let start) = self.phase else { return }
                let seconds = max(0, Int(Date().timeIntervalSince(start)))
                self.elapsedText = seconds >= 3600
                    ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
                    : String(format: "%02d:%02d", seconds / 60, seconds % 60)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        elapsedText = ""
    }

    private func playSound(_ name: String) {
        guard soundsEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// Copies the summary as a chat-ready message rather than raw markdown.
    /// Returns false when there is no summary to copy.
    @discardableResult
    func copySummaryAsMessage(_ recording: Recording) -> Bool {
        guard let summary = summaryText(for: recording) else { return false }
        let language = TranscriptLanguage(rawValue: recording.meta.language) ?? self.language
        let message = SummaryFormatter.message(
            summary: summary, recording: recording, language: language
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message, forType: .string)
        return true
    }

    func openTranscript(_ recording: Recording) {
        NSWorkspace.shared.open(recording.transcriptURL)
    }

    func openFolder(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.movieURL])
    }

    func openBaseFolder() {
        try? FileManager.default.createDirectory(at: RecordingStore.baseFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(RecordingStore.baseFolder)
    }
}
