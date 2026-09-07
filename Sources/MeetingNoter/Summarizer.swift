import Foundation

/// Call summary through the Claude Code CLI (`claude -p`), when it is installed.
enum Summarizer {
    private(set) static var claudePath: String?

    static var isAvailable: Bool { claudePath != nil }

    /// Look for claude in the usual places, then ask a login shell (a GUI app does not inherit PATH from ~/.zshrc).
    static func detect() async {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
        ]
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            claudePath = found
            return
        }
        // Fallback: ask the login shell.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus == 0, !output.isEmpty, fm.isExecutableFile(atPath: output) {
            claudePath = output
        }
    }

    static func summarize(transcriptURL: URL, language: TranscriptLanguage, into folder: URL) async throws -> URL {
        guard let claudePath else {
            throw TranscriberError.processFailed("claude", -1, "Claude CLI not found")
        }
        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)

        let prompt: String
        switch language {
        case .russian:
            prompt = """
            Ниже транскрипт рабочего звонка. Составь краткое саммари в markdown на русском со структурой:
            ## Темы
            ## Решения
            ## Action items
            (с ответственными, если они понятны из разговора; если решений или action items нет — так и напиши).
            Не пересказывай дословно, только суть. Транскрипт:

            \(transcript)
            """
        case .english:
            prompt = """
            Below is a transcript of a work call. Write a concise markdown summary in English structured as:
            ## Topics
            ## Decisions
            ## Action items
            (with owners when clear from the conversation; if there are none, say so).
            Do not retell verbatim, distill the essence. Transcript:

            \(transcript)
            """
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["-p", prompt, "--output-format", "text"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let summary: String = await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }

        guard process.terminationStatus == 0, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let errorOutput = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw TranscriberError.processFailed("claude", process.terminationStatus, errorOutput)
        }

        let summaryURL = folder.appendingPathComponent("summary.md")
        try summary.write(to: summaryURL, atomically: true, encoding: .utf8)
        return summaryURL
    }
}
