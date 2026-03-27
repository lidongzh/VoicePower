import Foundation

struct WhisperTranscriber: Sendable {
    private let config: TranscriptionConfig

    init(config: TranscriptionConfig) {
        self.config = config.withDefaults()
    }

    func transcribe(audioFileURL: URL) throws -> String {
        let fileManager = FileManager.default
        let outputDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let outputBase = outputDirectory.appendingPathComponent(audioFileURL.deletingPathExtension().lastPathComponent)
        let invocation = try makeInvocation(audioFileURL: audioFileURL, outputBase: outputBase)
        let result = try ProcessRunner.run(
            executableURL: invocation.executableURL,
            arguments: invocation.arguments,
            environment: invocation.environment
        )

        let stdout = result.standardOutput
        let stderr = result.standardError

        guard result.terminationStatus == 0 else {
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

    private func makeInvocation(audioFileURL: URL, outputBase: URL) throws -> (executableURL: URL, arguments: [String], environment: [String: String]) {
        if config.usesLegacyCommand, let command = config.command, let arguments = config.arguments {
            let commandPath = expand(
                command,
                audioPath: audioFileURL.path,
                outputBase: outputBase.path
            )

            guard FileManager.default.isExecutableFile(atPath: commandPath) else {
                throw VoicePowerError.transcriptionCommandNotExecutable(commandPath)
            }

            return (
                executableURL: URL(fileURLWithPath: commandPath),
                arguments: arguments.map { expand($0, audioPath: audioFileURL.path, outputBase: outputBase.path) },
                environment: [:]
            )
        }

        let runtimePythonURL = VoicePowerPaths.runtimePythonURL
        guard FileManager.default.isExecutableFile(atPath: runtimePythonURL.path) else {
            throw VoicePowerError.runtimeBootstrapFailed("VoicePower runtime is not ready yet")
        }

        let scriptURL = VoicePowerPaths.scriptURL(named: "mlx_whisper_transcribe.py")
        return (
            executableURL: runtimePythonURL,
            arguments: [
                scriptURL.path,
                "--audio-path",
                audioFileURL.path,
                "--model",
                config.resolvedModel,
                "--language",
                config.resolvedLanguage,
                "--hf-home",
                VoicePowerPaths.huggingFaceCacheURL.path,
            ],
            environment: [
                "HF_HOME": VoicePowerPaths.huggingFaceCacheURL.path,
                "TOKENIZERS_PARALLELISM": "false",
            ]
        )
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
