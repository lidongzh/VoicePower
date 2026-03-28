import Carbon.HIToolbox
import Foundation

struct AppConfig: Codable, Sendable {
    let recordingsDirectory: String?
    let recording: RecordingConfig?
    let hotkey: HotKeyConfig
    let holdToTalk: HoldToTalkConfig?
    let transcription: TranscriptionConfig
    let normalization: TextNormalizationConfig?
    let cleanup: CleanupConfig?
    let vocabulary: VocabularyConfig?
    let insertion: InsertionConfig

    var recordingsDirectoryURL: URL {
        let rawPath = recordingsDirectory ?? "~/Library/Application Support/VoicePower/Recordings"
        return URL(fileURLWithPath: rawPath.expandedTildePath)
    }

    var cleanupEnabled: Bool {
        cleanup?.enabled == true
    }

    var saveAudioFilesEnabled: Bool {
        recording?.saveAudioFiles ?? RecordingConfig.defaultConfig.saveAudioFiles
    }

    var resolvedHoldToTalk: HoldToTalkConfig {
        holdToTalk ?? .defaultConfig
    }

    var resolvedNormalization: TextNormalizationConfig {
        normalization ?? .defaultConfig
    }

    var resolvedTranscription: TranscriptionConfig {
        transcription.withDefaults()
    }

    var resolvedCleanup: CleanupConfig {
        (cleanup ?? .defaultConfig).withDefaults()
    }

    var resolvedVocabulary: VocabularyConfig {
        (vocabulary ?? .defaultConfig).withDefaults()
    }

    var needsManagedRuntimeMigration: Bool {
        resolvedTranscription.looksLikeLegacyManagedRuntime
            || resolvedNormalization.looksLikeLegacyManagedRuntime
            || resolvedCleanup.looksLikeLegacyManagedRuntime
    }

    var needsCleanupPromptRefresh: Bool {
        resolvedCleanup.usesLegacyPromptDefaults
    }

