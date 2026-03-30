import Foundation

struct RuntimeSnapshot {
    let baseRuntimeReady: Bool
    let whisperModelReady: Bool
    let cleanupModelReady: Bool
    let runtimeRootURL: URL
}

actor RuntimeBootstrapper {
    private var baseRuntimeTask: Task<Void, Error>?
    private var whisperModelTasks: [String: Task<Void, Error>] = [:]
    private var cleanupModelTasks: [String: Task<Void, Error>] = [:]

    func snapshot(for config: AppConfig) -> RuntimeSnapshot {
        RuntimeSnapshot(
            baseRuntimeReady: FileManager.default.isExecutableFile(atPath: VoicePowerPaths.runtimePythonURL.path)
                && FileManager.default.fileExists(atPath: VoicePowerPaths.runtimeReadyMarkerURL.path),
            whisperModelReady: FileManager.default.fileExists(
                atPath: VoicePowerPaths.markerURL(kind: "whisper", model: config.resolvedTranscription.resolvedModel).path
            ),
            cleanupModelReady: FileManager.default.fileExists(
                atPath: VoicePowerPaths.markerURL(kind: "cleanup", model: config.resolvedCleanup.resolvedModel).path
            ),
            runtimeRootURL: VoicePowerPaths.runtimeRootURL
        )
    }

    func ensureBaseRuntimeReady() async throws {
        if let baseRuntimeTask {
            return try await baseRuntimeTask.value
        }

        let task = Task.detached(priority: .utility) {
            try Self.bootstrapBaseRuntime()
        }
        baseRuntimeTask = task
        defer { baseRuntimeTask = nil }
        try await task.value
    }

    func ensureWhisperModelReady(_ model: String) async throws {
        if let task = whisperModelTasks[model] {
            return try await task.value
        }

        let task = Task.detached(priority: .utility) {
            try Self.bootstrapBaseRuntime()
            try Self.prefetchWhisperModel(model)
        }
        whisperModelTasks[model] = task
        defer { whisperModelTasks[model] = nil }
        try await task.value
    }

    func ensureCleanupModelReady(_ model: String) async throws {
        if let task = cleanupModelTasks[model] {
            return try await task.value
        }

        let task = Task.detached(priority: .utility) {
            try Self.bootstrapBaseRuntime()
            try Self.prefetchCleanupModel(model)
        }
        cleanupModelTasks[model] = task
        defer { cleanupModelTasks[model] = nil }
        try await task.value
    }

    private static func bootstrapBaseRuntime() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: VoicePowerPaths.applicationSupportURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: VoicePowerPaths.runtimeRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: VoicePowerPaths.cacheRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: VoicePowerPaths.pipCacheURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: VoicePowerPaths.huggingFaceCacheURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: VoicePowerPaths.markersURL, withIntermediateDirectories: true)

        if fileManager.isExecutableFile(atPath: VoicePowerPaths.runtimePythonURL.path),
           fileManager.fileExists(atPath: VoicePowerPaths.runtimeReadyMarkerURL.path) {
            if runtimePythonLooksCompatible(at: VoicePowerPaths.runtimePythonURL) {
                return
            }

            try? fileManager.removeItem(at: VoicePowerPaths.runtimeVenvURL)
            try? fileManager.removeItem(at: VoicePowerPaths.runtimeReadyMarkerURL)
        }

        if try installBundledRuntimeIfAvailable() {
            return
        }

        let bootstrapPython = try locateBootstrapPython()

        if !fileManager.isExecutableFile(atPath: VoicePowerPaths.runtimePythonURL.path) {
            let result = try ProcessRunner.run(
                executableURL: bootstrapPython,
                arguments: ["-m", "venv", VoicePowerPaths.runtimeVenvURL.path]
            )
            guard result.terminationStatus == 0 else {
                throw VoicePowerError.runtimeBootstrapFailed(result.standardError.nonEmptyOr(result.standardOutput))
            }
        }

        let runtimePython = VoicePowerPaths.runtimePythonURL
        let installEnvironment = [
            "PIP_CACHE_DIR": VoicePowerPaths.pipCacheURL.path,
            "HF_HOME": VoicePowerPaths.huggingFaceCacheURL.path,
            "TOKENIZERS_PARALLELISM": "false",
        ]

        let upgradePip = try ProcessRunner.run(
            executableURL: runtimePython,
            arguments: ["-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"],
            environment: installEnvironment
        )
        guard upgradePip.terminationStatus == 0 else {
            throw VoicePowerError.runtimeBootstrapFailed(upgradePip.standardError.nonEmptyOr(upgradePip.standardOutput))
        }

        let installPackages = try ProcessRunner.run(
            executableURL: runtimePython,
            arguments: [
                "-m",
                "pip",
                "install",
                "--upgrade",
                "mlx-whisper",
                "mlx-lm",
            ],
            environment: installEnvironment
        )
        guard installPackages.terminationStatus == 0 else {
            throw VoicePowerError.runtimeBootstrapFailed(installPackages.standardError.nonEmptyOr(installPackages.standardOutput))
        }

        try "ready\n".write(to: VoicePowerPaths.runtimeReadyMarkerURL, atomically: true, encoding: .utf8)
    }

    private static func installBundledRuntimeIfAvailable() throws -> Bool {
        let fileManager = FileManager.default
        guard let bundledRuntimeVenvURL = VoicePowerPaths.bundledRuntimeVenvURL,
              fileManager.fileExists(atPath: bundledRuntimeVenvURL.path) else {
            return false
        }

        try? fileManager.removeItem(at: VoicePowerPaths.runtimeVenvURL)
        try? fileManager.removeItem(at: VoicePowerPaths.runtimeReadyMarkerURL)
        try? fileManager.removeItem(at: VoicePowerPaths.installedBundledRuntimeManifestURL)

        try fileManager.copyItem(at: bundledRuntimeVenvURL, to: VoicePowerPaths.runtimeVenvURL)

        if let bundledManifestURL = VoicePowerPaths.bundledRuntimeManifestURL,
           fileManager.fileExists(atPath: bundledManifestURL.path) {
            try fileManager.copyItem(at: bundledManifestURL, to: VoicePowerPaths.installedBundledRuntimeManifestURL)
        }

        guard runtimePythonLooksCompatible(at: VoicePowerPaths.runtimePythonURL) else {
            try? fileManager.removeItem(at: VoicePowerPaths.runtimeVenvURL)
            try? fileManager.removeItem(at: VoicePowerPaths.installedBundledRuntimeManifestURL)
            return false
        }

        try "ready\n".write(to: VoicePowerPaths.runtimeReadyMarkerURL, atomically: true, encoding: .utf8)
        return true
    }

    private static func prefetchWhisperModel(_ model: String) throws {
        let markerURL = VoicePowerPaths.markerURL(kind: "whisper", model: model)
        if FileManager.default.fileExists(atPath: markerURL.path) {
            return
        }

        let result = try ProcessRunner.run(
            executableURL: VoicePowerPaths.runtimePythonURL,
            arguments: [
                VoicePowerPaths.scriptURL(named: "mlx_whisper_transcribe.py").path,
                "--model",
                model,
                "--download-only",
                "--hf-home",
                VoicePowerPaths.huggingFaceCacheURL.path,
            ],
            environment: [
                "HF_HOME": VoicePowerPaths.huggingFaceCacheURL.path,
                "TOKENIZERS_PARALLELISM": "false",
            ]
        )

        guard result.terminationStatus == 0 else {
            throw VoicePowerError.runtimeBootstrapFailed(result.standardError.nonEmptyOr(result.standardOutput))
        }

        try "ready\n".write(to: markerURL, atomically: true, encoding: .utf8)
    }

    private static func prefetchCleanupModel(_ model: String) throws {
        let markerURL = VoicePowerPaths.markerURL(kind: "cleanup", model: model)
        if FileManager.default.fileExists(atPath: markerURL.path) {
            return
        }

        let result = try ProcessRunner.run(
            executableURL: VoicePowerPaths.runtimePythonURL,
            arguments: [
                VoicePowerPaths.scriptURL(named: "mlx_cleanup_polish.py").path,
                "--model",
                model,
                "--download-only",
                "--hf-home",
                VoicePowerPaths.huggingFaceCacheURL.path,
            ],
            environment: [
                "HF_HOME": VoicePowerPaths.huggingFaceCacheURL.path,
                "TOKENIZERS_PARALLELISM": "false",
            ]
        )

        guard result.terminationStatus == 0 else {
            throw VoicePowerError.runtimeBootstrapFailed(result.standardError.nonEmptyOr(result.standardOutput))
        }

        try "ready\n".write(to: markerURL, atomically: true, encoding: .utf8)
    }

    private static func locateBootstrapPython() throws -> URL {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) }
            .map { URL(fileURLWithPath: $0).appendingPathComponent("python3").path }
        let candidatePaths = [
            environment["PYTHON3_PATH"],
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("anaconda3/bin/python3").path,
            "/usr/bin/python3",
        ]
        .compactMap { $0 }

        let orderedCandidates = Array(NSOrderedSet(array: pathCandidates + candidatePaths)).compactMap { $0 as? String }
        var fallbackURL: URL?

        for path in orderedCandidates where fileManager.isExecutableFile(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if fallbackURL == nil {
                fallbackURL = url
            }

            if runtimePythonLooksCompatible(at: url) {
                return url
            }
        }

        if let fallbackURL {
            return fallbackURL
        }

        throw VoicePowerError.pythonRuntimeMissing
    }

    private static func runtimePythonLooksCompatible(at executableURL: URL) -> Bool {
        guard let result = try? ProcessRunner.run(
            executableURL: executableURL,
            arguments: [
                "-c",
                """
                import ssl, sys
                print(f"{sys.version_info.major}.{sys.version_info.minor}")
                print(ssl.OPENSSL_VERSION)
                """
            ]
        ), result.terminationStatus == 0 else {
            return false
        }

        let lines = result.standardOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        guard lines.count >= 2 else {
            return false
        }

        let versionParts = lines[0].split(separator: ".").compactMap { Int($0) }
        guard versionParts.count >= 2 else {
            return false
        }

        let major = versionParts[0]
        let minor = versionParts[1]
        let sslVersion = lines[1]

        return major > 3 || (major == 3 && minor >= 10 && !sslVersion.contains("LibreSSL"))
    }
}
