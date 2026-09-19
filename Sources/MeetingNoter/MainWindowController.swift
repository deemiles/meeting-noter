import AppKit
import SwiftUI

/// An accessory (LSUIElement) app does not get its SwiftUI `Window` scenes presented for
/// it, so the main window is created and owned here instead. That also keeps the Dock icon
/// in step: it appears while the window is up and goes away when it closes.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?

    func show() {
        if let window {
            present(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Meeting Noter"
        // The title is shown in the Dock and window menu, but drawing it over the detail
        // pane just leaves a band of dead space above the content.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 560)
        window.contentView = NSHostingView(rootView: AppEnvironment.shared.inject(MainWindowView()))
        window.center()
        window.setFrameAutosaveName("MeetingNoterMain")
        window.delegate = self
        self.window = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu bar app once the window is gone. Deferred because the Dock icon
        // lingers if the policy changes while the window is still tearing down.
        Task { @MainActor in
            guard self.window?.isVisible != true else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