    func migratedToManagedRuntimeDefaults() -> AppConfig {
        AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: recording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: resolvedTranscription.migratedToManagedRuntime(),
            normalization: resolvedNormalization.migratedToManagedRuntime(),
            cleanup: resolvedCleanup.migratedToManagedRuntime(),
            vocabulary: resolvedVocabulary,
            insertion: insertion
        )
    }

    func refreshedCleanupPromptDefaults() -> AppConfig {
        AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: recording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: transcription,
            normalization: normalization,
            cleanup: resolvedCleanup.refreshingPromptDefaults(),
            vocabulary: vocabulary,
            insertion: insertion
        )
    }

    func toggledCleanupEnabled() -> AppConfig {
        let nextEnabled = !cleanupEnabled
        let nextCleanup = resolvedCleanup.withEnabled(nextEnabled)

        return AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: recording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: transcription,
            normalization: normalization,
            cleanup: nextCleanup,
            vocabulary: vocabulary,
            insertion: insertion
        )
    }

    func toggledAutoPunctuationEnabled() -> AppConfig {
        let nextEnabled = !resolvedCleanup.autoPunctuationEnabled
        let nextCleanup = resolvedCleanup.withAutoPunctuation(nextEnabled)

        return AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: recording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: transcription,
            normalization: normalization,
            cleanup: nextCleanup,
            vocabulary: vocabulary,
            insertion: insertion
        )
    }

    func toggledSaveAudioFiles() -> AppConfig {
        let nextEnabled = !saveAudioFilesEnabled
        let nextRecording = (recording ?? .defaultConfig).withSaveAudioFiles(nextEnabled)

        return AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: nextRecording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: transcription,
            normalization: normalization,
            cleanup: cleanup,
            vocabulary: vocabulary,
            insertion: insertion
        )
    }

    func settingCleanupEnabled(_ enabled: Bool) -> AppConfig {
        let nextCleanup = resolvedCleanup.withEnabled(enabled)

        return AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: recording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: transcription,
            normalization: normalization,
            cleanup: nextCleanup,
            vocabulary: vocabulary,
            insertion: insertion
        )
    }

    func settingAutoPunctuationEnabled(_ enabled: Bool) -> AppConfig {
        let nextCleanup = resolvedCleanup.withAutoPunctuation(enabled)

        return AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: recording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: transcription,
            normalization: normalization,
            cleanup: nextCleanup,
            vocabulary: vocabulary,
            insertion: insertion
        )
    }

    func settingSaveAudioFilesEnabled(_ enabled: Bool) -> AppConfig {
        let nextRecording = (recording ?? .defaultConfig).withSaveAudioFiles(enabled)

        return AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: nextRecording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: transcription,
            normalization: normalization,
            cleanup: cleanup,
            vocabulary: vocabulary,
            insertion: insertion
        )
    }

    func settingTranscriptionModel(_ model: String) -> AppConfig {
        let nextTranscription = resolvedTranscription.withModel(model)

        return AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: recording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: nextTranscription,
            normalization: normalization,
            cleanup: cleanup,
            vocabulary: vocabulary,
            insertion: insertion
        )
    }

    func settingTranscriptionProvider(_ provider: InferenceProvider) -> AppConfig {
        let nextTranscription = resolvedTranscription.withProvider(provider)

        return AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: recording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: nextTranscription,
            normalization: normalization,
            cleanup: cleanup,
            vocabulary: vocabulary,
            insertion: insertion
        )
    }

    func settingCleanupModel(_ model: String) -> AppConfig {
        let nextCleanup = resolvedCleanup.withModel(model)

        return AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: recording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: transcription,
            normalization: normalization,
            cleanup: nextCleanup,
            vocabulary: vocabulary,
            insertion: insertion
        )
    }

    func settingCleanupProvider(_ provider: InferenceProvider) -> AppConfig {
        let nextCleanup = resolvedCleanup.withProvider(provider)

        return AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: recording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: transcription,
            normalization: normalization,
            cleanup: nextCleanup,
            vocabulary: vocabulary,
            insertion: insertion
        )
    }

    func settingVocabulary(_ vocabulary: VocabularyConfig) -> AppConfig {
        AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: recording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: transcription,
            normalization: normalization,
            cleanup: cleanup,
            vocabulary: vocabulary.withDefaults(),
            insertion: insertion
        )
    }

    var localRuntimeRequirements: LocalRuntimeRequirements {
        let needsLocalTranscription = resolvedTranscription.usesManagedLocalModel
        let needsLocalCleanup = cleanupEnabled && resolvedCleanup.usesManagedLocalModel
        let needsLocalNormalization = resolvedNormalization.usesManagedRuntime

        return LocalRuntimeRequirements(
            needsBaseRuntime: needsLocalTranscription || needsLocalCleanup || needsLocalNormalization,
            needsWorker: needsLocalTranscription || needsLocalCleanup,
            needsWhisperModel: needsLocalTranscription,
            needsCleanupModel: needsLocalCleanup
        )
    }
}

struct HotKeyConfig: Codable, Sendable {
    let keyCode: UInt32
    let modifiers: [HotKeyModifier]

    var carbonModifiers: UInt32 {
        modifiers.reduce(0) { partialResult, modifier in
            partialResult | modifier.carbonValue
        }
    }
}

struct HoldToTalkConfig: Codable, Sendable {
    let enabled: Bool
    let activationDelayMilliseconds: Int?

    var activationDelaySeconds: TimeInterval {
        let milliseconds = activationDelayMilliseconds ?? 180
        return max(0, Double(milliseconds) / 1_000)
    }

    static let defaultConfig = HoldToTalkConfig(
        enabled: true,
        activationDelayMilliseconds: 180
    )
}

struct RecordingConfig: Codable, Sendable {
    let saveAudioFiles: Bool

    func withSaveAudioFiles(_ enabled: Bool) -> RecordingConfig {
        RecordingConfig(saveAudioFiles: enabled)
    }

    static let defaultConfig = RecordingConfig(saveAudioFiles: false)
}

enum InferenceProvider: String, Codable, Sendable, CaseIterable {
    case local
    case groq

    var title: String {
        switch self {
        case .local:
            return "Local"
        case .groq:
            return "Groq"
        }
    }
}

enum HotKeyModifier: String, Codable, Sendable {
    case command
    case control
    case option
    case shift

