import AppKit
import Foundation

struct VoiceTypingState {
    let isRecording: Bool
    let isProcessing: Bool
    let queuedCount: Int
    let lastErrorMessage: String?

    var statusText: String {
        if isRecording, isProcessing {
            return queuedCount > 0 ? "Recording + Processing (\(queuedCount) queued)" : "Recording + Processing"
        }

        if isRecording {
            return queuedCount > 0 ? "Recording (\(queuedCount) queued)" : "Recording"
        }

        if isProcessing {
            return queuedCount > 0 ? "Processing (\(queuedCount) queued)" : "Processing"
        }

        if let lastErrorMessage {
            return lastErrorMessage
        }

        return "Idle"
    }

    var toggleTitle: String {
        isRecording ? "Stop Recording" : "Start Recording"
    }

    var toggleEnabled: Bool {
        true
    }

    var shortTitle: String {
        if isRecording {
            return "REC"
        }

        if isProcessing {
            return "RUN"
        }

        if lastErrorMessage != nil {
            return "ERR"
        }

        return "VP"
    }
}

@MainActor
final class VoiceTypingController {
    var onStateChange: ((VoiceTypingState) -> Void)?
    var onRuntimeError: ((String) -> Void)?

    private struct PendingRecording {
        let recordingURL: URL
        let targetApplication: NSRunningApplication?
    }

    private enum RecordingTrigger {
        case toggle
        case holdToTalk
    }

    private let audioRecorder: AudioRecorder
    private let transcriber: WhisperTranscriber
    private let vocabularyCorrector: VocabularyCorrector
    private let textNormalizer: TextNormalizer
    private let textPolisher: LocalCleanupPolisher
    private let textInjector: TextInjector
    private let permissions: PermissionCoordinator
    private let saveAudioFiles: Bool

    private var currentTargetApplication: NSRunningApplication?
    private var pendingRecordings: [PendingRecording] = []
    private var isProcessingQueue = false
    private var recordingTrigger: RecordingTrigger?
    private var lastErrorMessage: String?

    init(
        audioRecorder: AudioRecorder,
        transcriber: WhisperTranscriber,
        vocabularyCorrector: VocabularyCorrector,
        textNormalizer: TextNormalizer,
        textPolisher: LocalCleanupPolisher,
        textInjector: TextInjector,
        permissions: PermissionCoordinator,
        saveAudioFiles: Bool
    ) {
        self.audioRecorder = audioRecorder
        self.transcriber = transcriber
        self.vocabularyCorrector = vocabularyCorrector
        self.textNormalizer = textNormalizer
        self.textPolisher = textPolisher
        self.textInjector = textInjector
        self.permissions = permissions
        self.saveAudioFiles = saveAudioFiles
    }

    func toggleRecording() {
        if audioRecorder.isRecording {
            stopRecordingAndEnqueue()
        } else {
            startRecording(trigger: .toggle)
        }
    }

    func beginHoldToTalk() {
        guard !audioRecorder.isRecording else {
            return
        }

        startRecording(trigger: .holdToTalk)
    }

    func endHoldToTalk() {
        guard audioRecorder.isRecording, recordingTrigger == .holdToTalk else {
            return
        }

        stopRecordingAndEnqueue()
    }

    private func startRecording(trigger: RecordingTrigger) {
        do {
            try permissions.ensureReadyForRecording()
            clearLastError()
            currentTargetApplication = NSWorkspace.shared.frontmostApplication
            _ = try audioRecorder.startRecording()
            recordingTrigger = trigger
            emitState()
        } catch {
            currentTargetApplication = nil
            recordingTrigger = nil
            reportRuntimeError(error.localizedDescription)
        }
    }

    private func stopRecordingAndEnqueue() {
        do {
            let recordingURL = try audioRecorder.stopRecording()
            let pendingRecording = PendingRecording(
                recordingURL: recordingURL,
                targetApplication: currentTargetApplication
            )

            currentTargetApplication = nil
            recordingTrigger = nil
            clearLastError()
            pendingRecordings.append(pendingRecording)
            emitState()
            startProcessingQueueIfNeeded()
        } catch {
            currentTargetApplication = nil
            recordingTrigger = nil
            reportRuntimeError(error.localizedDescription)
        }
    }

    private func startProcessingQueueIfNeeded() {
        guard !isProcessingQueue else {
            emitState()
            return
        }

        guard !pendingRecordings.isEmpty else {
            emitState()
            return
        }

        isProcessingQueue = true
        emitState()
        processNextQueuedRecording()
    }

    private func processNextQueuedRecording() {
        guard !pendingRecordings.isEmpty else {
            isProcessingQueue = false
            emitState()
            return
        }

        clearLastError()
        let nextRecording = pendingRecordings.removeFirst()
        emitState()

        let transcriber = transcriber
        let vocabularyCorrector = vocabularyCorrector
        let textNormalizer = textNormalizer
        let textPolisher = textPolisher
        let textInjector = textInjector
        let saveAudioFiles = saveAudioFiles

        Task { [weak self] in
            let result: Result<Void, Error>

            do {
                let rawTranscript = try await Task.detached(priority: .userInitiated) {
                    try await transcriber.transcribe(audioFileURL: nextRecording.recordingURL)
                }.value
                let correctedTranscript = vocabularyCorrector.correct(rawTranscript)
                let polishedText = try await textPolisher.polish(correctedTranscript)
                let finalizedText = vocabularyCorrector.correct(polishedText)
                let normalizedText = try textNormalizer.normalize(finalizedText)
                try textInjector.insert(text: normalizedText, targeting: nextRecording.targetApplication)
                result = .success(())
            } catch {
                result = .failure(error)
            }

            if !saveAudioFiles {
                try? FileManager.default.removeItem(at: nextRecording.recordingURL)
            }

            guard let self else {
                return
            }

            switch result {
            case .success:
                break
            case let .failure(error):
                self.reportRuntimeError(error.localizedDescription)
            }

            self.processNextQueuedRecording()
        }
    }

    private func clearLastError() {
        lastErrorMessage = nil
    }

    private func reportRuntimeError(_ message: String) {
        lastErrorMessage = message
        emitState()
        onRuntimeError?(message)
    }

    private func emitState() {
        onStateChange?(
            VoiceTypingState(
                isRecording: audioRecorder.isRecording,
                isProcessing: isProcessingQueue,
                queuedCount: pendingRecordings.count,
                lastErrorMessage: lastErrorMessage
            )
        )
    }
}
