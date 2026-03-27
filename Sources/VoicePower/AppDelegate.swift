import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissions = PermissionCoordinator()
    private let runtimeBootstrapper = RuntimeBootstrapper()
    private var statusMenuController: StatusMenuController?
    private var settingsWindowController: SettingsWindowController?
    private var voiceTypingController: VoiceTypingController?
    private var hotKeyManager: HotKeyManager?
    private var rightCommandHoldManager: RightCommandHoldManager?
    private var lastPresentedRuntimeError: String?
    private var currentConfig: AppConfig?
    private var currentConfigURL: URL?
    private var runtimePreparationTask: Task<Void, Never>?
    private var hasPresentedInputMonitoringReminder = false

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
            controller.onOpenSettings = { [weak self] in
                self?.showSettingsWindow()
            }
            controller.onOpenInputMonitoringSettings = { [weak self] in
                self?.permissions.openInputMonitoringSettings()
            }
            controller.onPrepareRuntime = { [weak self] in
                self?.prepareRuntimeIfNeeded(includeCleanupModel: self?.currentConfig?.cleanupEnabled == true)
            }
            controller.onReload = { [weak self] in
                self?.configureApplication()
            }
            controller.onQuit = {
                NSApplication.shared.terminate(nil)
            }
            statusMenuController = controller
        }

        hotKeyManager = nil
        rightCommandHoldManager = nil
        voiceTypingController = nil

        do {
            let loadedConfig = try AppConfigLoader.load()
            let config = loadedConfig.config
            let configURL = loadedConfig.url
            currentConfig = config
            currentConfigURL = configURL

            let audioRecorder = try AudioRecorder(recordingsDirectory: config.recordingsDirectoryURL)
            let transcriber = WhisperTranscriber(config: config.resolvedTranscription)
            let textNormalizer = TextNormalizer(config: config.resolvedNormalization)
            let textPolisher = LocalCleanupPolisher(config: config.resolvedCleanup)
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
            ensureSettingsWindowController()
            settingsWindowController?.apply(config: config)
            statusMenuController?.setConfigPath(configURL.path.abbreviatedTildePath)
            settingsWindowController?.setRuntimePreparationInProgress(false)
            updateHoldToTalkPermissionStatus(using: config)
            statusMenuController?.update(
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
                    updateHoldToTalkPermissionStatus(using: config)
                    presentHoldToTalkPermissionAlertIfNeeded(for: error)
                }
            } else {
                updateHoldToTalkPermissionStatus(using: config)
            }

            refreshRuntimeStatus(using: config)
            prepareRuntimeIfNeeded(includeCleanupModel: config.cleanupEnabled)

            if loadedConfig.createdDefaultConfig {
                presentFirstLaunchAlert(configPath: configURL.path)
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

    private func refreshRuntimeStatus(using config: AppConfig) {
        runtimePreparationTask?.cancel()
        runtimePreparationTask = Task { [weak self] in
            guard let self else {
                return
            }

            let snapshot = await runtimeBootstrapper.snapshot(for: config)
            await MainActor.run {
                updateHoldToTalkPermissionStatus(using: config)
                let runtimeStatus = snapshot.baseRuntimeReady ? "Ready" : "Needs Setup"
                let whisperStatus = snapshot.whisperModelReady ? "Ready" : "Pending Download"
                let cleanupStatus: String
                if config.cleanupEnabled {
                    cleanupStatus = snapshot.cleanupModelReady ? "Ready" : "Pending Download"
                } else {
                    cleanupStatus = snapshot.cleanupModelReady ? "Ready (Optional)" : "Optional"
                }
                applyRuntimeStatuses(
                    runtime: runtimeStatus,
                    whisper: whisperStatus,
                    cleanup: cleanupStatus,
                    isPreparing: false
                )
            }
        }
    }

    private func updateHoldToTalkPermissionStatus(using config: AppConfig) {
        guard config.resolvedHoldToTalk.enabled else {
            statusMenuController?.setHoldToTalkPermissionStatus("Disabled", needsAction: false)
            return
        }

        if permissions.hasInputMonitoringPermission {
            statusMenuController?.setHoldToTalkPermissionStatus("Ready", needsAction: false)
        } else {
            statusMenuController?.setHoldToTalkPermissionStatus("Needs Input Monitoring", needsAction: true)
        }
    }

    private func ensureSettingsWindowController() {
        guard settingsWindowController == nil else {
            return
        }

        let controller = SettingsWindowController()
        controller.onWhisperModelChange = { [weak self] model in
            self?.setWhisperModel(model)
        }
        controller.onCleanupModelChange = { [weak self] model in
            self?.setCleanupModel(model)
        }
        controller.onCleanupEnabledChange = { [weak self] enabled in
            self?.setCleanupEnabled(enabled)
        }
        controller.onAutoPunctuationChange = { [weak self] enabled in
            self?.setAutoPunctuationEnabled(enabled)
        }
        controller.onSaveAudioChange = { [weak self] enabled in
            self?.setSaveAudioEnabled(enabled)
        }
        controller.onPrepareRuntime = { [weak self] in
            self?.prepareRuntimeIfNeeded(includeCleanupModel: self?.currentConfig?.cleanupEnabled == true)
        }
        settingsWindowController = controller
    }

    private func applyRuntimeStatuses(runtime: String, whisper: String, cleanup: String, isPreparing: Bool) {
        statusMenuController?.setRuntimeStatus(runtime)
        statusMenuController?.setWhisperModelStatus(whisper)
        statusMenuController?.setCleanupModelStatus(cleanup)
        settingsWindowController?.setRuntimeStatus(runtime)
        settingsWindowController?.setWhisperModelStatus(whisper)
        settingsWindowController?.setCleanupModelStatus(cleanup)
        settingsWindowController?.setRuntimePreparationInProgress(isPreparing)
    }

    private func showSettingsWindow() {
        guard let currentConfig else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        ensureSettingsWindowController()
        settingsWindowController?.show(with: currentConfig)
    }

    private func prepareRuntimeIfNeeded(includeCleanupModel: Bool) {
        guard let config = currentConfig else {
            return
        }

        runtimePreparationTask?.cancel()
        runtimePreparationTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                await MainActor.run {
                    applyRuntimeStatuses(
                        runtime: "Preparing",
                        whisper: "Downloading",
                        cleanup: includeCleanupModel ? "Pending Download" : "Optional",
                        isPreparing: true
                    )
                }
                try await runtimeBootstrapper.ensureBaseRuntimeReady()
                try await runtimeBootstrapper.ensureWhisperModelReady(config.resolvedTranscription.resolvedModel)

                await MainActor.run {
                    applyRuntimeStatuses(
                        runtime: "Ready",
                        whisper: "Ready",
                        cleanup: includeCleanupModel ? "Downloading" : "Optional",
                        isPreparing: includeCleanupModel
                    )
                }

                if includeCleanupModel {
                    await MainActor.run {
                        applyRuntimeStatuses(
                            runtime: "Ready",
                            whisper: "Ready",
                            cleanup: "Downloading",
                            isPreparing: true
                        )
                    }
                    try await runtimeBootstrapper.ensureCleanupModelReady(config.resolvedCleanup.resolvedModel)
                    await MainActor.run {
                        applyRuntimeStatuses(
                            runtime: "Ready",
                            whisper: "Ready",
                            cleanup: "Ready",
                            isPreparing: false
                        )
                    }
                } else {
                    await MainActor.run {
                        applyRuntimeStatuses(
                            runtime: "Ready",
                            whisper: "Ready",
                            cleanup: "Optional",
                            isPreparing: false
                        )
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    settingsWindowController?.setRuntimePreparationInProgress(false)
                }
                return
            } catch {
                await MainActor.run {
                    applyRuntimeStatuses(
                        runtime: "Error",
                        whisper: "Retry Needed",
                        cleanup: includeCleanupModel ? "Retry Needed" : "Optional",
                        isPreparing: false
                    )
                    presentRuntimeAlert(message: error.localizedDescription)
                }
            }
        }
    }

    private func presentFirstLaunchAlert(configPath: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "VoicePower is setting itself up"
        alert.informativeText = """
        VoicePower runs as a menu bar app. It has already created a default config at \(configPath) and is now preparing the local runtime and Whisper model in the background.

        Cleanup model download stays optional until you turn Cleanup on in Settings.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
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

    private func presentHoldToTalkPermissionAlertIfNeeded(for error: Error) {
        guard case VoicePowerError.inputMonitoringPermissionMissing = error else {
            presentRuntimeAlert(message: "Right Command hold-to-talk is unavailable: \(error.localizedDescription)")
            return
        }

        guard !hasPresentedInputMonitoringReminder else {
            return
        }

        hasPresentedInputMonitoringReminder = true
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Input Monitoring is required for right Command hold-to-talk"
        alert.informativeText = """
        VoicePower can still use the regular hotkey, but right Command hold-to-talk will not work until you enable:

        System Settings > Privacy & Security > Input Monitoring
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            permissions.openInputMonitoringSettings()
        }
    }

    private func setWhisperModel(_ model: String) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        persistUpdatedConfig(
            currentConfig.settingTranscriptionModel(model),
            to: currentConfigURL,
            errorPrefix: "Failed to update Whisper model",
            prepareRuntime: true
        )
    }

    private func setCleanupModel(_ model: String) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        persistUpdatedConfig(
            currentConfig.settingCleanupModel(model),
            to: currentConfigURL,
            errorPrefix: "Failed to update cleanup model",
            prepareRuntime: currentConfig.cleanupEnabled
        )
    }

    private func setCleanupEnabled(_ enabled: Bool) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        persistUpdatedConfig(
            currentConfig.settingCleanupEnabled(enabled),
            to: currentConfigURL,
            errorPrefix: "Failed to update cleanup setting",
            prepareRuntime: enabled
        )
    }

    private func setAutoPunctuationEnabled(_ enabled: Bool) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        persistUpdatedConfig(
            currentConfig.settingAutoPunctuationEnabled(enabled),
            to: currentConfigURL,
            errorPrefix: "Failed to update punctuation setting",
            prepareRuntime: false
        )
    }

    private func setSaveAudioEnabled(_ enabled: Bool) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        persistUpdatedConfig(
            currentConfig.settingSaveAudioFilesEnabled(enabled),
            to: currentConfigURL,
            errorPrefix: "Failed to update save-audio setting",
            prepareRuntime: false
        )
    }

    private func persistUpdatedConfig(_ updatedConfig: AppConfig, to url: URL, errorPrefix: String, prepareRuntime: Bool) {
        do {
            try AppConfigLoader.save(updatedConfig, to: url)
            currentConfig = updatedConfig
            configureApplication()
            settingsWindowController?.apply(config: updatedConfig)
            if prepareRuntime {
                prepareRuntimeIfNeeded(includeCleanupModel: updatedConfig.cleanupEnabled)
            }
        } catch {
            presentRuntimeAlert(message: "\(errorPrefix): \(error.localizedDescription)")
        }
    }
}
