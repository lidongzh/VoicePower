import Foundation

struct LocalCleanupPolisher: Sendable {
    private let config: CleanupConfig?

    init(config: CleanupConfig?) {
        self.config = config
    }

    func polish(_ rawText: String) async throws -> String {
        guard let config else {
            return rawText
        }

        let resolvedConfig = config.withDefaults()
        let cleanedText: String
        if resolvedConfig.enabled {
            cleanedText = await cleanupPass(rawText: rawText, config: resolvedConfig)
        } else {
            cleanedText = rawText
        }

        let punctuatedText: String
        if resolvedConfig.autoPunctuationEnabled {
            punctuatedText = await punctuationPass(text: cleanedText, config: resolvedConfig)
        } else {
            punctuatedText = cleanedText
        }

        return DictationPostProcessor.format(punctuatedText, autoPunctuation: resolvedConfig.autoPunctuationEnabled)
    }

    private func cleanupPass(rawText: String, config: CleanupConfig) async -> String {
        do {
            let polished = try await generateText(
                rawText,
                systemPrompt: config.systemPrompt ?? CleanupPromptDefaults.systemPrompt,
                userPromptTemplate: config.userPromptTemplate ?? CleanupPromptDefaults.userPromptTemplate,
                model: config.resolvedModel,
                temperature: config.temperature ?? 0.0,
                maxTokens: 192,
                enablePunctuation: false,
                endpoint: config.endpoint
            )
            return validatedCleanupOutput(rawText: rawText, cleanedText: polished)
        } catch {
            return rawText
        }
    }

    private func punctuationPass(text: String, config: CleanupConfig) async -> String {
        do {
            let punctuated = try await generateText(
                text,
                systemPrompt: PunctuationPromptDefaults.systemPrompt,
                userPromptTemplate: PunctuationPromptDefaults.userPromptTemplate,
                model: config.resolvedModel,
                temperature: 0.0,
                maxTokens: 256,
                enablePunctuation: true,
                endpoint: config.endpoint
            )
            return validatedPunctuationOutput(sourceText: text, punctuatedText: punctuated)
        } catch {
            return text
        }
    }

    private func generateText(
        _ rawText: String,
        systemPrompt: String,
        userPromptTemplate: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        enablePunctuation: Bool,
        endpoint: String?
    ) async throws -> String {
        if let endpoint, !endpoint.isEmpty {
            return try await polishWithLegacyOllama(
                rawText,
                model: model,
                systemPrompt: systemPrompt,
                userPromptTemplate: userPromptTemplate,
                temperature: temperature,
                endpoint: endpoint
            )
        }

        return try polishWithBundledRuntime(
            rawText,
            model: model,
            systemPrompt: systemPrompt,
            userPromptTemplate: userPromptTemplate,
            temperature: temperature,
            maxTokens: maxTokens,
            enablePunctuation: enablePunctuation
        )
    }

    private func polishWithBundledRuntime(
        _ rawText: String,
        model: String,
        systemPrompt: String,
        userPromptTemplate: String,
        temperature: Double,
        maxTokens: Int,
        enablePunctuation: Bool
    ) throws -> String {
        let runtimePythonURL = VoicePowerPaths.runtimePythonURL
        guard FileManager.default.isExecutableFile(atPath: runtimePythonURL.path) else {
            throw VoicePowerError.runtimeBootstrapFailed("VoicePower runtime is not ready yet")
        }

        let scriptURL = VoicePowerPaths.scriptURL(named: "mlx_cleanup_polish.py")
        let punctuationFlag = enablePunctuation ? "--enable-punctuation" : "--disable-punctuation"

        let result = try ProcessRunner.run(
            executableURL: runtimePythonURL,
            arguments: [
                scriptURL.path,
                "--model",
                model,
                "--temperature",
                String(temperature),
                "--max-tokens",
                String(maxTokens),
                "--system-prompt",
                systemPrompt,
                "--user-prompt-template",
                userPromptTemplate,
                punctuationFlag,
                "--hf-home",
                VoicePowerPaths.huggingFaceCacheURL.path,
            ],
            environment: [
                "HF_HOME": VoicePowerPaths.huggingFaceCacheURL.path,
                "TOKENIZERS_PARALLELISM": "false",
            ],
            standardInput: rawText
        )

        guard result.terminationStatus == 0 else {
            throw VoicePowerError.cleanupRequestFailed(result.standardError.nonEmptyOr(result.standardOutput))
        }

        let cleaned = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? rawText : cleaned
    }

