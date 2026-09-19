import SwiftUI
import AppKit

/// The right-hand pane of the main window: everything about one recording.
struct RecordingDetailView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var summarizer: SummarizerAvailability
    @State private var copied: Copied?

    let recording: Recording

    private enum Copied { case notes, all }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if state.summarizing.contains(recording.id) {
                    thinkingCard
                } else if let summary = state.summaryText(for: recording) {
                    summaryCard(summary)
                } else if recording.hasTranscript, summarizer.isAvailable {
                    summaryInvite
                }

                transcriptCard
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 22)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(detailBackground)
    }

    private var detailBackground: some View {
        LinearGradient(
            colors: [.indigo.opacity(0.13), .purple.opacity(0.04), .clear],
            startPoint: .topLeading,
            endPoint: .bottom
        )
        .frame(maxHeight: 320, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recording.meta.date, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                .font(.system(.title2, design: .rounded).weight(.semibold))

            HStack(spacing: 7) {
                if let duration = recording.meta.duration {
                    chip(icon: "clock", text: durationString(duration))
                }
                chip(icon: "globe", text: recording.meta.language.uppercased())
                if recording.hasSummary {
                    chip(icon: "sparkles", text: "Summary", tint: .purple)
                }
                Spacer(minLength: 0)
            }

            actionBar
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            if summarizer.isAvailable, recording.hasTranscript {
                action(
                    recording.hasSummary ? "Refresh summary" : "Summarize",
                    icon: "sparkles",
                    tint: .purple,
                    busy: state.summarizing.contains(recording.id)
                ) { state.generateSummary(recording) }
            }

            if recording.hasSummary {
                action(copied == .notes ? "Copied" : "Copy notes",
                       icon: copied == .notes ? "checkmark" : "text.badge.checkmark") {
                    state.copySummaryAsMessage(recording)
                    flash(.notes)
                }
            }

            if recording.hasTranscript {
                action(copied == .all ? "Copied" : "Copy all",
                       icon: copied == .all ? "checkmark" : "doc.on.doc") {
                    copyTranscript()
                    flash(.all)
                }
            }

            action("Show in Finder", icon: "folder") { state.openFolder(recording) }
            Spacer(minLength: 0)
        }
    }

    private func flash(_ which: Copied) {
        withAnimation(.spring(duration: 0.25)) { copied = which }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.3)) { copied = nil }
        }
    }

    // MARK: - Summary

    private var thinkingCard: some View {
        card(title: "Summary", icon: "sparkles", tint: .purple) {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("Claude is reading the transcript…")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    /// Shown when a transcript exists but no summary does — the action is worth inviting
    /// rather than leaving it to be discovered in the row of buttons above.
    private var summaryInvite: some View {
        Button {
            state.generateSummary(recording)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Summarize this call").font(.callout.weight(.medium))
                    Text("Topics, decisions and action items via Claude.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.purple.opacity(0.12)).interactive(), in: .rect(cornerRadius: 16))
    }

    private func summaryCard(_ summary: String) -> some View {
        card(title: "Summary", icon: "sparkles", tint: .purple) {
            SummaryBody(text: summary)
        }
    }

    // MARK: - Transcript

    private var transcriptCard: some View {
        card(title: "Transcript", icon: "text.alignleft", tint: nil) {
            if recording.hasTranscript {
                TranscriptBody(text: state.transcriptText(for: recording))
            } else {
                transcriptPlaceholder
            }
        }
    }

    @ViewBuilder
    private var transcriptPlaceholder: some View {
        switch recording.meta.status {
        case .transcribing:
            VStack(alignment: .leading, spacing: 10) {
                if let progress = state.transcriptionProgress[recording.id] {
                    ProgressView(value: progress.overall).progressViewStyle(.linear)
                    HStack(spacing: 8) {
                        Text("\(Int(progress.overall * 100))%")
                            .font(.callout.monospacedDigit().weight(.medium))
                        if progress.trackCount > 1 {
                            Text("track \(min(progress.trackIndex + 1, progress.trackCount)) of \(progress.trackCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restart") { state.retryTranscription(recording) }.buttonStyle(.link)
                        Button("Stop") { state.cancelTranscription(recording) }.buttonStyle(.link)
                    }
                    .font(.caption)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Starting transcription…").foregroundStyle(.secondary)
                    }
                }
            }
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Label(recording.meta.errorMessage ?? "Transcription failed",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { state.retryTranscription(recording) }
                    .buttonStyle(.link)
            }
        default:
            HStack(spacing: 10) {
                Text("No transcript yet.").foregroundStyle(.secondary)
                Button("Transcribe") { state.retryTranscription(recording) }
                    .buttonStyle(.link)
            }
        }
    }

    // MARK: - Building blocks

    private func card<Content: View>(
        title: String, icon: String, tint: Color?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint ?? .primary)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            tint.map { .regular.tint($0.opacity(0.10)) } ?? .regular,
            in: .rect(cornerRadius: 18)
        )
    }

    private func chip(icon: String, text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption)
        }
        .foregroundStyle(tint ?? .secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
    }

    private func action(
        _ title: String, icon: String, tint: Color? = nil, busy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: icon).font(.caption)
                }
                Text(title).font(.callout)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(tint == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .glassEffect(
            tint.map { Glass.regular.tint($0).interactive() } ?? .regular.interactive(),
            in: .capsule
        )
    }

    // MARK: - Helpers

    private func copyTranscript() {
        var text = state.transcriptText(for: recording)
        if let summary = state.summaryText(for: recording) {
            text = summary + "\n\n---\n\n" + text
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func durationString(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return minutes >= 60
            ? String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Summary rendering

/// Inline-only markdown keeps line breaks but renders "## Topics" literally, so headings
/// and bullets are laid out here while inline styling is still parsed.
private struct SummaryBody: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(text.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    Spacer().frame(height: 3)
                } else if line.hasPrefix("#") {
                    Text(inlineMarkdown(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 5)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                    bullet(String(line.dropFirst(2)))
                } else if let match = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                    bullet(String(line[match.upperBound...]))
                } else if line.allSatisfy({ $0 == "-" }) && line.count >= 3 {
                    Divider().padding(.vertical, 2)
                } else {
                    Text(inlineMarkdown(line))
                }
            }
        }
        .font(.callout)
        .lineSpacing(3)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(_ content: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(.tertiary)
                .frame(width: 4, height: 4)
                .offset(y: -3)
            Text(inlineMarkdown(content))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 3)
    }
}

