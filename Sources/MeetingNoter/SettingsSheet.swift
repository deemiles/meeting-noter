import SwiftUI

/// Settings as a sheet on the main window. The menu bar keeps its own compact copy;
/// this one has room to explain itself.
struct SettingsSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var updater: UpdaterViewModel
    @EnvironmentObject var summarizer: SummarizerAvailability
    @EnvironmentObject var permissions: PermissionsModel

    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Recording") {
                        toggle("Play a sound when recording starts and stops",
                               isOn: Binding(get: { state.soundsEnabled },
                                             set: { state.soundsEnabled = $0 }))
                        toggle("Launch Meeting Noter at login",
                               isOn: Binding(get: { state.launchAtLogin },
                                             set: { state.setLaunchAtLogin($0) }))
                        row(label: "Transcript language") {
                            Picker("", selection: Binding(get: { state.language },
                                                          set: { state.language = $0 })) {
                                ForEach(TranscriptLanguage.allCases) { language in
                                    Text(language.title).tag(language)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                        }
                    }

                    section("Permissions") {
                        ForEach(Permission.allCases) { permission in
                            row(label: permission.title) {
                                switch permissions.state(of: permission) {
                                case .granted, .needsRestart:
                                    Label("Granted", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                case .notDetermined:
                                    Button("Allow") { permissions.request(permission) }
                                case .denied:
                                    Button("Open Settings") { permissions.openSettings(for: permission) }
                                }
                            }
                        }
                    }

                    section("Summaries") {
                        row(label: "Claude Code CLI") {
                            if summarizer.isDetecting {
                                ProgressView().controlSize(.small)
                            } else if summarizer.isAvailable {
                                Label("Found", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                HStack(spacing: 8) {
                                    Button("Locate…") { Task { await summarizer.chooseManually() } }
                                    Button("Look again") { Task { await summarizer.detect() } }
                                }
                            }
                        }
                        if let path = summarizer.claudePath {
                            Text(path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .textSelection(.enabled)
                        } else {
                            Text("Summaries are optional — recording, transcription and search all work without Claude Code.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let error = summarizer.error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }

                    section("Updates") {
                        toggle("Check for updates automatically",
                               isOn: $updater.automaticallyChecksForUpdates)
                        row(label: "Version \(updater.versionText)") {
                            Button("Check Now") { updater.checkForUpdates() }
                                .disabled(!updater.canCheckForUpdates)
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 520, height: 540)
    }

    private var header: some View {
        HStack {
            Text("Settings").font(.headline)
            Spacer()
            Button("Done") { isPresented = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.callout)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func row<Trailing: View>(
        label: String, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer(minLength: 12)
            trailing()
        }
        .controlSize(.small)
    }
}
