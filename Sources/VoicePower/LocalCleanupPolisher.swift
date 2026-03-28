import Foundation

struct LocalCleanupPolisher: Sendable {
    private let config: CleanupConfig?
    private let workerManager: InferenceWorkerManager

    init(config: CleanupConfig?, workerManager: InferenceWorkerManager) {
        self.config = config
        self.workerManager = workerManager
    }

    func polish(_ rawText: String) async throws -> String {
        guard let config else {
            return rawText
        }

        let resolvedConfig = config.withDefaults()

        guard resolvedConfig.enabled else {
            return DictationPostProcessor.format(rawText, autoPunctuation: resolvedConfig.autoPunctuationEnabled)
        }

        let generatedText: String
        if let endpoint = resolvedConfig.endpoint, !endpoint.isEmpty {
            generatedText = try await polishWithLegacyOllama(
                rawText,
                model: resolvedConfig.resolvedModel,
                systemPrompt: resolvedConfig.systemPrompt ?? CleanupPromptDefaults.systemPrompt,
                userPromptTemplate: resolvedConfig.userPromptTemplate ?? CleanupPromptDefaults.userPromptTemplate,
                temperature: resolvedConfig.temperature ?? 0.0,
                endpoint: endpoint
            )
        } else {
            generatedText = try await workerManager.polish(rawText, config: resolvedConfig)
        }

        let validatedText = validatedCleanupOutput(rawText: rawText, cleanedText: generatedText)
        return DictationPostProcessor.format(validatedText, autoPunctuation: resolvedConfig.autoPunctuationEnabled)
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