    var carbonValue: UInt32 {
        switch self {
        case .command:
            return UInt32(cmdKey)
        case .control:
            return UInt32(controlKey)
        case .option:
            return UInt32(optionKey)
        case .shift:
            return UInt32(shiftKey)
        }
    }
}

struct TranscriptionConfig: Codable, Sendable {
    let model: String?
    let language: String?
    let command: String?
    let arguments: [String]?
    let outputTextPath: String?
    let provider: InferenceProvider?

    var usesLegacyCommand: Bool {
        guard let command, let arguments else {
            return false
        }

        return !command.isEmpty && !arguments.isEmpty
    }

    var looksLikeLegacyManagedRuntime: Bool {
        guard (arguments ?? []).contains(where: { $0.contains("mlx_whisper_transcribe.py") }) else {
            return false
        }

        return (command ?? "").contains(".venv-mlx-whisper") || (command ?? "").contains("voice_power")
    }

    var resolvedProvider: InferenceProvider {
        provider ?? .local
    }

    var usesManagedLocalModel: Bool {
        resolvedProvider == .local && !usesLegacyCommand
    }

    var resolvedModel: String {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidate = trimmed.isEmpty ? Self.defaultModel(for: resolvedProvider) : trimmed
        return Self.canonicalModelID(candidate)
    }

    var resolvedLanguage: String {
        let trimmed = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "auto" : trimmed
    }

    func withDefaults() -> TranscriptionConfig {
        TranscriptionConfig(
            model: resolvedModel,
            language: resolvedLanguage,
            command: command,
            arguments: arguments,
            outputTextPath: outputTextPath,
            provider: provider
        )
    }

    func withModel(_ model: String) -> TranscriptionConfig {
        TranscriptionConfig(
            model: Self.canonicalModelID(model),
            language: resolvedLanguage,
            command: nil,
            arguments: nil,
            outputTextPath: nil,
            provider: provider
        )
    }

    func withProvider(_ provider: InferenceProvider) -> TranscriptionConfig {
        TranscriptionConfig(
            model: Self.defaultModel(for: provider),
            language: resolvedLanguage,
            command: nil,
            arguments: nil,
            outputTextPath: nil,
            provider: provider
        )
    }

    func migratedToManagedRuntime() -> TranscriptionConfig {
        TranscriptionConfig(
            model: Self.canonicalModelID(model ?? argumentValue(after: "--model") ?? Self.defaultModel),
            language: language ?? argumentValue(after: "--language") ?? "auto",
            command: nil,
            arguments: nil,
            outputTextPath: nil,
            provider: provider
        )
    }

    private func argumentValue(after flag: String) -> String? {
        guard let arguments else {
            return nil
        }

        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }

        return arguments[index + 1]
    }

    static func canonicalModelID(_ model: String) -> String {
        switch model.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "mlx-community/whisper-medium":
            return "mlx-community/whisper-medium-mlx"
        case "mlx-community/whisper-small":
            return "mlx-community/whisper-small-mlx"
        case "mlx-community/whisper-tiny":
            return "mlx-community/whisper-tiny-mlx"
        default:
            return model.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static var defaultModel: String {
        defaultModel(for: .local)
    }

    static func defaultModel(for provider: InferenceProvider) -> String {
        switch provider {
        case .local:
            return "mlx-community/whisper-large-v3-turbo"
        case .groq:
            return "whisper-large-v3-turbo"
        }
    }
}

struct TextNormalizationConfig: Codable, Sendable {
    let simplifiedChinese: Bool
    let command: String?
    let arguments: [String]?

    var usesLegacyCommand: Bool {
        guard let command, let arguments else {
            return false
        }

        return !command.isEmpty && !arguments.isEmpty
    }

    var usesManagedRuntime: Bool {
        simplifiedChinese && !usesLegacyCommand
    }

    var looksLikeLegacyManagedRuntime: Bool {
        guard (arguments ?? []).contains(where: { $0.contains("simplify_chinese_text.py") }) else {
            return false
        }

        return (command ?? "").contains(".venv-mlx-whisper") || (command ?? "").contains("voice_power")
    }

