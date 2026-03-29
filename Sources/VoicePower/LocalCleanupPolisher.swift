import Foundation

struct LocalCleanupPolisher: Sendable {
    private let config: CleanupConfig?
    private let workerManager: InferenceWorkerManager
    private let groqClient: GroqClient

    init(config: CleanupConfig?, workerManager: InferenceWorkerManager, groqClient: GroqClient) {
        self.config = config
        self.workerManager = workerManager
        self.groqClient = groqClient
    }

    func polish(_ rawText: String) async throws -> String {
        guard let config else {
            return rawText
        }

        let resolvedConfig = config.withDefaults()

        guard resolvedConfig.enabled else {
            return DictationPostProcessor.format(
                rawText,
                autoPunctuation: resolvedConfig.autoPunctuationEnabled,
                punctuationStyle: resolvedConfig.resolvedPunctuationStyle
            )
        }

        let generatedText: String
        if resolvedConfig.usesLegacyEndpoint, let endpoint = resolvedConfig.endpoint, !endpoint.isEmpty {
            generatedText = try await polishWithLegacyOllama(
                rawText,
                model: resolvedConfig.resolvedModel,
                systemPrompt: resolvedConfig.systemPrompt ?? CleanupPromptDefaults.systemPrompt,
                userPromptTemplate: resolvedConfig.userPromptTemplate ?? CleanupPromptDefaults.userPromptTemplate,
                temperature: resolvedConfig.temperature ?? 0.0,
                endpoint: endpoint
            )
        } else if resolvedConfig.resolvedProvider == .groq {
            let prompt = Self.buildGroqCleanupPrompt(
                rawText,
                model: resolvedConfig.resolvedModel,
                systemPrompt: resolvedConfig.systemPrompt ?? CleanupPromptDefaults.systemPrompt,
                userPromptTemplate: resolvedConfig.userPromptTemplate ?? CleanupPromptDefaults.userPromptTemplate,
                autoPunctuation: resolvedConfig.autoPunctuationEnabled,
                punctuationStyle: resolvedConfig.resolvedPunctuationStyle
            )
            generatedText = try await groqClient.cleanup(
                rawText: rawText,
                model: resolvedConfig.resolvedModel,
                systemPrompt: prompt.systemPrompt,
                userPrompt: prompt.userPrompt,
                temperature: resolvedConfig.temperature ?? 0.0,
                maxCompletionTokens: resolvedConfig.autoPunctuationEnabled ? 256 : 192
            )
        } else {
            generatedText = try await workerManager.polish(rawText, config: resolvedConfig)
        }

        let validatedText = validatedCleanupOutput(rawText: rawText, cleanedText: generatedText)
        return DictationPostProcessor.format(
            validatedText,
            autoPunctuation: resolvedConfig.autoPunctuationEnabled,
            punctuationStyle: resolvedConfig.resolvedPunctuationStyle
        )
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

    private static func makePrompt(_ rawText: String, template: String?) -> String {
        let resolvedTemplate = template ?? CleanupPromptDefaults.userPromptTemplate
        return resolvedTemplate.replacingOccurrences(of: "{{text}}", with: rawText)
    }

    private static func buildGroqCleanupPrompt(
        _ rawText: String,
        model: String,
        systemPrompt: String,
        userPromptTemplate: String,
        autoPunctuation: Bool,
        punctuationStyle: CleanupPunctuationStyle
    ) -> (systemPrompt: String, userPrompt: String) {
        var finalSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var finalUserPrompt = makePrompt(rawText, template: userPromptTemplate)

        if autoPunctuation {
            finalSystemPrompt = "\(finalSystemPrompt)\n\n\(punctuationSystemAppendix(for: punctuationStyle))"
                .trimmingCharacters(in: .whitespacesAndNewlines)
            finalUserPrompt = "\(punctuationUserAppendix(for: punctuationStyle))\n\n\(finalUserPrompt)"
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            finalSystemPrompt = "\(finalSystemPrompt)\nDo not add punctuation unless the original transcript already makes it obvious."
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if model.lowercased().contains("qwen3") {
            finalSystemPrompt = """
            \(finalSystemPrompt)

            Use non-thinking mode. Do not emit reasoning, chain-of-thought, or <think> blocks.
            Return only the final cleaned text.
            """.trimmingCharacters(in: .whitespacesAndNewlines)
            finalUserPrompt = "/no_think\n\(finalUserPrompt)"
        }

        return (finalSystemPrompt, finalUserPrompt)
    }

    private static func punctuationSystemAppendix(for style: CleanupPunctuationStyle) -> String {
        switch style {
        case .chinese:
            return """
            When adding punctuation:
            - Preserve every original word in the same order.
            - Never translate English into Chinese.
            - Never translate Chinese into English.
            - Never add or remove content except safe punctuation and spacing around punctuation.
            - Keep English words separated by spaces.
            - Do not insert spaces between Chinese and English words.
            - Use Chinese punctuation after Chinese text.
            - Use English punctuation after English text.
            - Add one space after English punctuation when another token follows.
            - Do not add spaces after Chinese punctuation.

            Examples:
            Input: 标点符号还是不行请继续用这个sample测试直到它可以正确加上标点
            Output: 标点符号还是不行。请继续用这个sample测试，直到它可以正确加上标点。

            Input: 今天review API docs然后更新settings页面
            Output: 今天review API docs，然后更新settings页面。

            Input: Should the app open the browser directly instead of keeping the native setup window for onboarding
            Output: Should the app open the browser directly instead of keeping the native setup window for onboarding?
            """
        case .english:
            return """
            When adding punctuation:
            - Preserve every original word in the same order.
            - Never translate English into Chinese.
            - Never translate Chinese into English.
            - Never add or remove content except safe punctuation and spacing around punctuation.
            - Use ASCII punctuation only: comma, period, question mark, and exclamation mark.
            - Keep English punctuation attached to the word before it. Do not add a space before English punctuation.
            - Use one space after English punctuation when another token follows, including Chinese text.
            - Never replace English punctuation with Chinese punctuation marks.

            Examples:
            Input: 标点符号还是不行请继续用这个sample测试直到它可以正确加上标点
            Output: 标点符号还是不行. 请继续用这个sample测试, 直到它可以正确加上标点.

            Input: 今天review API docs然后更新settings页面
            Output: 今天review API docs, 然后更新settings页面.

            Input: 这个东西为什么不会自己加上标点符号呢如果要disable这个cleanup model该怎么做呢
            Output: 这个东西为什么不会自己加上标点符号呢? 如果要 disable 这个 cleanup model, 该怎么做呢?
            """
        }
    }

    private static func punctuationUserAppendix(for style: CleanupPunctuationStyle) -> String {
        switch style {
        case .chinese:
            return """
            Add sentence boundaries and punctuation when it is clearly helpful and safe.
            Do not rewrite, summarize, or improve word choice.
            """
        case .english:
            return """
            Add sentence boundaries and punctuation when it is clearly helpful and safe.
            Use English punctuation only.
            Keep English punctuation attached to the word before it, with one space after it when another token follows.
            Do not rewrite, summarize, or improve word choice.
            """
        }
    }
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
