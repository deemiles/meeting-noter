import SwiftUI
import AppKit

struct TranscriptWindowView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if let recording = state.viewingRecording {
                content(recording)
            } else {
                placeholder
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Pick a recording in the Meeting Noter menu")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ recording: Recording) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(recording)

                if let summary = state.summaryText(for: recording) {
                    summaryCard(summary)
                }

                transcriptCard(recording)
            }
            .padding(20)
        }
        .background(alignment: .top) {
            LinearGradient(
                colors: [.indigo.opacity(0.15), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
        }
    }

    // MARK: - Header

    private func header(_ recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recording.meta.date, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                .font(.title2.weight(.semibold))

            HStack(spacing: 8) {
                if let duration = recording.meta.duration {
                    infoChip(icon: "clock", text: durationString(duration))
                }
                infoChip(icon: "globe", text: recording.meta.language.uppercased())

                Spacer()

                if Summarizer.isAvailable, recording.hasTranscript {
                    if state.summarizing.contains(recording.id) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Claude is thinking…").font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    } else {
                        glassButton(
                            recording.hasSummary ? "Refresh summary" : "Summarize",
                            icon: "sparkles",
                            tint: .purple
                        ) {
                            state.generateSummary(recording)
                        }
                    }
                }

                glassButton("Copy", icon: "doc.on.doc") {
                    copyTranscript(recording)
                }
                glassButton("Finder", icon: "folder") {
                    state.openFolder(recording)
                }
            }
        }
    }

    private func infoChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }

    private func glassButton(_ title: String, icon: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(tint == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
        }
        .buttonStyle(.plain)
        .glassEffect(
            tint.map { Glass.regular.tint($0).interactive() } ?? .regular.interactive(),
            in: .capsule
        )
    }

    // MARK: - Cards

    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Summary", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.purple)
            Text(markdown(summary))
                .font(.body)
                .lineSpacing(3)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.purple.opacity(0.12)), in: .rect(cornerRadius: 18))
    }

    private func transcriptCard(_ recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Transcript", systemImage: "text.alignleft")
                .font(.headline)

            if recording.hasTranscript {
                Text(state.transcriptText(for: recording))
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(transcriptPlaceholder(recording))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    // MARK: - Helpers

    private func transcriptPlaceholder(_ recording: Recording) -> String {
        switch recording.meta.status {
        case .transcribing: return "Transcription in progress…"
        case .failed: return "Failed: \(recording.meta.errorMessage ?? "unknown")"
        default: return "No transcript yet."
        }
    }

    private func copyTranscript(_ recording: Recording) {
        var text = state.transcriptText(for: recording)
        if let summary = state.summaryText(for: recording) {
            text = summary + "\n\n---\n\n" + text
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func durationString(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return minutes >= 60
            ? String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(text)
    }
}