    func migratedToManagedRuntime() -> TextNormalizationConfig {
        TextNormalizationConfig(
            simplifiedChinese: simplifiedChinese,
            command: nil,
            arguments: nil
        )
    }

    static let defaultConfig = TextNormalizationConfig(
        simplifiedChinese: true,
        command: nil,
        arguments: nil
    )
}

struct CleanupConfig: Codable, Sendable {
    let enabled: Bool
    let endpoint: String?
    let model: String?
    let temperature: Double?
    let autoPunctuation: Bool?
    let systemPrompt: String?
    let userPromptTemplate: String?
    let provider: InferenceProvider?

    var autoPunctuationEnabled: Bool {
        autoPunctuation ?? true
    }

    var resolvedProvider: InferenceProvider {
        provider ?? .local
    }

    var usesLegacyEndpoint: Bool {
        provider == nil && !(endpoint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var usesManagedLocalModel: Bool {
        resolvedProvider == .local && !usesLegacyEndpoint
    }

    var resolvedModel: String {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? Self.defaultModel(for: resolvedProvider) : trimmed
    }

    var looksLikeLegacyManagedRuntime: Bool {
        if let endpoint, endpoint.contains("127.0.0.1:11434") || endpoint.contains("localhost:11434") {
            return true
        }

        return (model ?? "").contains(":")
    }

    var usesLegacyPromptDefaults: Bool {
        let normalizedSystemPrompt = (systemPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUserPrompt = (userPromptTemplate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedSystemPrompt == CleanupPromptDefaults.legacySystemPrompt
            || normalizedUserPrompt == CleanupPromptDefaults.legacyUserPromptTemplate
    }

    func withEnabled(_ enabled: Bool) -> CleanupConfig {
        CleanupConfig(
            enabled: enabled,
            endpoint: endpoint,
            model: model,
            temperature: temperature,
            autoPunctuation: autoPunctuation,
            systemPrompt: systemPrompt,
            userPromptTemplate: userPromptTemplate,
            provider: provider
        )
    }

    func withAutoPunctuation(_ enabled: Bool) -> CleanupConfig {
        CleanupConfig(
            enabled: self.enabled,
            endpoint: endpoint,
            model: model,
            temperature: temperature,
            autoPunctuation: enabled,
            systemPrompt: systemPrompt,
            userPromptTemplate: userPromptTemplate,
            provider: provider
        )
    }

    func withModel(_ model: String) -> CleanupConfig {
        CleanupConfig(
            enabled: enabled,
            endpoint: nil,
            model: model,
            temperature: temperature,
            autoPunctuation: autoPunctuation,
            systemPrompt: systemPrompt,
            userPromptTemplate: userPromptTemplate,
            provider: provider
        )
    }

    func withProvider(_ provider: InferenceProvider) -> CleanupConfig {
        CleanupConfig(
            enabled: enabled,
            endpoint: nil,
            model: Self.defaultModel(for: provider),
            temperature: temperature,
            autoPunctuation: autoPunctuation,
            systemPrompt: systemPrompt,
            userPromptTemplate: userPromptTemplate,
            provider: provider
        )
    }

    func withDefaults() -> CleanupConfig {
        CleanupConfig(
            enabled: enabled,
            endpoint: endpoint,
            model: resolvedModel,
            temperature: temperature ?? 0.0,
            autoPunctuation: autoPunctuationEnabled,
            systemPrompt: systemPrompt ?? CleanupPromptDefaults.systemPrompt,
            userPromptTemplate: userPromptTemplate ?? CleanupPromptDefaults.userPromptTemplate,
            provider: provider
        )
    }

    func migratedToManagedRuntime() -> CleanupConfig {
        let migratedModel: String
        if let model, !model.isEmpty, !model.contains(":") {
            migratedModel = model
        } else {
            migratedModel = Self.defaultModel
        }

        return CleanupConfig(
            enabled: enabled,
            endpoint: nil,
            model: migratedModel,
            temperature: temperature ?? 0.0,
            autoPunctuation: autoPunctuationEnabled,
            systemPrompt: systemPrompt ?? CleanupPromptDefaults.systemPrompt,
            userPromptTemplate: userPromptTemplate ?? CleanupPromptDefaults.userPromptTemplate,
            provider: provider
        )
    }

    func refreshingPromptDefaults() -> CleanupConfig {
        CleanupConfig(
            enabled: enabled,
            endpoint: endpoint,
            model: model,
            temperature: temperature,
            autoPunctuation: autoPunctuation,
            systemPrompt: usesLegacyPromptDefaults ? CleanupPromptDefaults.systemPrompt : systemPrompt,
            userPromptTemplate: usesLegacyPromptDefaults ? CleanupPromptDefaults.userPromptTemplate : userPromptTemplate,
            provider: provider
        )
    }

    static let defaultConfig = CleanupConfig(
        enabled: false,
        endpoint: nil,
        model: Self.defaultModel,
        temperature: 0.0,
        autoPunctuation: true,
        systemPrompt: CleanupPromptDefaults.systemPrompt,
        userPromptTemplate: CleanupPromptDefaults.userPromptTemplate,
        provider: nil
    )

    static var defaultModel: String {
        defaultModel(for: .local)
    }

    static func defaultModel(for provider: InferenceProvider) -> String {
        switch provider {
        case .local:
            return "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        case .groq:
            return "llama-3.3-70b-versatile"
        }
    }
}

struct LocalRuntimeRequirements {
    let needsBaseRuntime: Bool
    let needsWorker: Bool
    let needsWhisperModel: Bool
    let needsCleanupModel: Bool

    var needsPreparation: Bool {
        needsBaseRuntime || needsWorker || needsWhisperModel || needsCleanupModel
    }
}

struct VocabularyConfig: Codable, Sendable {
    let enabled: Bool
    let entries: [VocabularyEntry]

    func withEnabled(_ enabled: Bool) -> VocabularyConfig {
        VocabularyConfig(enabled: enabled, entries: entries)
    }

    func withEntries(_ entries: [VocabularyEntry]) -> VocabularyConfig {
        VocabularyConfig(enabled: enabled, entries: entries)
    }

    func withDefaults() -> VocabularyConfig {
        VocabularyConfig(
            enabled: enabled,
            entries: entries.filter { !$0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
    }

    static let defaultConfig = VocabularyConfig(
        enabled: true,
        entries: []
    )
}

struct VocabularyEntry: Codable, Sendable {
    let target: String
    let aliases: [String]
    let caseSensitive: Bool?
    let matchWholeWords: Bool?

    var resolvedTarget: String {
        target.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedAliases: [String] {
        aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var resolvedCaseSensitive: Bool {
        caseSensitive ?? false
    }
}

struct InsertionConfig: Codable, Sendable {
    let restoreClipboard: Bool
}

struct LoadedAppConfig {
    let config: AppConfig
    let url: URL
    let createdDefaultConfig: Bool
}

enum AppConfigLoader {
    static let defaultConfigURL = URL(fileURLWithPath: "~/.voice-power/config.json".expandedTildePath)

    static func load() throws -> LoadedAppConfig {
        let path = ProcessInfo.processInfo.environment["VOICE_POWER_CONFIG"]?.expandedTildePath
        let configURL = path.map(URL.init(fileURLWithPath:)) ?? defaultConfigURL

        let createdDefaultConfig: Bool
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            try createSampleConfig(at: configURL)
            createdDefaultConfig = true
            let data = try Data(contentsOf: configURL)
            return LoadedAppConfig(
                config: try JSONDecoder().decode(AppConfig.self, from: data),
                url: configURL,
                createdDefaultConfig: createdDefaultConfig
            )
        }

        let data = try Data(contentsOf: configURL)
        do {
            let decodedConfig = try JSONDecoder().decode(AppConfig.self, from: data)
            if decodedConfig.needsManagedRuntimeMigration {
                let migratedConfig = decodedConfig.migratedToManagedRuntimeDefaults()
                try save(migratedConfig, to: configURL)
                return LoadedAppConfig(
                    config: migratedConfig,
                    url: configURL,
                    createdDefaultConfig: false
                )
            }

            if decodedConfig.needsCleanupPromptRefresh {
                let refreshedConfig = decodedConfig.refreshedCleanupPromptDefaults()
                try save(refreshedConfig, to: configURL)
                return LoadedAppConfig(
                    config: refreshedConfig,
                    url: configURL,
                    createdDefaultConfig: false
                )
            }

            return LoadedAppConfig(config: decodedConfig, url: configURL, createdDefaultConfig: false)
        } catch {
            throw VoicePowerError.invalidConfig(reason: error.localizedDescription)
        }
    }

    static func save(_ config: AppConfig, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(config)
        try data.write(to: url)
    }

    private static func createSampleConfig(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try sampleConfigJSON.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let sampleConfigJSON = """
    {
      "recordingsDirectory": "~/Library/Application Support/VoicePower/Recordings",
      "recording": {
        "saveAudioFiles": false
      },
      "hotkey": {
        "keyCode": 49,
        "modifiers": ["control", "option"]
      },
      "holdToTalk": {
        "enabled": true,
        "activationDelayMilliseconds": 180
      },
      "transcription": {
        "provider": "local",
        "model": "\(TranscriptionConfig.defaultModel)",
        "language": "auto"
      },
      "normalization": {
        "simplifiedChinese": true
      },
      "cleanup": {
        "enabled": false,
        "provider": "local",
        "model": "\(CleanupConfig.defaultModel)",
        "temperature": 0.0,
        "autoPunctuation": true,
        "systemPrompt": "\(CleanupPromptDefaults.escapedSystemPrompt)",
        "userPromptTemplate": "\(CleanupPromptDefaults.escapedUserPromptTemplate)"
      },
      "vocabulary": {
        "enabled": true,
        "entries": [
          {
            "target": "GitHub",
            "aliases": ["git hub", "githup"],
            "caseSensitive": false,
            "matchWholeWords": true
          }
        ]
      },
      "insertion": {
        "restoreClipboard": true
      }
    }
    """
}

enum CleanupPromptDefaults {
    static let legacySystemPrompt = """
    You are a bilingual dictation cleanup engine.
    Your job is to remove filler words, false starts, and duplicates while preserving the exact language of each span.
    Never translate English into Chinese.
    Never translate Chinese into English.
    Keep code-switching intact.
    If output contains Chinese characters, use simplified Chinese script.
    Output only the cleaned text.
    Example input: um okay 所以 tomorrow we can maybe 再看一下这个 part.
    Example output: 所以 tomorrow we can 再看一下这个 part.
    Example input: uh the cleanup option 应该默认关闭.
    Example output: the cleanup option 应该默认关闭.
    """

    static let systemPrompt = """
    You are a bilingual dictation cleanup engine.
    Your job is to remove filler words, false starts, duplicated fragments, and obvious speech disfluencies only when it is safe.
    Never translate English into Chinese.
    Never translate Chinese into English.
    Keep code-switching intact.
    If output contains Chinese characters, use simplified Chinese script.
    Add punctuation when it is clearly implied by the speaker's phrasing or pauses.
    Use Chinese punctuation for Chinese spans and standard English punctuation for English spans when natural.
    Do not over-rewrite or add information.
    Output only the cleaned final text.
    Example input: um okay 所以 tomorrow we can maybe 再看一下这个 part
    Example output: 所以 tomorrow we can 再看一下这个 part.
    Example input: uh the cleanup option 应该默认关闭因为它会改变输出
    Example output: the cleanup option 应该默认关闭，因为它会改变输出。
    Example input: 这个东西为什么不会自己加上标点符号呢如果要disable这个cleanup model该怎么做呢
    Example output: 这个东西为什么不会自己加上标点符号呢？如果要 disable 这个 cleanup model，该怎么做呢？
    """

    static let legacyUserPromptTemplate = """
    Input: {{text}}
    Output:
    """

    static let userPromptTemplate = """
    Clean up this dictated text without changing meaning.
    Preserve mixed English and Chinese exactly as spoken.
    Add punctuation only when it is clearly helpful and safe.
    Return only the final cleaned text.

    Raw transcript:
    {{text}}
    """

    static var escapedSystemPrompt: String {
        systemPrompt.jsonEscaped
    }

    static var escapedUserPromptTemplate: String {
        userPromptTemplate.jsonEscaped
    }
}
