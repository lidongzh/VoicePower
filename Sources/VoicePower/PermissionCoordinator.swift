import AVFoundation
import ApplicationServices
import Foundation
import CoreGraphics

@MainActor
final class PermissionCoordinator {
    func requestPermissionsIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }

        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
    }

    func ensureReadyForRecording() throws {
        let audioAuthorization = AVCaptureDevice.authorizationStatus(for: .audio)
        guard audioAuthorization == .authorized else {
            throw VoicePowerError.microphonePermissionMissing
        }

        guard AXIsProcessTrusted() else {
            throw VoicePowerError.accessibilityPermissionMissing
        }
    }

    func ensureReadyForHoldToTalk() throws {
        guard CGPreflightListenEventAccess() else {
            throw VoicePowerError.inputMonitoringPermissionMissing
        }
    }
}