// MARK: - Transcript rendering

/// A transcript is `[mm:ss] Speaker: line`. Rendering it as one blob wastes the structure
/// that the two-track pipeline worked to produce.
private struct TranscriptBody: View {
    let text: String

    private struct Line: Identifiable {
        let id: Int
        let time: String
        let speaker: String?
        let body: String
        /// Speakers alternate colour so a conversation is scannable; which speaker gets
        /// which colour is decided by first appearance, since the labels are localised.
        var isFirstSpeaker = false
    }

    private var lines: [Line] {
        var firstSpeaker: String?
        return text.components(separatedBy: .newlines)
            .enumerated()
            .compactMap { index, raw -> Line? in
                let raw = raw.trimmingCharacters(in: .whitespaces)
                guard !raw.isEmpty else { return nil }

                guard raw.hasPrefix("["), let close = raw.firstIndex(of: "]") else {
                    return Line(id: index, time: "", speaker: nil, body: raw)
                }
                let time = String(raw[raw.index(after: raw.startIndex)..<close])
                let rest = raw[raw.index(after: close)...].trimmingCharacters(in: .whitespaces)

                guard let colon = rest.firstIndex(of: ":"),
                      rest.distance(from: rest.startIndex, to: colon) <= 20 else {
                    return Line(id: index, time: time, speaker: nil, body: rest)
                }
                let speaker = String(rest[..<colon])
                let body = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if firstSpeaker == nil { firstSpeaker = speaker }
                return Line(id: index, time: time, speaker: speaker, body: body,
                            isFirstSpeaker: speaker == firstSpeaker)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(line.time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 42, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 1) {
                        if let speaker = line.speaker {
                            Text(speaker)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(line.isFirstSpeaker ? Color.purple : Color.green)
                        }
                        Text(line.body)
                            .font(.callout)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

/// Parses **bold** and `code` while leaving block syntax alone.
private func inlineMarkdown(_ text: String) -> AttributedString {
    (try? AttributedString(
        markdown: text,
        options: AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
    )) ?? AttributedString(text)
}
