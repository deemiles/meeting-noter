import SwiftUI

struct MenuView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var updater: UpdaterViewModel
    @EnvironmentObject var models: ModelDownloader
    @Environment(\.openWindow) private var openWindow
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            recordPanel

            if !Transcriber.isReady || models.isDownloading {
                setupWarning
            }
            if let error = state.lastError {
                errorBanner(error)
            }

            pickers

            if showSettings {
                settings
            }

            recordingsSection
            footer
        }
        .padding(14)
        .frame(width: 344)
        .background(alignment: .top) { backdrop }
    }

    /// A soft colour glow underneath the glass.
    private var backdrop: some View {
        LinearGradient(
            colors: state.isRecording
                ? [.red.opacity(0.22), .orange.opacity(0.10), .clear]
                : [.indigo.opacity(0.22), .purple.opacity(0.10), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 190)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: state.isRecording)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(state.isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                .symbolEffect(.pulse, isActive: state.isRecording)
            Text("Meeting Noter")
                .font(.headline)
            Spacer()
            Button {
                withAnimation(.spring(duration: 0.3)) { showSettings.toggle() }
            } label: {
                Image(systemName: "gearshape")
                    .font(.callout)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .help("Settings")
        }
    }

    // MARK: - Record panel

    private var recordPanel: some View {
        VStack(spacing: 10) {
            ZStack {
                if state.isRecording {
                    PulsingRings()
                }
                recordButton
            }
            .frame(height: 86)
            .frame(maxWidth: .infinity)

            statusLine
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var recordButton: some View {
        Button {
            state.toggleRecording()
        } label: {
            Image(systemName: buttonSymbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(buttonTint).interactive(), in: .circle)
        .disabled(state.phase == .stopping)
        .keyboardShortcut("r")
        .animation(.spring(duration: 0.35), value: state.isRecording)
    }

    private var buttonSymbol: String {
        switch state.phase {
        case .idle: return "record.circle"
        case .recording: return "stop.fill"
        case .stopping: return "hourglass"
        }
    }

    private var buttonTint: Color {
        state.isRecording ? .red : .indigo
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state.phase {
        case .idle:
            Text("Ready · ⌘⇧R from anywhere")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .recording:
            HStack(spacing: 8) {
                WaveBars()
                Text(state.elapsedText)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.red)
                    .contentTransition(.numericText())
                WaveBars()
            }
        case .stopping:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Saving the recording…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Warnings

    /// Shown until a Whisper model exists on disk. Downloading one is the only setup step,
    /// and it happens here rather than in a terminal.
    @ViewBuilder
    private var setupWarning: some View {
        VStack(alignment: .leading, spacing: 10) {
            if models.isDownloading {
                HStack(spacing: 8) {
                    Label("Downloading speech model", systemImage: "arrow.down.circle")
                        .font(.caption.bold())
                    Spacer()
                    Button("Cancel") { models.cancel() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                ProgressView(value: models.progress)
                    .progressViewStyle(.linear)
                Text(models.progressText.isEmpty ? "Starting…" : models.progressText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Label("One-time setup", systemImage: "arrow.down.circle")
                    .font(.caption.bold())
                Text("Meeting Noter needs a speech model to transcribe. It stays on your Mac.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(WhisperModel.allCases) { model in
                    Button {
                        models.download(model)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(model.title).font(.callout.weight(.medium))
                                Text(model.subtitle).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.down.circle.fill").font(.callout)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 11))
                }
            }
            if let error = models.error {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.indigo.opacity(0.22)), in: .rect(cornerRadius: 14))
    }

    private func errorBanner(_ error: String) -> some View {
        Label(error, systemImage: "xmark.octagon.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(3)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.red.opacity(0.2)), in: .rect(cornerRadius: 14))
    }

    // MARK: - Language and source pickers

    private var pickers: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                languageMenu
                HStack(spacing: 6) {
                    ForEach(CaptureSource.allCases) { source in
                        chip(icon: source.icon, title: source.title, isSelected: state.source == source) {
                            state.source = source
                        }
                    }
                }
            }
        }
        .disabled(state.isRecording)
        .opacity(state.isRecording ? 0.5 : 1)
    }

    /// Five languages would overflow a row of chips, so the picker collapses into a menu.
    private var languageMenu: some View {
        Menu {
            ForEach(TranscriptLanguage.allCases) { language in
                Button {
                    state.language = language
                } label: {
                    if state.language == language {
                        Label(language.title, systemImage: "checkmark")
                    } else {
                        Text(language.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe").font(.caption)
                Text(state.language.title).font(.callout)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func chip(icon: String, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { action() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption)
                Text(title).font(.callout)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(.indigo).interactive() : .regular.interactive(),
            in: .capsule
        )
    }

    // MARK: - Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { state.soundsEnabled },
                set: { state.soundsEnabled = $0 }
            )) {
                Label("Start and stop sounds", systemImage: "speaker.wave.2")
            }
            Toggle(isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            )) {
                Label("Launch at login", systemImage: "power")
            }
            Toggle(isOn: $updater.automaticallyChecksForUpdates) {
                Label("Check for updates automatically", systemImage: "arrow.down.circle")
            }
            HStack(spacing: 6) {
                Image(systemName: Summarizer.isAvailable ? "sparkles" : "sparkles.slash")
                Text(Summarizer.isAvailable
                     ? "Summaries via Claude — available"
                     : "Summaries: Claude CLI not found")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .buttonStyle(.link)
                    .disabled(!updater.canCheckForUpdates)
                Spacer()
                Text("v\(updater.versionText)")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
        }
        .font(.callout)
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Recordings

    @ViewBuilder
    private var recordingsSection: some View {
        if state.recordings.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "tray")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("No recordings yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 10)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                searchField

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(state.filteredRecordings.prefix(20)) { recording in
                            RecordingRow(recording: recording) {
                                state.viewingRecording = recording
                                openWindow(id: "viewer")
                                NSApp.activate(ignoringOtherApps: true)
                            }
                        }
                        if state.filteredRecordings.isEmpty {
                            Text("Nothing found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }
                    }
                }
                // A ScrollView is infinitely flexible, and the popover sizes itself to its
                // content — together that collapses the list to zero height. Give it an
                // explicit height derived from the row count instead.
                .frame(height: listHeight)
            }
        }
    }

    /// Height for the recordings list: one row is ~62pt, capped so the menu stays compact.
    private var listHeight: CGFloat {
        let rows = max(1, min(state.filteredRecordings.count, 4))
        return min(CGFloat(rows) * 62, 250)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search transcripts…", text: $state.searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
            if !state.searchQuery.isEmpty {
                Button {
                    state.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "history")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Full history (\(state.recordings.count))", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.link)
            Spacer()
            Button("Folder") { state.openBaseFolder() }
                .buttonStyle(.link)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.link)
        }
        .font(.caption)
    }
}

// MARK: - Recording row

struct RecordingRow: View {
    @EnvironmentObject var state: AppState
    @State private var copiedSummary = false
    let recording: Recording
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 18)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.meta.date, format: .dateTime.day().month().hour().minute())
                        .font(.callout.weight(.medium))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            actions
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var actions: some View {
        if recording.meta.status == .failed || recording.meta.status == .recorded {
            iconButton("arrow.clockwise", help: "Transcribe again") {
                state.retryTranscription(recording)
            }
        }
        if recording.meta.status == .done, Summarizer.isAvailable, !recording.hasSummary {
            if state.summarizing.contains(recording.id) {
                ProgressView().controlSize(.mini)
            } else {
                iconButton("sparkles", help: "Summarize with Claude") {
                    state.generateSummary(recording)
                }
            }
        }
        if recording.hasSummary {
            iconButton(copiedSummary ? "checkmark" : "text.badge.checkmark",
                       help: "Copy notes as a message") {
                state.copySummaryAsMessage(recording)
                copiedSummary = true
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    copiedSummary = false
                }
            }
        }
        iconButton("folder", help: "Reveal in Finder") {
            state.openFolder(recording)
        }
        iconButton("trash", help: "Move to Trash") {
            withAnimation(.spring(duration: 0.3)) { state.delete(recording) }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch recording.meta.status {
        case .done:
            Image(systemName: recording.hasSummary ? "sparkles" : "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .transcribing:
            ProgressView().controlSize(.mini)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .recorded, .recording:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let duration = recording.meta.duration {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            parts.append(String(format: "%d:%02d", minutes, seconds))
        }
        parts.append(recording.meta.language.uppercased())
        switch recording.meta.status {
        case .transcribing: parts.append("transcribing…")
        case .failed: parts.append(recording.meta.errorMessage ?? "failed")
        case .recorded: parts.append("no transcript")
        case .done where recording.hasSummary: parts.append("summary ready")
        default: break
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Recording animations

/// Pulsing rings around the record button.
struct PulsingRings: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<2) { index in
                Circle()
                    .stroke(.red.opacity(0.45), lineWidth: 2)
                    .frame(width: 68, height: 68)
                    .scaleEffect(animate ? 1.55 : 1)
                    .opacity(animate ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 1.8)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.9),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

/// A tiny equaliser next to the timer.
struct WaveBars: View {
    @State private var animate = false
    private let heights: [CGFloat] = [10, 18, 13, 20, 9]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { index in
                Capsule()
                    .fill(.red.opacity(0.8))
                    .frame(width: 3, height: animate ? heights[index] : 5)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: animate
                    )
            }
        }
        .frame(height: 20)
        .onAppear { animate = true }
    }
}
