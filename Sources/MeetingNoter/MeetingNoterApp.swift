import SwiftUI
import AppKit

/// Closes the main window when the app was started by the login item, and brings it back
/// when the Dock icon is clicked. SwiftUI opens a Window scene at launch by default; there
/// is no supported way to open one later from AppKit, so it is opened and then dismissed.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set from the App's init, before the delegate callbacks run.
    static var openWindowAtLaunch = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await AppEnvironment.shared.summarizer.detect()
        }
        guard Self.openWindowAtLaunch else { return }
        MainWindowController.shared.show()
    }

    /// Closing the window must leave the app in the menu bar, not quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon with no window open brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowController.shared.show() }
        return true
    }
}

@main
struct MeetingNoterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Observed rather than owned: AppEnvironment holds them so the window controller can
    // build its view before any SwiftUI view exists.
    @ObservedObject private var state = AppEnvironment.shared.state
    @ObservedObject private var updater = AppEnvironment.shared.updater
    private var summarizer: SummarizerAvailability { AppEnvironment.shared.summarizer }

    init() {
        Self.runCLIIfNeeded()
        AppDelegate.openWindowAtLaunch = Self.shouldOpenWindowAtLaunch
    }

    /// Opening the window on a login-item launch would put a window in the user's face
    /// every morning, which is the opposite of what a menu bar app is for.
    private static var shouldOpenWindowAtLaunch: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAsLoginItem = event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?
                .enumCodeValue == AEEventID(keyAELaunchedAsLogInItem)
        return !launchedAsLoginItem
    }

    var body: some Scene {
        MenuBarExtra {
            AppEnvironment.shared.inject(MenuView())
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
