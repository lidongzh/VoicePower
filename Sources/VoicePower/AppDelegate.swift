import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissions = PermissionCoordinator()
    private var statusMenuController: StatusMenuController?
    private var voiceTypingController: VoiceTypingController?
    private var hotKeyManager: HotKeyManager?
    private var rightCommandHoldManager: RightCommandHoldManager?
    private var lastPresentedRuntimeError: String?
    private var currentConfig: AppConfig?
    private var currentConfigURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        permissions.requestPermissionsIfNeeded()
        configureApplication()
    }

    private func configureApplication() {
        let expectedConfigPath = AppConfigLoader.defaultConfigURL.path.abbreviatedTildePath

        if statusMenuController == nil {
            let controller = StatusMenuController(configPath: expectedConfigPath)
            controller.onToggle = { [weak self] in
                self?.voiceTypingController?.toggleRecording()
            }
            controller.onToggleCleanup = { [weak self] in
                self?.toggleCleanupEnabled()
            }
            controller.onToggleSaveAudio = { [weak self] in
                self?.toggleSaveAudioEnabled()
            }
            controller.onReload = { [weak self] in
                self?.configureApplication()
            }
            controller.onQuit = {
                NSApplication.shared.terminate(nil)
            }
            statusMenuController = controller
        }

        // Release the previous registration before reloading config so the same
        // global shortcut can be registered again without colliding.
        hotKeyManager = nil
        rightCommandHoldManager = nil
        voiceTypingController = nil

        do {
            let (config, configURL) = try AppConfigLoader.load()
            currentConfig = config
            currentConfigURL = configURL
            let audioRecorder = try AudioRecorder(recordingsDirectory: config.recordingsDirectoryURL)
            let transcriber = WhisperTranscriber(config: config.transcription)
            let textNormalizer = TextNormalizer(config: config.resolvedNormalization)
            let textPolisher = OllamaTextPolisher(config: config.cleanup)
            let textInjector = TextInjector(restoreClipboard: config.insertion.restoreClipboard)
            let voiceTypingController = VoiceTypingController(
                audioRecorder: audioRecorder,
                transcriber: transcriber,
                textNormalizer: textNormalizer,
                textPolisher: textPolisher,
                textInjector: textInjector,
                permissions: permissions,
                saveAudioFiles: config.saveAudioFilesEnabled
            )

            voiceTypingController.onStateChange = { [weak self] state in
                self?.statusMenuController?.setConfigPath(configURL.path.abbreviatedTildePath)
                self?.statusMenuController?.update(for: state)
            }

            voiceTypingController.onRuntimeError = { [weak self] message in
                self?.presentRuntimeAlert(message: message)
            }

            self.voiceTypingController = voiceTypingController
            self.statusMenuController?.setConfigPath(configURL.path.abbreviatedTildePath)
            self.statusMenuController?.setCleanupEnabled(config.cleanupEnabled)
            self.statusMenuController?.setSaveAudioEnabled(config.saveAudioFilesEnabled)
            self.statusMenuController?.update(
                for: VoiceTypingState(
                    isRecording: false,
                    isProcessing: false,
                    queuedCount: 0,
                    lastErrorMessage: nil
                )
            )

            do {
                hotKeyManager = try HotKeyManager(config: config.hotkey) { [weak voiceTypingController] in
                    voiceTypingController?.toggleRecording()
                }
            } catch {
                hotKeyManager = nil
                presentRuntimeAlert(message: "Hotkey registration failed: \(error.localizedDescription)")
            }

            if config.resolvedHoldToTalk.enabled {
                do {
                    try permissions.ensureReadyForHoldToTalk()
                    rightCommandHoldManager = try RightCommandHoldManager(
                        activationDelay: config.resolvedHoldToTalk.activationDelaySeconds,
                        onPress: { [weak voiceTypingController] in
                            voiceTypingController?.beginHoldToTalk()
                        },
                        onRelease: { [weak voiceTypingController] in
                            voiceTypingController?.endHoldToTalk()
                        }
                    )
                } catch {
                    rightCommandHoldManager = nil
                    presentRuntimeAlert(message: "Right Command hold-to-talk is unavailable: \(error.localizedDescription)")
                }
            }
        } catch {
            hotKeyManager = nil
            rightCommandHoldManager = nil
            voiceTypingController = nil
            statusMenuController?.update(
                for: VoiceTypingState(
                    isRecording: false,
                    isProcessing: false,
                    queuedCount: 0,
                    lastErrorMessage: error.localizedDescription
                )
            )
            presentLaunchAlert(for: error)
        }
    }

    private func presentLaunchAlert(for error: Error) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "VoicePower is a menu bar app"
        alert.informativeText = "\(error.localizedDescription)\n\nLook for the VoicePower item in the macOS menu bar."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentRuntimeAlert(message: String) {
        guard lastPresentedRuntimeError != message else {
            return
        }

        lastPresentedRuntimeError = message
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "VoicePower Error"
        alert.informativeText = "\(message)\n\nYou can also click the VoicePower menu bar item to see the current status."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        lastPresentedRuntimeError = nil
    }

    private func toggleCleanupEnabled() {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        do {
            let updatedConfig = currentConfig.toggledCleanupEnabled()
            try AppConfigLoader.save(updatedConfig, to: currentConfigURL)
            configureApplication()
        } catch {
            presentRuntimeAlert(message: "Failed to update cleanup setting: \(error.localizedDescription)")
        }
    }

    private func toggleSaveAudioEnabled() {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        do {
            let updatedConfig = currentConfig.toggledSaveAudioFiles()
            try AppConfigLoader.save(updatedConfig, to: currentConfigURL)
            configureApplication()
        } catch {
            presentRuntimeAlert(message: "Failed to update save-audio setting: \(error.localizedDescription)")
        }
    }
}
