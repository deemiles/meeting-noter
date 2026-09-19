import SwiftUI

@main
struct MeetingNoterApp: App {
    @StateObject private var state = AppState()
    @StateObject private var updater = UpdaterViewModel()
    @StateObject private var models = ModelDownloader()
    @StateObject private var permissions = PermissionsModel()
    @StateObject private var summarizer = SummarizerAvailability()

    init() {
        Self.runCLIIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(state)
                .environmentObject(updater)
                .environmentObject(models)
                .environmentObject(permissions)
                .environmentObject(summarizer)
                .task { await summarizer.detect() }
        } label: {
            // While recording, the menu bar shows a timer. After an update the icon carries a
            // checkmark until the menu is opened — a relaunching menu bar app is otherwise
            // completely silent about having updated, and this needs no notification
            // permission to be noticed.
            if state.isRecording {
                Image(systemName: "record.circle.fill")
                Text(state.elapsedText)
            } else if updater.showsUpdateBadge {
                Image(systemName: "waveform.badge.checkmark")
            } else {
                Image(systemName: "waveform.circle")
            }
        }
        .menuBarExtraStyle(.window)

        Window("Transcript — Meeting Noter", id: "viewer") {
            TranscriptWindowView()
                .environmentObject(state)
                .environmentObject(summarizer)
        }
        .defaultSize(width: 660, height: 760)

        Window("History — Meeting Noter", id: "history") {
            HistoryWindowView()
                .environmentObject(state)
        }
        .defaultSize(width: 520, height: 640)
    }

    /// Headless mode: `MeetingNoter --retranscribe <recording folder> [uk|en|es|de|ru]`.
    private static func runCLIIfNeeded() {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--retranscribe"),
              arguments.count > flagIndex + 1 else { return }

        let folder = URL(fileURLWithPath: arguments[flagIndex + 1])
        let language = arguments.count > flagIndex + 2
            ? (TranscriptLanguage(rawValue: arguments[flagIndex + 2]) ?? .ukrainian)
            : .ukrainian

        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let transcriptURL = try await Transcriber.transcribe(
                    movie: folder.appendingPathComponent("recording.mov"),
                    language: language,
                    into: folder
                )
                print("OK: \(transcriptURL.path)")
            } catch {
                print("FAIL: \(error.localizedDescription)")
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }
}
