import SwiftUI

/// Owns the app's models. The window is created by AppKit before any SwiftUI view has
/// appeared, so the models cannot live as `@StateObject` on the App struct alone — the
/// window controller needs to reach them at launch.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let state = AppState()
    let updater = UpdaterViewModel()
    let models = ModelDownloader()
    let permissions = PermissionsModel()
    let summarizer = SummarizerAvailability()

    private init() {}

    /// Injects everything into a view, for both the menu bar and the window.
    func inject<Content: View>(_ content: Content) -> some View {
        content
            .environmentObject(state)
            .environmentObject(updater)
            .environmentObject(models)
            .environmentObject(permissions)
            .environmentObject(summarizer)
    }
}
