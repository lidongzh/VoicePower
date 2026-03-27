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

        let invocation = try makeInvocation()
        let result = try ProcessRunner.run(
            executableURL: invocation.executableURL,
            arguments: invocation.arguments,
            environment: invocation.environment,
            standardInput: "\(trimmed)\n"
        )

        guard result.terminationStatus == 0 else {
            let details = result.standardError.isEmpty ? result.standardOutput : result.standardError
            throw VoicePowerError.textNormalizationFailed(details.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let normalized = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? trimmed : normalized
    }

    private func makeInvocation() throws -> (executableURL: URL, arguments: [String], environment: [String: String]) {
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

        let runtimePythonURL = VoicePowerPaths.runtimePythonURL
        guard FileManager.default.isExecutableFile(atPath: runtimePythonURL.path) else {
            throw VoicePowerError.runtimeBootstrapFailed("VoicePower runtime is not ready yet")
        }

        return (
            executableURL: runtimePythonURL,
            arguments: [
                VoicePowerPaths.scriptURL(named: "simplify_chinese_text.py").path,
            ],
            environment: [:]
        )
    }
}
