import SwiftUI
import AppKit

struct HistoryWindowView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""

    private var filtered: [Recording] {
        state.filterRecordings(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            searchField

            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filtered) { recording in
                            RecordingRow(recording: recording) {
                                state.viewingRecording = recording
                                openWindow(id: "viewer")
                                NSApp.activate(ignoringOtherApps: true)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(18)
        .frame(minWidth: 460, minHeight: 420)
        .background(alignment: .top) {
            LinearGradient(
                colors: [.indigo.opacity(0.16), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 160)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording history")
                    .font(.title2.weight(.semibold))
                Text(stats)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                state.openBaseFolder()
            } label: {
                Label("Folder", systemImage: "folder")
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private var stats: String {
        let count = state.recordings.count
        let totalSeconds = state.recordings.compactMap(\.meta.duration).reduce(0, +)
        let minutes = Int(totalSeconds) / 60
        let withTranscript = state.recordings.filter { $0.meta.status == .done }.count
        return "\(count) recordings · \(minutes) min · \(withTranscript) transcribed"
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search by date or transcript contents…", text: $query)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "tray" : "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "No recordings yet" : "Nothing found")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
