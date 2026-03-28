import Foundation

enum InferenceWorkerState: Equatable {
    case stopped
    case starting
    case warming
    case ready
    case restarting
    case error(String)

    var statusText: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting"
        case .warming:
            return "Warming"
        case .ready:
            return "Ready"
        case .restarting:
            return "Restarting"
        case let .error(message):
            return "Error: \(message)"
        }
    }
}

actor InferenceWorkerManager {
    private struct Request: Codable {
        let id: String
        let method: String
        let whisperModel: String?
        let language: String?
        let cleanupModel: String?
        let cleanupEnabled: Bool?
        let audioPath: String?
        let text: String?
        let systemPrompt: String?
        let userPromptTemplate: String?
        let temperature: Double?
        let autoPunctuation: Bool?
        let maxTokens: Int?
    }

    private struct Response: Codable {
        let id: String
        let ok: Bool
        let result: ResultPayload?
        let error: String?
    }

    private struct ResultPayload: Codable {
        let text: String?
        let status: String?
    }

    private enum TransportError: LocalizedError {
        case startup(String)
        case request(String)

        var errorDescription: String? {
            switch self {
            case let .startup(message), let .request(message):
                return message
            }
        }
    }

    private enum RequestFailure: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case let .failed(message):
                return message
            }
        }
    }

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var pendingResponses: [String: CheckedContinuation<Response, Error>] = [:]
    private var stderrTail: [String] = []
    private var statusHandler: (@Sendable (InferenceWorkerState) -> Void)?
    private var currentState: InferenceWorkerState = .stopped
    private var intentionalShutdown = false

    func setStatusHandler(_ handler: @escaping @Sendable (InferenceWorkerState) -> Void) {
        statusHandler = handler
        handler(currentState)
    }

    func prepare(for config: AppConfig) async throws {
        let requirements = config.localRuntimeRequirements
        guard requirements.needsWorker else {
            intentionalShutdown = true
            await teardownProcess(markAsStopped: true)
            return
        }

        _ = try await sendRequestWithSingleRestart(
            makeRequest: {
                Request(
                    id: UUID().uuidString,
                    method: "prepare",
                    whisperModel: requirements.needsWhisperModel ? config.resolvedTranscription.resolvedModel : nil,
                    language: nil,
                    cleanupModel: requirements.needsCleanupModel ? config.resolvedCleanup.resolvedModel : nil,
                    cleanupEnabled: requirements.needsCleanupModel,
                    audioPath: nil,
                    text: nil,
                    systemPrompt: nil,
                    userPromptTemplate: nil,
                    temperature: nil,
                    autoPunctuation: nil,
                    maxTokens: nil
                )
            },
            startingState: .warming,
            mapError: { VoicePowerError.runtimeBootstrapFailed($0) }
        )
        publishStatus(.ready)
    }

    func transcribe(audioFileURL: URL, config: TranscriptionConfig) async throws -> String {
        let response = try await sendRequestWithSingleRestart(
            makeRequest: {
                Request(
                    id: UUID().uuidString,
                    method: "transcribe",
                    whisperModel: config.resolvedModel,
                    language: config.resolvedLanguage,
                    cleanupModel: nil,
                    cleanupEnabled: nil,
                    audioPath: audioFileURL.path,
                    text: nil,
                    systemPrompt: nil,
                    userPromptTemplate: nil,
                    temperature: nil,
                    autoPunctuation: nil,
                    maxTokens: nil
                )
            },
            startingState: .starting,
            mapError: { VoicePowerError.transcriptionFailed(details: $0) }
        )

        guard let text = response.result?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw VoicePowerError.emptyTranscript
        }

        publishStatus(.ready)
        return text
    }

    func polish(_ rawText: String, config: CleanupConfig) async throws -> String {
        let response = try await sendRequestWithSingleRestart(
            makeRequest: {
                Request(
                    id: UUID().uuidString,
                    method: "polish",
                    whisperModel: nil,
                    language: nil,
                    cleanupModel: config.resolvedModel,
                    cleanupEnabled: true,
                    audioPath: nil,
                    text: rawText,
                    systemPrompt: config.systemPrompt ?? CleanupPromptDefaults.systemPrompt,
                    userPromptTemplate: config.userPromptTemplate ?? CleanupPromptDefaults.userPromptTemplate,
                    temperature: config.temperature ?? 0.0,
                    autoPunctuation: config.autoPunctuationEnabled,
                    maxTokens: config.autoPunctuationEnabled ? 256 : 192
                )
            },
            startingState: .warming,
            mapError: { VoicePowerError.cleanupRequestFailed($0) }
        )

        let text = response.result?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw VoicePowerError.cleanupRequestFailed("Worker returned empty text")
        }

        publishStatus(.ready)
        return text
    }

    func shutdown() async {
        intentionalShutdown = true
        do {
            _ = try await sendRequest(
                Request(
                    id: UUID().uuidString,
                    method: "shutdown",
                    whisperModel: nil,
                    language: nil,
                    cleanupModel: nil,
                    cleanupEnabled: nil,
                    audioPath: nil,
                    text: nil,
                    systemPrompt: nil,
                    userPromptTemplate: nil,
                    temperature: nil,
                    autoPunctuation: nil,
                    maxTokens: nil
                )
            )
        } catch {
            // Ignore shutdown errors.
        }

        await teardownProcess(markAsStopped: true)
    }

    private func sendRequestWithSingleRestart(
        makeRequest: @escaping @Sendable () -> Request,
        startingState: InferenceWorkerState,
        mapError: @escaping (String) -> Error
    ) async throws -> Response {
        publishStatus(startingState)

        do {
            return try await sendRequest(makeRequest())
        } catch let error as TransportError {
            publishStatus(.restarting)
            await teardownProcess(markAsStopped: false)

            do {
                let response = try await sendRequest(makeRequest())
                return response
            } catch let secondError as TransportError {
                let message = [error.localizedDescription, secondError.localizedDescription]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                publishStatus(.error(message))
                throw mapError(message)
            } catch {
                publishStatus(.error(error.localizedDescription))
                throw error
            }
        } catch {
            publishStatus(.error(error.localizedDescription))
            throw error
        }
    }

    private func sendRequest(_ request: Request) async throws -> Response {
        try await ensureProcessStarted()
        guard let stdinHandle else {
            throw TransportError.startup("Worker stdin is unavailable")
        }

        let requestData = try JSONEncoder().encode(request)
        var payload = requestData
        payload.append(0x0A)

        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[request.id] = continuation

            do {
                try stdinHandle.write(contentsOf: payload)
            } catch {
                pendingResponses.removeValue(forKey: request.id)
                continuation.resume(throwing: TransportError.request("Failed to write to worker: \(error.localizedDescription)"))
            }
        }
    }

    private func ensureProcessStarted() async throws {
        if let process, process.isRunning {
            return
        }

        guard FileManager.default.isExecutableFile(atPath: VoicePowerPaths.runtimePythonURL.path) else {
            throw TransportError.startup("VoicePower runtime is not ready yet")
        }

        intentionalShutdown = false
        stderrTail.removeAll(keepingCapacity: true)
        publishStatus(.starting)

        let process = Process()
        process.executableURL = VoicePowerPaths.runtimePythonURL
        process.arguments = [
            VoicePowerPaths.scriptURL(named: "voicepower_worker.py").path,
            "--hf-home",
            VoicePowerPaths.huggingFaceCacheURL.path,
        ]
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "HF_HOME": VoicePowerPaths.huggingFaceCacheURL.path,
                "TOKENIZERS_PARALLELISM": "false",
            ]
        ) { _, new in new }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] terminatedProcess in
            Task {
                await self?.handleProcessTermination(terminatedProcess)
            }
        }

        do {
            try process.run()
        } catch {
            throw TransportError.startup("Failed to launch worker: \(error.localizedDescription)")
        }

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting

        let stdoutHandle = stdoutPipe.fileHandleForReading
        stdoutTask = Task.detached { [weak self] in
            do {
                for try await line in stdoutHandle.bytes.lines {
                    await self?.handleStdoutLine(String(line))
                }
                await self?.handleStdoutClosed()
            } catch {
                await self?.handleTransportFailure("Worker stdout failed: \(error.localizedDescription)")
            }
        }

        let stderrHandle = stderrPipe.fileHandleForReading
        stderrTask = Task.detached { [weak self] in
            do {
                for try await line in stderrHandle.bytes.lines {
                    await self?.appendStderr(String(line))
                }
            } catch {
                await self?.appendStderr("Worker stderr failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleStdoutLine(_ line: String) {
        guard let data = line.data(using: .utf8) else {
            handleTransportFailure("Worker returned non-UTF8 output")
            return
        }

        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard let continuation = pendingResponses.removeValue(forKey: response.id) else {
                return
            }

            if response.ok {
                continuation.resume(returning: response)
            } else {
                continuation.resume(throwing: RequestFailure.failed(response.error ?? latestWorkerDetails()))
            }
        } catch {
            handleTransportFailure("Worker returned invalid JSON: \(line)")
        }
    }

    private func handleStdoutClosed() {
        if intentionalShutdown {
            return
        }

        handleTransportFailure("Worker stdout closed unexpectedly")
    }

    private func handleProcessTermination(_ terminatedProcess: Process) async {
        guard process === terminatedProcess else {
            return
        }

        let message: String
        if intentionalShutdown {
            message = "Stopped"
        } else {
            message = latestWorkerDetails(defaultMessage: "Worker exited unexpectedly")
        }

        await teardownProcess(markAsStopped: intentionalShutdown)

        if !intentionalShutdown {
            publishStatus(.error(message))
        }
    }

    private func handleTransportFailure(_ message: String) {
        let error = TransportError.request([message, latestWorkerDetails()].filter { !$0.isEmpty }.joined(separator: "\n"))
        for continuation in pendingResponses.values {
            continuation.resume(throwing: error)
        }
        pendingResponses.removeAll()
    }

    private func appendStderr(_ line: String) {
        stderrTail.append(line)
        if stderrTail.count > 20 {
            stderrTail.removeFirst(stderrTail.count - 20)
        }
    }

    private func latestWorkerDetails(defaultMessage: String = "") -> String {
        if stderrTail.isEmpty {
            return defaultMessage
        }

        return stderrTail.joined(separator: "\n")
    }

    private func teardownProcess(markAsStopped: Bool) async {
        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil

        let process = self.process
        process?.terminationHandler = nil
        self.process = nil

        if let stdinHandle {
            try? stdinHandle.close()
        }
        self.stdinHandle = nil

        if let process, process.isRunning {
            process.terminate()
        }

        let error = TransportError.request(latestWorkerDetails(defaultMessage: "Worker connection closed"))
        for continuation in pendingResponses.values {
            continuation.resume(throwing: error)
        }
        pendingResponses.removeAll()

        if markAsStopped {
            publishStatus(.stopped)
        }
    }

    private func publishStatus(_ state: InferenceWorkerState) {
        currentState = state
        statusHandler?(state)
    }
}
