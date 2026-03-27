import Foundation

struct WhisperTranscriber: Sendable {
    private let config: TranscriptionConfig

    init(config: TranscriptionConfig) {
        self.config = config
    }

    func transcribe(audioFileURL: URL) throws -> String {
        let fileManager = FileManager.default
        let outputDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let outputBase = outputDirectory.appendingPathComponent(audioFileURL.deletingPathExtension().lastPathComponent)
        let commandPath = expand(
            config.command,
            audioPath: audioFileURL.path,
            outputBase: outputBase.path
        )

        guard fileManager.isExecutableFile(atPath: commandPath) else {
            throw VoicePowerError.transcriptionCommandNotExecutable(commandPath)
        }

        let arguments = config.arguments.map {
            expand($0, audioPath: audioFileURL.path, outputBase: outputBase.path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: commandPath)
        process.arguments = arguments

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        let stdout = String(
            data: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: standardError.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            let details = stderr.isEmpty ? stdout : stderr
            throw VoicePowerError.transcriptionFailed(details: details.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let rawTranscript: String
        if let outputTextPath = config.outputTextPath {
            let transcriptPath = expand(outputTextPath, audioPath: audioFileURL.path, outputBase: outputBase.path)
            rawTranscript = try String(contentsOfFile: transcriptPath, encoding: .utf8)
        } else {
            rawTranscript = stdout
        }

        let normalized = Self.normalize(rawTranscript)
        guard !normalized.isEmpty else {
            throw VoicePowerError.emptyTranscript
        }

        return normalized
    }

    private func expand(_ template: String, audioPath: String, outputBase: String) -> String {
        template
            .replacingOccurrences(of: "{{audio_path}}", with: audioPath)
            .replacingOccurrences(of: "{{output_base}}", with: outputBase)
            .expandedTildePath
    }

    private static func normalize(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
