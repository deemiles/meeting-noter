import Foundation

/// Drains a pipe on a background queue so a chatty child process cannot block on a
/// full pipe buffer, and the collected output survives the process exiting.
private final class PipeCollector: @unchecked Sendable {
    private let pipe: Pipe
    private let lock = NSLock()
    private var data = Data()

    init(_ pipe: Pipe) {
        self.pipe = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let self else { return }
            self.lock.lock(); self.data.append(chunk); self.lock.unlock()
        }
    }

    func finish() {
        pipe.fileHandleForReading.readabilityHandler = nil
        let rest = pipe.fileHandleForReading.availableData
        guard !rest.isEmpty else { return }
        lock.lock(); data.append(rest); lock.unlock()
    }

    var string: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Call summary through the Claude Code CLI (`claude -p`), when it is installed.
@MainActor
final class SummarizerAvailability: ObservableObject {
    /// Observable, unlike a bare static: the menu is often rendered before detection
    /// finishes, and SwiftUI has no way to notice a plain global changing.
    @Published private(set) var claudePath: String?
    @Published private(set) var isDetecting = false

    var isAvailable: Bool { claudePath != nil }

    func detect() async {
        isDetecting = true
        claudePath = await Summarizer.locateClaude()
        Summarizer.claudePath = claudePath
        isDetecting = false
    }
}

/// Call summary through the Claude Code CLI (`claude -p`), when it is installed.
enum Summarizer {
    /// Mirrors SummarizerAvailability for the non-UI code paths.
    static var claudePath: String?

    static var isAvailable: Bool { claudePath != nil }

    /// Looks in the usual install locations, then asks a login shell.
    static func locateClaude() async -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.volta/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/node_modules/.bin/claude",
        ]
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return found
        }
        return await shellLookup()
    }

    /// A GUI app inherits none of the user's shell PATH. `-i` matters: PATH is usually set
    /// in ~/.zshrc, which a non-interactive login shell never reads.
    private static func shellLookup() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-ilc", "command -v claude"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                // An interactive shell must never be able to block on input.
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                // A heavy ~/.zshrc can be slow; do not let startup wait on it forever.
                let deadline = DispatchTime.now() + 10
                DispatchQueue.global().asyncAfter(deadline: deadline) {
                    if process.isRunning { process.terminate() }
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let path = String(data: data, encoding: .utf8)?
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .last(where: { !$0.isEmpty }) ?? ""

                continuation.resume(
                    returning: FileManager.default.isExecutableFile(atPath: path) ? path : nil
                )
            }
        }
    }

    static func summarize(transcriptURL: URL, language: TranscriptLanguage, into folder: URL) async throws -> URL {
        guard let claudePath else {
            throw TranscriberError.processFailed("claude", -1, "Claude CLI not found")
        }
        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)

        // Each language gets its own prompt so the summary comes back in the language
        // the meeting was actually held in, with headings that match.
        let headings = language.summaryHeadings
        let instruction: String
        switch language {
        case .ukrainian:
            instruction = """
            Нижче транскрипт робочого дзвінка. Склади стислий підсумок у markdown українською зі структурою:
            ## \(headings.topics)
            ## \(headings.decisions)
            ## \(headings.actions)
            (з відповідальними, якщо вони зрозумілі з розмови; якщо рішень або завдань немає — так і напиши).
            Не переказуй дослівно, лише суть.
            """
        case .english:
            instruction = """
            Below is a transcript of a work call. Write a concise markdown summary in English structured as:
            ## \(headings.topics)
            ## \(headings.decisions)
            ## \(headings.actions)
            (with owners when clear from the conversation; if there are none, say so).
            Do not retell verbatim, distill the essence.
            """
        case .spanish:
            instruction = """
            A continuación hay la transcripción de una llamada de trabajo. Escribe un resumen conciso en markdown en español con esta estructura:
            ## \(headings.topics)
            ## \(headings.decisions)
            ## \(headings.actions)
            (con responsables cuando se deduzcan de la conversación; si no hay decisiones o tareas, indícalo).
            No repitas literalmente, extrae lo esencial.
            """
        case .german:
            instruction = """
            Unten steht das Transkript eines Arbeitsgesprächs. Schreibe eine knappe Zusammenfassung in Markdown auf Deutsch mit dieser Struktur:
            ## \(headings.topics)
            ## \(headings.decisions)
            ## \(headings.actions)
            (mit Verantwortlichen, sofern aus dem Gespräch erkennbar; falls es keine gibt, schreibe das).
            Nicht wörtlich nacherzählen, nur das Wesentliche.
            """
        case .russian:
            instruction = """
            Ниже транскрипт рабочего звонка. Составь краткое саммари в markdown на русском со структурой:
            ## \(headings.topics)
            ## \(headings.decisions)
            ## \(headings.actions)
            (с ответственными, если они понятны из разговора; если решений или задач нет — так и напиши).
            Не пересказывай дословно, только суть.
            """
        }
        let prompt = instruction + "\n\n" + transcript

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["-p", prompt, "--output-format", "text"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Both pipes are drained while the process runs. Reading only after it exits
        // deadlocks once a child fills the 64 KB pipe buffer, and setting the termination
        // handler after run() races with a process that exits immediately.
        let out = PipeCollector(outputPipe)
        let err = PipeCollector(errorPipe)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                out.finish()
                err.finish()
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                out.finish()
                err.finish()
                continuation.resume()
            }
        }

        let summary = out.string
        guard process.terminationStatus == 0, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriberError.processFailed("claude", process.terminationStatus, err.string)
        }

        let summaryURL = folder.appendingPathComponent("summary.md")
        try summary.write(to: summaryURL, atomically: true, encoding: .utf8)
        return summaryURL
    }
}
