import CoreFoundation
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

        if config.usesLegacyCommand {
            return try normalizeWithCommand(trimmed)
        }

        return try normalizeWithSystemTransform(trimmed)
    }

    private func normalizeWithSystemTransform(_ text: String) throws -> String {
        let mutableText = NSMutableString(string: text)
        let succeeded = CFStringTransform(mutableText, nil, "Traditional-Simplified" as CFString, false)
        guard succeeded else {
            throw VoicePowerError.textNormalizationFailed("Built-in Traditional-to-Simplified conversion failed")
        }

        let normalized = String(mutableText).trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? text : normalized
    }

    private func normalizeWithCommand(_ text: String) throws -> String {
        let invocation = try makeCommandInvocation()
        let result = try ProcessRunner.run(
            executableURL: invocation.executableURL,
            arguments: invocation.arguments,
            environment: invocation.environment,
            standardInput: "\(text)\n"
        )

        guard result.terminationStatus == 0 else {
            let details = result.standardError.isEmpty ? result.standardOutput : result.standardError
            throw VoicePowerError.textNormalizationFailed(details.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let normalized = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? text : normalized
    }

    private func makeCommandInvocation() throws -> (executableURL: URL, arguments: [String], environment: [String: String]) {
        if let command = config.command, let arguments = config.arguments, !arguments.isEmpty {
            let commandPath = command.expandedTildePath
            guard FileManager.default.isExecutableFile(atPath: commandPath) else {
                throw VoicePowerError.transcriptionCommandNotExecutable(commandPath)
            }

            return (
                executableURL: URL(fileURLWithPath: commandPath),
                arguments: arguments.map { $0.expandedTildePath },
                environment: [:]
            )
        }

        throw VoicePowerError.textNormalizationFailed("No valid Chinese-normalization command is configured")
    }
}
