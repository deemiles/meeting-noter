import SwiftUI
import AVFoundation
import CoreGraphics
import AppKit

/// The two TCC permissions the recorder cannot work without. Requesting them up front,
/// with visible state, beats discovering a silent failure halfway into a call.
enum Permission: String, CaseIterable, Identifiable {
    case screen
    case microphone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screen: return "Screen & System Audio"
        case .microphone: return "Microphone"
        }
    }

    var explanation: String {
        switch self {
        case .screen: return "Captures the call window and what the other side says."
        case .microphone: return "Records your own voice as a separate track."
        }
    }

    var icon: String {
        switch self {
        case .screen: return "rectangle.inset.filled.badge.record"
        case .microphone: return "mic.fill"
        }
    }

    /// Deep link into the exact pane of System Settings, for when the prompt is spent.
    var settingsURL: URL? {
        switch self {
        case .screen:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        }
    }
}

enum PermissionState: Equatable {
    case granted
    case notDetermined      // the system prompt has not been shown yet
    case denied             // prompt spent or refused — only System Settings can fix it
    case needsRestart       // granted, but this process started before it was
}

@MainActor
final class PermissionsModel: ObservableObject {
    @Published private(set) var states: [Permission: PermissionState] = [:]

    /// macOS only ever shows the screen-recording prompt once per app version, so remember
    /// whether we have spent it — otherwise a refusal looks indistinguishable from "not asked".
    @AppStorage("askedForScreenAccess") private var askedForScreenAccess = false

    /// ScreenCaptureKit reads the permission at process start; granting it later does not
    /// reach the running process, so the app has to be relaunched.
    private let screenAccessAtLaunch: Bool

    private var timer: Timer?

    init() {
        screenAccessAtLaunch = CGPreflightScreenCaptureAccess()
        refresh()
    }

    var allGranted: Bool {
        Permission.allCases.allSatisfy { states[$0] == .granted }
    }

    /// True only when a relaunch is the single remaining step — otherwise the gate would
    /// claim "almost there" while another permission is still unanswered.
    var needsRestart: Bool {
        let settled = Permission.allCases.allSatisfy {
            states[$0] == .granted || states[$0] == .needsRestart
        }
        return settled && states.values.contains(.needsRestart)
    }

    /// The gate stays up until every permission is granted *and* no relaunch is pending.
    var blocksRecording: Bool {
        !allGranted
    }

    func state(of permission: Permission) -> PermissionState {
        states[permission] ?? .notDetermined
    }

    func refresh() {
        states[.screen] = screenState()
        states[.microphone] = microphoneState()
    }

    private func screenState() -> PermissionState {
        guard CGPreflightScreenCaptureAccess() else {
            return askedForScreenAccess ? .denied : .notDetermined
        }
        // Granted now, but this process was launched without it — capture would return
        // empty frames until the app restarts.
        return screenAccessAtLaunch ? .granted : .needsRestart
    }

    private func microphoneState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func request(_ permission: Permission) {
        switch permission {
        case .screen:
            // Marking the prompt as spent before asking means a refusal — or a prompt that
            // macOS silently declines to show a second time — flips the row to "Settings"
            // instead of leaving a button that appears to do nothing.
            askedForScreenAccess = true
            _ = CGRequestScreenCaptureAccess()
            refresh()
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func openSettings(for permission: Permission) {
        guard let url = permission.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Relaunches the app so ScreenCaptureKit picks up a freshly granted permission.
    func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL, configuration: configuration
        ) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    /// Permissions are granted in System Settings, outside the app, so poll while any are
    /// missing and stop once everything is in place.
    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                if self.allGranted && !self.needsRestart { self.stopPolling() }
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}

extension PermissionsModel {
    /// Cheap check for the code paths that bypass the menu — the global ⌘⇧R hotkey above all.
    static var recordingAllowed: Bool {
        CGPreflightScreenCaptureAccess()
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
