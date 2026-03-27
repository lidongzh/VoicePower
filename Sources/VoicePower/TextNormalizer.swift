import Foundation

struct TextNormalizer: Sendable {
    private let config: TextNormalizationConfig

    init(config: TextNormalizationConfig) {
        self.config = config
    }

    func normalize(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        guard config.simplifiedChinese else {
            return trimmed
        }

        guard let command = config.command, let arguments = config.arguments, !arguments.isEmpty else {
            return trimmed
        }

        let commandPath = command.expandedTildePath
        guard FileManager.default.isExecutableFile(atPath: commandPath) else {
            throw VoicePowerError.transcriptionCommandNotExecutable(commandPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: commandPath)
        process.arguments = arguments.map { $0.expandedTildePath }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        if let inputData = "\(trimmed)\n".data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(inputData)
        }
        try? stdinPipe.fileHandleForWriting.close()

        process.waitUntilExit()

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            let details = stderr.isEmpty ? stdout : stderr
            throw VoicePowerError.textNormalizationFailed(details.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let normalized = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? trimmed : normalized
    }
}
