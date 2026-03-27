import Foundation

enum VoicePowerError: LocalizedError {
    case createdSampleConfig(path: String)
    case missingConfig(path: String)
    case invalidConfig(reason: String)
    case hotKeyRegistrationFailed(reason: String)
    case holdToTalkRegistrationFailed(reason: String)
    case pythonRuntimeMissing
    case runtimeBootstrapFailed(String)
    case microphonePermissionMissing
    case accessibilityPermissionMissing
    case inputMonitoringPermissionMissing
    case recordingAlreadyInProgress
    case recordingNotInProgress
    case recordingFailedToStart(reason: String)
    case transcriptionCommandNotExecutable(String)
    case transcriptionFailed(details: String)
    case emptyTranscript
    case invalidCleanupEndpoint(String)
    case cleanupRequestFailed(String)
    case textNormalizationFailed(String)
    case textInjectionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .createdSampleConfig(path):
            return "Created a sample config at \(path). Edit it, then choose Reload Config from the VoicePower menu bar item."
        case let .missingConfig(path):
            return "Missing config: \(path)"
        case let .invalidConfig(reason):
            return "Invalid config: \(reason)"
        case let .hotKeyRegistrationFailed(reason):
            return "Hotkey registration failed: \(reason)"
        case let .holdToTalkRegistrationFailed(reason):
            return "Hold-to-talk registration failed: \(reason)"
        case .pythonRuntimeMissing:
            return "Python 3 was not found. Install Python 3 or Xcode Command Line Tools, then reopen VoicePower."
        case let .runtimeBootstrapFailed(details):
            return "Runtime setup failed: \(details)"
        case .microphonePermissionMissing:
            return "Microphone permission is missing"
        case .accessibilityPermissionMissing:
            return "Accessibility permission is missing"
        case .inputMonitoringPermissionMissing:
            return "Input Monitoring permission is missing"
        case .recordingAlreadyInProgress:
            return "Recording is already in progress"
        case .recordingNotInProgress:
            return "Recording is not in progress"
        case let .recordingFailedToStart(reason):
            return "Recording failed to start: \(reason)"
        case let .transcriptionCommandNotExecutable(path):
            return "Transcription command is not executable: \(path)"
        case let .transcriptionFailed(details):
            return "Transcription failed: \(details)"
        case .emptyTranscript:
            return "Transcription returned empty text"
        case let .invalidCleanupEndpoint(endpoint):
            return "Invalid cleanup endpoint: \(endpoint)"
        case let .cleanupRequestFailed(details):
            return "Cleanup request failed: \(details)"
        case let .textNormalizationFailed(details):
            return "Text normalization failed: \(details)"
        case let .textInjectionFailed(details):
            return "Text injection failed: \(details)"
        }
    }
}
