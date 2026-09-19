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
    @State private var showingSettings = false

    private var results: [Recording] { state.filterRecordings(query) }

    private var selected: Recording? {
        guard let selection else { return nil }
        return state.recordings.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 264, ideal: 296, max: 400)
        } detail: {
            detail
        }
        .frame(minWidth: 880, minHeight: 580)
        .onAppear { syncSelection() }
        .onChange(of: state.viewingRecording?.id) { _, id in if let id { selection = id } }
        .onChange(of: state.recordings.count) { _, _ in syncSelection() }
        .sheet(isPresented: $showingSettings) {
            AppEnvironment.shared.inject(SettingsSheet(isPresented: $showingSettings))
        }
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
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if !state.recordings.isEmpty {
                searchField
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            Divider().opacity(0.5)

            if state.recordings.isEmpty {
                emptyLibrary
            } else if results.isEmpty {
                noResults
            } else {
                list
            }

            Divider().opacity(0.5)
            sidebarFooter
        }
        .background(.ultraThinMaterial)
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(DateGroup.group(results), id: \.title) { group in
                Section {
                    ForEach(group.recordings) { recording in
                        SidebarRow(recording: recording)
                            .tag(recording.id)
                    }
                } header: {
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField("Search transcripts", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private var emptyLibrary: some View {
        VStack(spacing: 7) {
            Image(systemName: "waveform")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("No recordings yet").font(.callout.weight(.medium))
            Text("Press record, or ⌘⇧R from\nany app during a call.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var noResults: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.tertiary)
            Text("Nothing matches “\(query)”")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape").font(.callout).padding(5)
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button { state.openBaseFolder() } label: {
                Image(systemName: "folder").font(.callout).padding(5)
            }
            .buttonStyle(.plain)
            .help("Show recordings folder")

            Spacer()

            Text("\(state.recordings.count) \(state.recordings.count == 1 ? "recording" : "recordings")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selected {
            RecordingDetailView(recording: selected)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 46))
                    .foregroundStyle(.tertiary)
                Text(state.recordings.isEmpty ? "Record your first call" : "Select a recording")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                if state.recordings.isEmpty {
                    Text("Slack, Teams, Google Meet or the whole screen.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Date grouping

/// "Today / Yesterday / This week / older months" reads better than a flat wall of dates.
private struct DateGroup {
    let title: String
    let recordings: [Recording]

    static func group(_ recordings: [Recording]) -> [DateGroup] {
        let calendar = Calendar.current
        var order: [String] = []
        var buckets: [String: [Recording]] = [:]

        for recording in recordings {
            let title = label(for: recording.meta.date, calendar: calendar)
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(recording)
        }
        return order.map { DateGroup(title: $0, recordings: buckets[$0] ?? []) }
    }

    private static func label(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let week = calendar.dateInterval(of: .weekOfYear, for: Date()), week.contains(date) {
            return "This week"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
            ? "MMMM" : "MMMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Sidebar row

private struct SidebarRow: View {
    @EnvironmentObject var state: AppState
    let recording: Recording

    var body: some View {
        HStack(spacing: 10) {
            statusIcon.frame(width: 15)

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.meta.date, format: .dateTime.hour().minute())
                    .font(.callout.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            if recording.meta.status == .transcribing,
               let progress = state.transcriptionProgress[recording.id] {
                Text("\(Int(progress.overall * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu { menu }
    }

    @ViewBuilder
    private var menu: some View {
        if recording.meta.status == .transcribing {
            Button("Stop transcription") { state.cancelTranscription(recording) }
            Button("Restart transcription") { state.retryTranscription(recording) }
        } else if recording.meta.status != .done {
            Button("Transcribe") { state.retryTranscription(recording) }
        }
        if recording.hasSummary {
            Button("Copy notes") { state.copySummaryAsMessage(recording) }
        }
        Button("Show in Finder") { state.openFolder(recording) }
        Divider()
        Button("Move to Trash", role: .destructive) {
            withAnimation(.spring(duration: 0.3)) { state.delete(recording) }
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
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
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
        case .transcribing: parts.append("transcribing")
        case .failed: parts.append("failed")
        case .recorded: parts.append("no transcript")
        case .done where recording.hasSummary: parts.append("summarized")
        default: break
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Record panel

private struct RecordPanel: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var permissions: PermissionsModel

    var body: some View {
        VStack(spacing: 12) {
            if permissions.allGranted {
                HStack(spacing: 13) {
                    ZStack {
                        if state.isRecording { RecordingRings(diameter: 48) }
                        recordButton
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 2) {
                        if state.isRecording {
                            Text(state.elapsedText)
                                .font(.system(.title3, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.red)
                                .contentTransition(.numericText())
                        } else {
                            Text(state.phase == .stopping ? "Saving…" : "Ready")
                                .font(.callout.weight(.semibold))
                        }
                        Text(state.isRecording ? state.source.title : "⌘⇧R from anywhere")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                sourcePicker
            } else {
                permissionNotice
            }
        }
    }

    private var recordButton: some View {
        Button(action: state.toggleRecording) {
            Image(systemName: state.isRecording ? "stop.fill" : "record.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .background(state.isRecording ? Color.red : Color.indigo, in: Circle())
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(state.phase == .stopping)
        .animation(.spring(duration: 0.3), value: state.isRecording)
    }

    private var sourcePicker: some View {
        Picker("", selection: Binding(get: { state.source }, set: { state.source = $0 })) {
            ForEach(CaptureSource.allCases) { source in
                Text(source.title).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(state.isRecording)
        .opacity(state.isRecording ? 0.5 : 1)
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Permissions needed", systemImage: "lock.fill")
                .font(.caption.bold())
            Text("Grant screen and microphone access from the Meeting Noter menu bar icon.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.orange)
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.orange.opacity(0.18)), in: .rect(cornerRadius: 12))
    }
}

/// Rings radiating from the record button while capture is live.
private struct RecordingRings: View {
    let diameter: CGFloat
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<2) { index in
                Circle()
                    .stroke(.red.opacity(0.45), lineWidth: 2)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(animate ? 1.5 : 1)
                    .opacity(animate ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 1.8).repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.9),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}