    private func polishWithLegacyOllama(
        _ rawText: String,
        model: String,
        systemPrompt: String,
        userPromptTemplate: String,
        temperature: Double,
        endpoint: String
    ) async throws -> String {
        guard let endpointURL = URL(string: endpoint) else {
            throw VoicePowerError.invalidCleanupEndpoint(endpoint)
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaGenerateRequest(
                model: model,
                prompt: Self.makePrompt(rawText, template: userPromptTemplate),
                system: systemPrompt,
                stream: false,
                options: OllamaOptions(temperature: temperature)
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoicePowerError.cleanupRequestFailed("Missing HTTP response")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw VoicePowerError.cleanupRequestFailed("HTTP \(httpResponse.statusCode)")
        }

        let responseBody = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let polished = responseBody.response.trimmingCharacters(in: .whitespacesAndNewlines)
        return polished.isEmpty ? rawText : polished
    }

    private func validatedCleanupOutput(rawText: String, cleanedText: String) -> String {
        let rawTrimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTrimmed = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTrimmed.isEmpty else {
            return rawTrimmed
        }

        let rawHasLatin = rawTrimmed.range(of: "[A-Za-z]", options: .regularExpression) != nil
        let cleanedHasLatin = cleanedTrimmed.range(of: "[A-Za-z]", options: .regularExpression) != nil
        let rawHasChinese = rawTrimmed.range(of: "\\p{Han}", options: .regularExpression) != nil
        let cleanedHasChinese = cleanedTrimmed.range(of: "\\p{Han}", options: .regularExpression) != nil

        if rawHasLatin && !cleanedHasLatin && cleanedHasChinese {
            return rawTrimmed
        }

        if !rawHasChinese && cleanedHasChinese {
            return rawTrimmed
        }

        return cleanedTrimmed
    }

    private func validatedPunctuationOutput(sourceText: String, punctuatedText: String) -> String {
        let sourceTrimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let punctuatedTrimmed = punctuatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !punctuatedTrimmed.isEmpty else {
            return sourceTrimmed
        }

        if normalizedComparableContent(sourceTrimmed) != normalizedComparableContent(punctuatedTrimmed) {
            return sourceTrimmed
        }

        return punctuatedTrimmed
    }

    private func normalizedComparableContent(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "[\\p{P}\\p{S}\\s]+", with: "", options: .regularExpression)
    }

    private static func makePrompt(_ rawText: String, template: String?) -> String {
        let resolvedTemplate = template ?? CleanupPromptDefaults.userPromptTemplate
        return resolvedTemplate.replacingOccurrences(of: "{{text}}", with: rawText)
    }
}

private enum PunctuationPromptDefaults {
    static let systemPrompt = """
    You are a bilingual dictation punctuation engine.
    Preserve every original word in the same order.
    Never translate English into Chinese.
    Never translate Chinese into English.
    Never add or remove content except punctuation and minimal spacing around punctuation.
    Keep mixed English and Chinese intact.
    If output contains Chinese characters, use simplified Chinese punctuation conventions.
    Return only the final punctuated text.
    """

    static let userPromptTemplate = """
    Add sentence boundaries and punctuation to this transcript.
    Do not rewrite, summarize, or correct wording.
    Only add punctuation and minimal spacing when needed.

    Transcript:
    {{text}}
    """
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let system: String
    let stream: Bool
    let options: OllamaOptions
}

private struct OllamaOptions: Encodable {
    let temperature: Double
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}
