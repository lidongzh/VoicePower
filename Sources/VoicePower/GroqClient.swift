import Foundation

struct GroqClient: Sendable {
    private let apiKeyStore: GroqAPIKeyStore
    private let baseURL = URL(string: "https://api.groq.com/openai/v1")!

    init(apiKeyStore: GroqAPIKeyStore) {
        self.apiKeyStore = apiKeyStore
    }

    func transcribe(audioFileURL: URL, model: String, language: String?) async throws -> String {
        var request = try authorizedRequest(path: "audio/transcriptions")
        let boundary = "Boundary-\(UUID().uuidString)"
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        request.httpBody = try makeTranscriptionBody(
            audioFileURL: audioFileURL,
            model: model,
            language: language,
            boundary: boundary
        )

        let data = try await perform(request)
        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cleanup(
        rawText: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxCompletionTokens: Int
    ) async throws -> String {
        let reasoningConfiguration = reasoningConfiguration(for: model)
        var request = try authorizedRequest(path: "chat/completions")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: model,
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: userPrompt),
                ],
                temperature: temperature,
                maxCompletionTokens: maxCompletionTokens,
                reasoningEffort: reasoningConfiguration.effort,
                reasoningFormat: reasoningConfiguration.format
            )
        )

        let data = try await perform(request)
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let content = normalizeCleanupOutput(decoded.choices.first?.message.content ?? "")
        guard !content.isEmpty else {
            throw VoicePowerError.groqRequestFailed("Cleanup model returned empty text")
        }

        return content
    }

    private func authorizedRequest(path: String) throws -> URLRequest {
        guard let apiKey = try apiKeyStore.load(), !apiKey.isEmpty else {
            throw VoicePowerError.missingGroqAPIKey
        }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoicePowerError.groqRequestFailed("Missing HTTP response")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(GroqErrorEnvelope.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Unknown error"
            throw VoicePowerError.groqRequestFailed("HTTP \(httpResponse.statusCode): \(message)")
        }

        return data
    }

    private func makeTranscriptionBody(
        audioFileURL: URL,
        model: String,
        language: String?,
        boundary: String
    ) throws -> Data {
        let fileData = try Data(contentsOf: audioFileURL)
        var body = Data()

        body.appendMultipartField(named: "model", value: model, boundary: boundary)
        body.appendMultipartField(named: "response_format", value: "json", boundary: boundary)
        body.appendMultipartField(named: "temperature", value: "0", boundary: boundary)
        if let language, !language.isEmpty, language.lowercased() != "auto" {
            body.appendMultipartField(named: "language", value: language, boundary: boundary)
        }

        body.appendMultipartFile(
            named: "file",
            filename: audioFileURL.lastPathComponent,
            mimeType: mimeType(for: audioFileURL.pathExtension),
            data: fileData,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")
        return body
    }

    private func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/m4a"
        case "mp3":
            return "audio/mpeg"
        case "ogg":
            return "audio/ogg"
        case "webm":
            return "audio/webm"
        default:
            return "application/octet-stream"
        }
    }

    private func normalizeCleanupOutput(_ raw: String) -> String {
        var normalized = raw
            .replacingOccurrences(
                of: "<think>[\\s\\S]*?</think>",
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.hasPrefix("Output:") {
            normalized.removeFirst("Output:".count)
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func reasoningConfiguration(for model: String) -> (effort: String?, format: String?) {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedModel == "qwen/qwen3-32b" {
            return ("none", "hidden")
        }

        return (nil, nil)
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxCompletionTokens: Int
    let reasoningEffort: String?
    let reasoningFormat: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxCompletionTokens = "max_completion_tokens"
        case reasoningEffort = "reasoning_effort"
        case reasoningFormat = "reasoning_format"
    }
}

private struct ChatMessage: Encodable, Decodable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessageContent
    }

    struct ChatMessageContent: Decodable {
        let content: String?
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

private struct GroqErrorEnvelope: Decodable {
    let error: GroqError

    struct GroqError: Decodable {
        let message: String
    }
}

private extension Data {
    mutating func appendString(_ value: String) {
        append(Data(value.utf8))
    }

    mutating func appendMultipartField(named name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFile(
        named name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }
}
