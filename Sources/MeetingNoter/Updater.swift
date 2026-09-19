import SwiftUI
import Sparkle
import UserNotifications
import AppKit

/// Sparkle auto-updates. The app is a menu bar accessory, so there is no main menu to
/// hang "Check for Updates…" on — the button lives in the settings section instead.
@MainActor
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    /// Set when this launch is the first after an update, so the menu can say so.
    @Published private(set) var installedVersion: String?

    /// Drives the checkmark on the menu bar icon. Cleared as soon as the menu is opened,
    /// while the banner stays for that session — a badge that nags until it is explicitly
    /// dismissed is worse than one that disappears once you have looked.
    @Published private(set) var showsUpdateBadge = false

    /// Sparkle's own "update installed" callback only fires while its process is still
    /// alive, which a relaunching menu bar app cannot rely on. Comparing the version
    /// across launches is what actually survives the restart.
    @AppStorage("lastRunVersion") private var lastRunVersion = ""

    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true begins the background check cycle on launch.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        detectUpdate()
    }

    private func detectUpdate() {
        let current = Self.currentVersion
        defer { lastRunVersion = current }

        // An empty stored version means a first install, not an update.
        guard !lastRunVersion.isEmpty, lastRunVersion != current else { return }
        installedVersion = current
        showsUpdateBadge = true
        notifyUpdateInstalled(from: lastRunVersion, to: current)
    }

    /// A menu bar app shows nothing on relaunch, so post a notification too — the banner
    /// in the menu is only seen if the user happens to open it.
    private func notifyUpdateInstalled(from previous: String, to current: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Meeting Noter updated"
            content.body = "Now running \(current), up from \(previous)."
            content.sound = .default
            center.add(UNNotificationRequest(
                identifier: "update-installed-\(current)",
                content: content,
                trigger: nil
            ))
        }
    }

    /// The menu has been opened, so the badge has done its job.
    func markUpdateSeen() {
        showsUpdateBadge = false
    }

    func dismissInstalledBanner() {
        installedVersion = nil
        showsUpdateBadge = false
    }

    static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Version string for the settings footer, e.g. "1.0 (3)".
    var versionText: String { Self.currentVersion }
}
