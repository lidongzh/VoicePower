import Foundation

struct OllamaTextPolisher: Sendable {
    private let config: CleanupConfig?

    init(config: CleanupConfig?) {
        self.config = config
    }

    func polish(_ rawText: String) async throws -> String {
        guard let config, config.enabled else {
            return rawText
        }

        guard let endpointURL = URL(string: config.endpoint) else {
            throw VoicePowerError.invalidCleanupEndpoint(config.endpoint)
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaGenerateRequest(
                model: config.model,
                prompt: Self.makePrompt(rawText, template: config.userPromptTemplate),
                system: config.systemPrompt ?? Self.defaultSystemPrompt,
                stream: false,
                options: OllamaOptions(temperature: config.temperature ?? 0.1)
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

    private static let defaultSystemPrompt = CleanupPromptDefaults.systemPrompt

    private static func makePrompt(_ rawText: String, template: String?) -> String {
        if let template {
            return template.replacingOccurrences(of: "{{text}}", with: rawText)
        }

        return """
        Clean up this dictated text without changing meaning. Keep mixed English and Chinese intact.

        Raw transcript:
        \(rawText)
        """
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
