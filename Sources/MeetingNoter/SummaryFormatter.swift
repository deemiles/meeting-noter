import Foundation

/// Turns `summary.md` into a message you can paste straight into Slack, Telegram or email.
/// Markdown headings and bullets become plain lines with emoji section markers, because
/// most chat clients render raw `##` literally and it reads like a leaked file.
enum SummaryFormatter {
    private enum Section { case topics, decisions, actions, other }

    /// Recognises a heading in any supported language, so summaries written by an older
    /// prompt (or in a different language than the current setting) still format correctly.
    private static func section(of heading: String) -> Section {
        let normalized = heading.lowercased()
        func matches(_ candidates: [String]) -> Bool {
            candidates.contains { normalized.hasPrefix($0.lowercased()) }
        }
        let all = TranscriptLanguage.allCases.map(\.summaryHeadings)
        if matches(all.map(\.topics)) { return .topics }
        if matches(all.map(\.decisions)) { return .decisions }
        // "Action items" is what earlier versions of the prompt produced.
        if matches(all.map(\.actions) + ["action items", "actions"]) { return .actions }
        return .other
    }

    private static func marker(for section: Section) -> String {
        switch section {
        case .topics: return "💬"
        case .decisions: return "✅"
        case .actions: return "📌"
        case .other: return "•"
        }
    }

    /// Strips inline markdown that chat clients would show as literal characters.
    private static func clean(_ line: String) -> String {
        var text = line
        for token in ["**", "__", "`"] {
            text = text.replacingOccurrences(of: token, with: "")
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func message(
        summary: String,
        recording: Recording,
        language: TranscriptLanguage
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: language.rawValue)
        dateFormatter.setLocalizedDateFormatFromTemplate("d MMMM HH:mm")

        var header = "📝 \(language.notesTitle) · \(dateFormatter.string(from: recording.meta.date))"
        if let duration = recording.meta.duration {
            let minutes = max(1, Int(duration) / 60)
            header += " · \(minutes) \(language.minutesUnit)"
        }

        var lines: [String] = [header, ""]
        var isActionSection = false
        var lastWasListItem = false

        for rawLine in summary.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#") {
                let heading = clean(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))
                guard !heading.isEmpty else { continue }
                let section = section(of: heading)
                isActionSection = section == .actions
                if lines.count > 2 { lines.append("") }
                lines.append("\(marker(for: section)) \(heading)")
                lastWasListItem = false
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                let item = clean(String(line.dropFirst(2)))
                // Action items get checkboxes — they are the part people act on.
                lines.append(isActionSection ? "   ☐ \(item)" : "   • \(item)")
                lastWasListItem = true
            } else if let match = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let item = clean(String(line[match.upperBound...]))
                lines.append(isActionSection ? "   ☐ \(item)" : "   • \(item)")
                lastWasListItem = true
            } else {
                // A trailing remark after a list needs a blank line, or it reads as a bullet.
                if lastWasListItem { lines.append("") }
                lines.append(clean(line))
                lastWasListItem = false
            }
        }

        return lines.joined(separator: "\n")
    }
}
