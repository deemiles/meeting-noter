import AppKit

/// The app ships as an accessory (LSUIElement) so it lives in the menu bar without a Dock
/// icon. A real window needs a Dock icon and an app menu, so the policy flips while one is
/// open and flips back when the last one closes.
@MainActor
enum ActivationPolicy {
    private static var openWindows = 0

    static func windowOpened() {
        openWindows += 1
        guard openWindows == 1 else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func windowClosed() {
        openWindows = max(0, openWindows - 1)
        guard openWindows == 0 else { return }
        // Deferred: closing happens mid-teardown, and switching policy synchronously there
        // leaves the Dock icon behind.
        Task { @MainActor in
            guard openWindows == 0 else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
