import SwiftUI
import AppKit

/// The main window: recordings on the left, the selected one on the right. This replaces
/// the separate transcript and history windows — the menu bar popover stays as quick access.
struct MainWindowView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var models: ModelDownloader
    @EnvironmentObject var permissions: PermissionsModel
    @EnvironmentObject var summarizer: SummarizerAvailability

    @State private var query = ""
    @State private var selection: String?

    private var recordings: [Recording] { state.filterRecordings(query) }

    private var selected: Recording? {
        guard let selection else { return nil }
        return state.recordings.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            detail
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear { syncSelection() }
        // Opening a recording from the menu bar selects it here.
        .onChange(of: state.viewingRecording?.id) { _, id in
            if let id { selection = id }
        }
        .onChange(of: state.recordings.count) { _, _ in syncSelection() }
    }

    /// Keeps a selection alive: after a delete, or on first open, fall back to the newest.
    private func syncSelection() {
        if let selection, state.recordings.contains(where: { $0.id == selection }) { return }
        selection = state.viewingRecording?.id ?? state.recordings.first?.id
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            RecordPanel()
                .padding(12)

            Divider()

            if state.recordings.isEmpty {
                emptyState
            } else {
                searchField
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                List(selection: $selection) {
                    ForEach(recordings) { recording in
                        SidebarRow(recording: recording)
                            .tag(recording.id)
                    }
                }
                .listStyle(.sidebar)

                if recordings.isEmpty {
                    Text("Nothing found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search transcripts", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("No recordings yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Press record, or ⌘⇧R from anywhere.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selected {
            RecordingDetailView(recording: selected)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 42))
                    .foregroundStyle(.tertiary)
                Text(state.recordings.isEmpty ? "Record your first call" : "Select a recording")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Sidebar row

/// Denser than the menu bar row: the window shows more of them at once.
private struct SidebarRow: View {
    @EnvironmentObject var state: AppState
    let recording: Recording

    var body: some View {
        HStack(spacing: 9) {
            statusIcon.frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(recording.meta.date, format: .dateTime.day().month().hour().minute())
                    .font(.callout.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contextMenu {
            if recording.meta.status == .transcribing {
                Button("Stop transcription") { state.cancelTranscription(recording) }
                Button("Restart transcription") { state.retryTranscription(recording) }
            } else if recording.meta.status != .done {
                Button("Transcribe") { state.retryTranscription(recording) }
            }
            if recording.hasSummary {
                Button("Copy notes") { state.copySummaryAsMessage(recording) }
            }
            Button("Reveal in Finder") { state.openFolder(recording) }
            Divider()
            Button("Move to Trash", role: .destructive) { state.delete(recording) }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch recording.meta.status {
        case .done:
            Image(systemName: recording.hasSummary ? "sparkles" : "checkmark.circle.fill")
                .foregroundStyle(recording.hasSummary ? AnyShapeStyle(.purple) : AnyShapeStyle(.green))
        case .transcribing:
            ProgressView().controlSize(.mini)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .recorded, .recording:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let duration = recording.meta.duration {
            parts.append(String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60))
        }
        parts.append(recording.meta.language.uppercased())
        switch recording.meta.status {
        case .transcribing:
            if let progress = state.transcriptionProgress[recording.id] {
                parts.append("\(Int(progress.overall * 100))%")
            } else {
                parts.append("transcribing")
            }
        case .failed: parts.append("failed")
        case .recorded: parts.append("no transcript")
        default: break
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Record panel

/// The record control, shared in spirit with the menu bar but laid out for a window.
private struct RecordPanel: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var permissions: PermissionsModel

    var body: some View {
        VStack(spacing: 10) {
            if permissions.allGranted {
                HStack(spacing: 12) {
                    Button(action: state.toggleRecording) {
                        Image(systemName: state.isRecording ? "stop.fill" : "record.circle")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .background(state.isRecording ? Color.red : Color.indigo, in: Circle())
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(state.phase == .stopping)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.isRecording ? state.elapsedText : "Ready")
                            .font(state.isRecording
                                  ? .system(.title3, design: .monospaced).weight(.semibold)
                                  : .callout.weight(.medium))
                            .foregroundStyle(state.isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                        Text("⌘⇧R from anywhere")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                sourcePicker
            } else {
                Label("Grant screen and microphone access in the menu bar", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sourcePicker: some View {
        Picker("", selection: Binding(
            get: { state.source },
            set: { state.source = $0 }
        )) {
            ForEach(CaptureSource.allCases) { source in
                Text(source.title).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(state.isRecording)
    }
}
