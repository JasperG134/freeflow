import Foundation

/// Runs the bundled Parakeet Core ML helper as an isolated, one-shot process.
/// The model is loaded only while a transcription is running, keeping idle RAM
/// use close to the stock FreeFlow app. All audio and transcript data stay on
/// this Mac; the helper receives only a local file path and writes its result to
/// a temporary file that is deleted immediately after parsing.
final class LocalParakeetTranscriptionService {
    private let executableURL: URL
    private let modelDirectory: URL

    init(modelDirectory: URL, executableURL: URL? = nil) throws {
        let resolvedURL: URL
        if let executableURL {
            resolvedURL = executableURL
        } else if let mainExecutable = Bundle.main.executableURL {
            resolvedURL = mainExecutable
                .deletingLastPathComponent()
                .appendingPathComponent("freeflow-local-asr", isDirectory: false)
        } else {
            throw LocalParakeetError.helperUnavailable
        }

        guard FileManager.default.isExecutableFile(atPath: resolvedURL.path) else {
            throw LocalParakeetError.helperUnavailable
        }
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw LocalParakeetError.modelUnavailable
        }
        self.executableURL = resolvedURL
        self.modelDirectory = modelDirectory
    }

    func transcribe(fileURL: URL) async throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("freeflow-local-asr-\(UUID().uuidString)")
            .appendingPathExtension("txt")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        guard FileManager.default.createFile(
            atPath: outputURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw LocalParakeetError.invalidOutput
        }
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "transcribe",
            fileURL.path,
            "--models", modelDirectory.path,
            "--compute-units", "ane",
        ]

        // Diagnostics go to stderr; stdout contains only the transcript. Keep
        // both out of persistent application logs and delete the private output
        // file immediately after parsing.
        process.standardOutput = outputHandle
        process.standardError = FileHandle.nullDevice

        try await run(process)
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw LocalParakeetError.helperFailed(process.terminationStatus)
        }

        try outputHandle.synchronize()
        let data = try Data(contentsOf: outputURL)
        return try Self.parseTranscript(from: data)
    }

    static func parseTranscript(from data: Data) throws -> String {
        guard let output = String(data: data, encoding: .utf8) else {
            throw LocalParakeetError.invalidOutput
        }
        let repairedTranscript = removingSingleTrailingForeignScriptArtifact(
            in: output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let transcript = collapseRepeatedTerminalPunctuation(in: repairedTranscript)
        guard !transcript.isEmpty else {
            throw LocalParakeetError.invalidOutput
        }
        return transcript
    }

    /// Some short Latin-script dictations end with one unrelated script token.
    /// Remove only that narrow decoder artifact; never filter a non-Latin
    /// transcript or an actual multi-character word.
    private static func removingSingleTrailingForeignScriptArtifact(in transcript: String) -> String {
        guard let last = transcript.last,
              last.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) && !isLatin($0) }),
              let lastIndex = transcript.indices.last,
              lastIndex > transcript.startIndex else { return transcript }
        let prefixEnd = transcript.index(before: lastIndex)
        guard transcript[prefixEnd].isWhitespace else { return transcript }
        let prefix = transcript[..<prefixEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = prefix.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 4,
              letters.filter({ isLatin($0) }).count * 10 >= letters.count * 9 else { return transcript }
        return prefix
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F:
            return true
        default:
            return false
        }
    }

    /// The current Core ML decoder can repeat its terminal punctuation token
    /// (for example `sentence........`). This local, deterministic repair is
    /// deliberately narrow and never rewrites dictated words.
    private static func collapseRepeatedTerminalPunctuation(in transcript: String) -> String {
        var characters = Array(transcript)
        let collapsible: Set<Character> = [".", "!", "?"]
        while characters.count >= 2,
              let last = characters.last,
              collapsible.contains(last),
              characters[characters.count - 2] == last {
            characters.removeLast()
        }
        return String(characters)
    }

    private func run(_ process: Process) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
        try Task.checkCancellation()
    }
}

enum LocalParakeetError: LocalizedError {
    case helperUnavailable
    case modelUnavailable
    case helperFailed(Int32)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            return "The bundled local transcription engine is missing or cannot be executed."
        case .modelUnavailable:
            return "The on-device transcription model is not installed. Open Settings to download it."
        case .helperFailed(let status):
            return "Local transcription failed (engine exit \(status))."
        case .invalidOutput:
            return "The local transcription engine returned no readable transcript."
        }
    }
}
