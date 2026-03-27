import AVFoundation
import Foundation

final class AudioRecorder: NSObject {
    private let recordingsDirectory: URL
    private var recorder: AVAudioRecorder?
    private var currentRecordingURL: URL?

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    init(recordingsDirectory: URL) throws {
        self.recordingsDirectory = recordingsDirectory
        super.init()

        try FileManager.default.createDirectory(
            at: recordingsDirectory,
            withIntermediateDirectories: true
        )
    }

    func startRecording() throws -> URL {
        if isRecording {
            throw VoicePowerError.recordingAlreadyInProgress
        }

        let fileName = "voice-power-\(Self.timestampFormatter.string(from: Date())).wav"
        let recordingURL = recordingsDirectory.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        guard recorder.prepareToRecord() else {
            throw VoicePowerError.recordingFailedToStart(reason: "prepareToRecord returned false")
        }

        guard recorder.record() else {
            throw VoicePowerError.recordingFailedToStart(reason: "record() returned false")
        }

        self.recorder = recorder
        currentRecordingURL = recordingURL
        return recordingURL
    }

    func stopRecording() throws -> URL {
        guard let recorder, let recordingURL = currentRecordingURL else {
            throw VoicePowerError.recordingNotInProgress
        }

        recorder.stop()
        self.recorder = nil
        currentRecordingURL = nil
        return recordingURL
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
