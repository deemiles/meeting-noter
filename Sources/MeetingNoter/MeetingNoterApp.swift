import SwiftUI

@main
struct MeetingNoterApp: App {
    @StateObject private var state = AppState()
    @StateObject private var updater = UpdaterViewModel()

    init() {
        Self.runCLIIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(state)
                .environmentObject(updater)
        } label: {
            // While recording, the menu bar shows a timer.
            if state.isRecording {
                Image(systemName: "record.circle.fill")
                Text(state.elapsedText)
            } else {
                Image(systemName: "waveform.circle")
            }
        }
        .menuBarExtraStyle(.window)

        Window("Transcript — Meeting Noter", id: "viewer") {
            TranscriptWindowView()
                .environmentObject(state)
        }
        .defaultSize(width: 660, height: 760)

        Window("History — Meeting Noter", id: "history") {
            HistoryWindowView()
                .environmentObject(state)
        }
        .defaultSize(width: 520, height: 640)
    }

    /// Headless mode: `MeetingNoter --retranscribe <recording folder> [ru|en]`.
    private static func runCLIIfNeeded() {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--retranscribe"),
              arguments.count > flagIndex + 1 else { return }

        let folder = URL(fileURLWithPath: arguments[flagIndex + 1])
        let language = arguments.count > flagIndex + 2
            ? (TranscriptLanguage(rawValue: arguments[flagIndex + 2]) ?? .russian)
            : .russian

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
