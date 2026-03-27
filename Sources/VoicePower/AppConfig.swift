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

    func toggledCleanupEnabled() -> AppConfig {
        let nextEnabled = !cleanupEnabled
        let nextCleanup = (cleanup ?? CleanupConfig.defaultConfig).withEnabled(nextEnabled)

        return AppConfig(
            recordingsDirectory: recordingsDirectory,
            recording: recording,
            hotkey: hotkey,
            holdToTalk: holdToTalk,
            transcription: transcription,
            normalization: normalization,
            cleanup: nextCleanup,
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
            insertion: insertion
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

    static let defaultConfig = RecordingConfig(saveAudioFiles: true)
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
    let command: String
    let arguments: [String]
    let outputTextPath: String?
}

struct TextNormalizationConfig: Codable, Sendable {
    let simplifiedChinese: Bool
    let command: String?
    let arguments: [String]?

    static let defaultConfig = TextNormalizationConfig(
        simplifiedChinese: true,
        command: nil,
        arguments: nil
    )
}

struct CleanupConfig: Codable, Sendable {
    let enabled: Bool
    let endpoint: String
    let model: String
    let temperature: Double?
    let systemPrompt: String?
    let userPromptTemplate: String?

    func withEnabled(_ enabled: Bool) -> CleanupConfig {
        CleanupConfig(
            enabled: enabled,
            endpoint: endpoint,
            model: model,
            temperature: temperature,
            systemPrompt: systemPrompt,
            userPromptTemplate: userPromptTemplate
        )
    }

    static let defaultConfig = CleanupConfig(
        enabled: true,
        endpoint: "http://127.0.0.1:11434/api/generate",
        model: "qwen2.5:3b",
        temperature: 0.0,
        systemPrompt: CleanupPromptDefaults.systemPrompt,
        userPromptTemplate: CleanupPromptDefaults.userPromptTemplate
    )
}

struct InsertionConfig: Codable, Sendable {
    let restoreClipboard: Bool
}

enum AppConfigLoader {
    static let defaultConfigURL = URL(fileURLWithPath: "~/.voice-power/config.json".expandedTildePath)

    static func load() throws -> (AppConfig, URL) {
        let path = ProcessInfo.processInfo.environment["VOICE_POWER_CONFIG"]?.expandedTildePath
        let configURL = path.map(URL.init(fileURLWithPath:)) ?? defaultConfigURL

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            try createSampleConfig(at: configURL)
            throw VoicePowerError.createdSampleConfig(path: configURL.path)
        }

        let data = try Data(contentsOf: configURL)
        do {
            return (try JSONDecoder().decode(AppConfig.self, from: data), configURL)
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
        "saveAudioFiles": true
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
        "command": "/absolute/path/to/python3",
        "arguments": [
          "/absolute/path/to/scripts/mlx_whisper_transcribe.py",
          "--audio-path",
          "{{audio_path}}",
          "--model",
          "mlx-community/whisper-large-v3-turbo",
          "--language",
          "auto"
        ],
        "outputTextPath": null
      },
      "normalization": {
        "simplifiedChinese": true,
        "command": "/absolute/path/to/python3",
        "arguments": [
          "/absolute/path/to/scripts/simplify_chinese_text.py"
        ]
      },
      "cleanup": {
        "enabled": true,
        "endpoint": "http://127.0.0.1:11434/api/generate",
        "model": "qwen2.5:3b",
        "temperature": 0.0,
        "systemPrompt": "\(CleanupPromptDefaults.escapedSystemPrompt)",
        "userPromptTemplate": "\(CleanupPromptDefaults.escapedUserPromptTemplate)"
      },
      "insertion": {
        "restoreClipboard": true
      }
    }
    """
}

enum CleanupPromptDefaults {
    static let systemPrompt = """
    You are a bilingual dictation cleanup engine.
    Your job is to remove filler words, false starts, and duplicates while preserving the exact language of each span.
    Never translate English into Chinese.
    Never translate Chinese into English.
    Keep code-switching intact.
    If output contains Chinese characters, use simplified Chinese script.
    Output only the cleaned text.
    Example input: um okay 所以 tomorrow we can maybe 再看一下这个 part.
    Example output: 所以 tomorrow we can 再看一下这个 part.
    Example input: uh I think 这个 bug should be fixed today.
    Example output: I think 这个 bug should be fixed today.
    """

    static let userPromptTemplate = """
    Input: {{text}}
    Output:
    """

    static var escapedSystemPrompt: String {
        systemPrompt.jsonEscaped
    }

    static var escapedUserPromptTemplate: String {
        userPromptTemplate.jsonEscaped
    }
}
