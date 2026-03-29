import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissions = PermissionCoordinator()
    private let runtimeBootstrapper = RuntimeBootstrapper()
    private let inferenceWorker = InferenceWorkerManager()
    private let groqAPIKeyStore = GroqAPIKeyStore()
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
        ApplicationMenuController.installMainMenuIfNeeded()
        Task {
            await inferenceWorker.setStatusHandler { [weak self] state in
                Task { @MainActor in
                    self?.applyWorkerStatus(state.statusText)
                }
            }
        }
        permissions.requestPermissionsIfNeeded()
        configureApplication()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await inferenceWorker.shutdown()
        }
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
                self?.prepareRuntimeIfNeeded()
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
            let groqClient = GroqClient(apiKeyStore: groqAPIKeyStore)
            let transcriber = WhisperTranscriber(
                config: config.resolvedTranscription,
                workerManager: inferenceWorker,
                groqClient: groqClient
            )
            let vocabularyCorrector = VocabularyCorrector(config: config.resolvedVocabulary)
            let textNormalizer = TextNormalizer(config: config.resolvedNormalization)
            let textPolisher = LocalCleanupPolisher(
                config: config.resolvedCleanup,
                workerManager: inferenceWorker,
                groqClient: groqClient
            )
            let textInjector = TextInjector(restoreClipboard: config.insertion.restoreClipboard)
            let reviewWindowController = ReviewWindowController()
            let voiceTypingController = VoiceTypingController(
                audioRecorder: audioRecorder,
                transcriber: transcriber,
                vocabularyCorrector: vocabularyCorrector,
                textNormalizer: textNormalizer,
                textPolisher: textPolisher,
                textInjector: textInjector,
                reviewWindowController: reviewWindowController,
                permissions: permissions,
                saveAudioFiles: config.saveAudioFilesEnabled,
                reviewBeforePaste: config.reviewBeforePasteEnabled
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
            settingsWindowController?.apply(config: config, hasGroqAPIKey: hasStoredGroqAPIKey())
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
                        },
                        onCancel: { [weak voiceTypingController] in
                            voiceTypingController?.cancelHoldToTalk()
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
            prepareRuntimeIfNeeded()

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
                applyRuntimeSnapshot(snapshot, for: config, isPreparing: false)
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
        controller.onTranscriptionProviderChange = { [weak self] provider in
            self?.setTranscriptionProvider(provider)
        }
        controller.onWhisperModelChange = { [weak self] model in
            self?.setWhisperModel(model)
        }
        controller.onCleanupProviderChange = { [weak self] provider in
            self?.setCleanupProvider(provider)
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
        controller.onCleanupPunctuationStyleChange = { [weak self] style in
            self?.setCleanupPunctuationStyle(style)
        }
        controller.onCleanupPromptProfilesChange = { [weak self] promptProfiles, selectedPromptProfileID in
            self?.setCleanupPromptProfiles(promptProfiles, selectedPromptProfileID: selectedPromptProfileID)
        }
        controller.onSaveAudioChange = { [weak self] enabled in
            self?.setSaveAudioEnabled(enabled)
        }
        controller.onReviewBeforePasteChange = { [weak self] enabled in
            self?.setReviewBeforePasteEnabled(enabled)
        }
        controller.onHoldToTalkEnabledChange = { [weak self] enabled in
            self?.setHoldToTalkEnabled(enabled)
        }
        controller.onHoldToTalkDelayChange = { [weak self] milliseconds in
            self?.setHoldToTalkDelayMilliseconds(milliseconds)
        }
        controller.onVocabularySave = { [weak self] enabled, rawText in
            self?.setVocabulary(enabled: enabled, rawText: rawText)
        }
        controller.onPrepareRuntime = { [weak self] in
            self?.prepareRuntimeIfNeeded()
        }
        controller.onSaveGroqAPIKey = { [weak self] apiKey in
            self?.saveGroqAPIKey(apiKey)
        }
        controller.onClearGroqAPIKey = { [weak self] in
            self?.clearGroqAPIKey()
        }
        settingsWindowController = controller
    }

    private func applyRuntimeStatuses(runtime: String, worker: String, whisper: String, cleanup: String, isPreparing: Bool) {
        statusMenuController?.setRuntimeStatus(runtime)
        statusMenuController?.setWorkerStatus(worker)
        statusMenuController?.setWhisperModelStatus(whisper)
        statusMenuController?.setCleanupModelStatus(cleanup)
        settingsWindowController?.setRuntimeStatus(runtime)
        settingsWindowController?.setWorkerStatus(worker)
        settingsWindowController?.setWhisperModelStatus(whisper)
        settingsWindowController?.setCleanupModelStatus(cleanup)
        settingsWindowController?.setRuntimePreparationInProgress(isPreparing)
    }

    private func applyWorkerStatus(_ status: String) {
        guard currentConfig?.localRuntimeRequirements.needsWorker == true else {
            statusMenuController?.setWorkerStatus("Not Used")
            settingsWindowController?.setWorkerStatus("Not Used")
            return
        }

        statusMenuController?.setWorkerStatus(status)
        settingsWindowController?.setWorkerStatus(status)
    }

    private func showSettingsWindow() {
        guard let currentConfig else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        ensureSettingsWindowController()
        settingsWindowController?.show(with: currentConfig, hasGroqAPIKey: hasStoredGroqAPIKey())
    }

    private func prepareRuntimeIfNeeded() {
        guard let config = currentConfig else {
            return
        }

        let requirements = config.localRuntimeRequirements
        guard requirements.needsPreparation else {
            refreshRuntimeStatus(using: config)
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
                        runtime: requirements.needsBaseRuntime ? "Preparing" : "Not Needed",
                        worker: requirements.needsWorker ? "Pending" : "Not Used",
                        whisper: requirements.needsWhisperModel ? "Downloading" : whisperStatusText(for: config, snapshot: nil),
                        cleanup: requirements.needsCleanupModel ? "Pending Download" : cleanupStatusText(for: config, snapshot: nil),
                        isPreparing: true
                    )
                }
                if requirements.needsBaseRuntime {
                    try await runtimeBootstrapper.ensureBaseRuntimeReady()
                }

                if requirements.needsWhisperModel {
                    try await runtimeBootstrapper.ensureWhisperModelReady(config.resolvedTranscription.resolvedModel)
                }

                if requirements.needsCleanupModel {
                    await MainActor.run {
                        applyRuntimeStatuses(
                            runtime: "Ready",
                            worker: requirements.needsWorker ? "Pending" : "Not Used",
                            whisper: whisperStatusText(for: config, snapshot: nil, forceLocalReady: true),
                            cleanup: "Downloading",
                            isPreparing: true
                        )
                    }
                    try await runtimeBootstrapper.ensureCleanupModelReady(config.resolvedCleanup.resolvedModel)
                }

                if requirements.needsWorker {
                    await MainActor.run {
                        applyWorkerStatus("Warming")
                    }
                    try await inferenceWorker.prepare(for: config)
                }

                let snapshot = await runtimeBootstrapper.snapshot(for: config)

                await MainActor.run {
                    applyRuntimeSnapshot(snapshot, for: config, isPreparing: false)
                    if requirements.needsWorker {
                        applyWorkerStatus("Ready")
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
                        runtime: requirements.needsBaseRuntime ? "Error" : "Not Needed",
                        worker: requirements.needsWorker ? "Error" : "Not Used",
                        whisper: requirements.needsWhisperModel ? "Retry Needed" : whisperStatusText(for: config, snapshot: nil),
                        cleanup: requirements.needsCleanupModel ? "Retry Needed" : cleanupStatusText(for: config, snapshot: nil),
                        isPreparing: false
                    )
                    presentRuntimeAlert(message: error.localizedDescription)
                }
            }
        }
    }

    private func applyRuntimeSnapshot(_ snapshot: RuntimeSnapshot, for config: AppConfig, isPreparing: Bool) {
        applyRuntimeStatuses(
            runtime: runtimeStatusText(for: config, snapshot: snapshot),
            worker: workerStatusText(for: config, snapshot: snapshot),
            whisper: whisperStatusText(for: config, snapshot: snapshot),
            cleanup: cleanupStatusText(for: config, snapshot: snapshot),
            isPreparing: isPreparing
        )
    }

    private func runtimeStatusText(for config: AppConfig, snapshot: RuntimeSnapshot?) -> String {
        guard config.localRuntimeRequirements.needsBaseRuntime else {
            return "Not Needed"
        }

        guard let snapshot else {
            return "Needs Setup"
        }

        return snapshot.baseRuntimeReady ? "Ready" : "Needs Setup"
    }

    private func workerStatusText(for config: AppConfig, snapshot: RuntimeSnapshot?) -> String {
        guard config.localRuntimeRequirements.needsWorker else {
            return "Not Used"
        }

        guard let snapshot else {
            return "Pending"
        }

        return snapshot.baseRuntimeReady ? "Pending" : "Needs Runtime"
    }

    private func whisperStatusText(for config: AppConfig, snapshot: RuntimeSnapshot?, forceLocalReady: Bool = false) -> String {
        let transcription = config.resolvedTranscription

        if transcription.usesLegacyCommand {
            return "Custom Command"
        }

        if transcription.resolvedProvider == .groq {
            return "Remote (Groq)"
        }

        if forceLocalReady {
            return "Ready"
        }

        guard let snapshot else {
            return "Pending Download"
        }

        return snapshot.whisperModelReady ? "Ready" : "Pending Download"
    }

    private func cleanupStatusText(for config: AppConfig, snapshot: RuntimeSnapshot?) -> String {
        let cleanup = config.resolvedCleanup

        if !config.cleanupEnabled {
            if cleanup.usesLegacyEndpoint {
                return "Optional (Custom Endpoint)"
            }

            if cleanup.resolvedProvider == .groq {
                return "Optional (Groq)"
            }

            guard let snapshot else {
                return "Optional"
            }

            return snapshot.cleanupModelReady ? "Ready (Optional)" : "Optional"
        }

        if cleanup.usesLegacyEndpoint {
            return "Custom Endpoint"
        }

        if cleanup.resolvedProvider == .groq {
            return "Remote (Groq)"
        }

        guard let snapshot else {
            return "Pending Download"
        }

        return snapshot.cleanupModelReady ? "Ready" : "Pending Download"
    }

    private func presentFirstLaunchAlert(configPath: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "VoicePower is setting itself up"
        alert.informativeText = """
        VoicePower runs as a menu bar app. It has already created a default config at \(configPath).

        If local transcription, local cleanup, or simplified-Chinese normalization are enabled, VoicePower will prepare the local runtime and any selected local models in the background. In a portable runtime build, the base runtime may already be bundled and only the models still need downloading.

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
            errorPrefix: "Failed to update Whisper model"
        )
    }

    private func setTranscriptionProvider(_ provider: InferenceProvider) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        persistUpdatedConfig(
            currentConfig.settingTranscriptionProvider(provider),
            to: currentConfigURL,
            errorPrefix: "Failed to update transcription provider"
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
            errorPrefix: "Failed to update cleanup model"
        )
    }

    private func setCleanupProvider(_ provider: InferenceProvider) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        persistUpdatedConfig(
            currentConfig.settingCleanupProvider(provider),
            to: currentConfigURL,
            errorPrefix: "Failed to update cleanup provider"
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
            errorPrefix: "Failed to update cleanup setting"
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
            errorPrefix: "Failed to update punctuation setting"
        )
    }

    private func setCleanupPunctuationStyle(_ style: CleanupPunctuationStyle) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        persistUpdatedConfig(
            currentConfig.settingCleanupPunctuationStyle(style),
            to: currentConfigURL,
            errorPrefix: "Failed to update punctuation style"
        )
    }

    private func setCleanupPromptProfiles(_ promptProfiles: [CleanupPromptProfile], selectedPromptProfileID: String) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        do {
            let validatedProfiles = try validateCleanupPromptProfiles(
                promptProfiles,
                selectedPromptProfileID: selectedPromptProfileID
            )
            persistUpdatedConfig(
                currentConfig.settingCleanupPromptProfiles(validatedProfiles, selectedPromptProfileID: selectedPromptProfileID),
                to: currentConfigURL,
                errorPrefix: "Failed to update cleanup prompts"
            )
        } catch {
            presentRuntimeAlert(message: "Failed to update cleanup prompts: \(error.localizedDescription)")
        }
    }

    private func setSaveAudioEnabled(_ enabled: Bool) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        persistUpdatedConfig(
            currentConfig.settingSaveAudioFilesEnabled(enabled),
            to: currentConfigURL,
            errorPrefix: "Failed to update save-audio setting"
        )
    }

    private func setReviewBeforePasteEnabled(_ enabled: Bool) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        persistUpdatedConfig(
            currentConfig.settingReviewBeforePasteEnabled(enabled),
            to: currentConfigURL,
            errorPrefix: "Failed to update review-before-paste setting"
        )
    }

    private func setHoldToTalkEnabled(_ enabled: Bool) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        persistUpdatedConfig(
            currentConfig.settingHoldToTalkEnabled(enabled),
            to: currentConfigURL,
            errorPrefix: "Failed to update hold-to-talk setting"
        )
    }

    private func setHoldToTalkDelayMilliseconds(_ milliseconds: Int) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        persistUpdatedConfig(
            currentConfig.settingHoldToTalkActivationDelayMilliseconds(milliseconds),
            to: currentConfigURL,
            errorPrefix: "Failed to update hold-to-talk delay"
        )
    }

    private func setVocabulary(enabled: Bool, rawText: String) {
        guard let currentConfig, let currentConfigURL else {
            presentRuntimeAlert(message: "Config is not loaded yet")
            return
        }

        do {
            let entries = try parseVocabularyEntries(from: rawText)
            let updatedVocabulary = currentConfig.resolvedVocabulary
                .withEnabled(enabled)
                .withEntries(entries)

            persistUpdatedConfig(
                currentConfig.settingVocabulary(updatedVocabulary),
                to: currentConfigURL,
                errorPrefix: "Failed to update vocabulary"
            )
        } catch {
            presentRuntimeAlert(message: "Failed to update vocabulary: \(error.localizedDescription)")
        }
    }

    private func saveGroqAPIKey(_ apiKey: String) {
        do {
            try groqAPIKeyStore.save(apiKey)
            settingsWindowController?.setGroqAPIKeySaved(hasStoredGroqAPIKey())
        } catch {
            presentRuntimeAlert(message: "Failed to save Groq API key: \(error.localizedDescription)")
        }
    }

    private func clearGroqAPIKey() {
        do {
            try groqAPIKeyStore.clear()
            settingsWindowController?.setGroqAPIKeySaved(false)
        } catch {
            presentRuntimeAlert(message: "Failed to clear Groq API key: \(error.localizedDescription)")
        }
    }

    private func parseVocabularyEntries(from rawText: String) throws -> [VocabularyEntry] {
        let lines = rawText.components(separatedBy: .newlines)
        var entries: [VocabularyEntry] = []

        for (index, originalLine) in lines.enumerated() {
            let line = originalLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else {
                throw VoicePowerError.invalidConfig(reason:
                    "Vocabulary line \(index + 1) must use the format: Target => alias one | alias two"
                )
            }

            let target = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let aliases = parts[1]
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !target.isEmpty else {
                throw VoicePowerError.invalidConfig(reason: "Vocabulary line \(index + 1) is missing the target phrase")
            }

            guard !aliases.isEmpty else {
                throw VoicePowerError.invalidConfig(reason: "Vocabulary line \(index + 1) needs at least one alias")
            }

            entries.append(
                VocabularyEntry(
                    target: target,
                    aliases: aliases,
                    caseSensitive: false,
                    matchWholeWords: nil
                )
            )
        }

        return entries
    }

    private func validateCleanupPromptProfiles(
        _ promptProfiles: [CleanupPromptProfile],
        selectedPromptProfileID: String
    ) throws -> [CleanupPromptProfile] {
        let selectedID = selectedPromptProfileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedID.isEmpty else {
            throw VoicePowerError.invalidConfig(reason: "A cleanup prompt preset must be selected")
        }

        var seenIDs = Set<String>()
        var normalizedProfiles: [CleanupPromptProfile] = []

        for profile in promptProfiles {
            let id = profile.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let systemPrompt = profile.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let userPromptTemplate = profile.userPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !id.isEmpty else {
                throw VoicePowerError.invalidConfig(reason: "Cleanup prompt preset IDs cannot be empty")
            }
            guard !seenIDs.contains(id) else {
                throw VoicePowerError.invalidConfig(reason: "Cleanup prompt preset IDs must be unique")
            }
            guard !name.isEmpty else {
                throw VoicePowerError.invalidConfig(reason: "Cleanup prompt preset names cannot be empty")
            }
            guard !systemPrompt.isEmpty else {
                throw VoicePowerError.invalidConfig(reason: "System prompt cannot be empty")
            }
            guard !userPromptTemplate.isEmpty else {
                throw VoicePowerError.invalidConfig(reason: "User prompt template cannot be empty")
            }
            guard userPromptTemplate.contains("{{text}}") else {
                throw VoicePowerError.invalidConfig(reason: "User prompt template must contain {{text}}")
            }

            seenIDs.insert(id)
            normalizedProfiles.append(
                CleanupPromptProfile(
                    id: id,
                    name: name,
                    systemPrompt: systemPrompt,
                    userPromptTemplate: userPromptTemplate,
                    isBuiltIn: profile.resolvedIsBuiltIn
                )
            )
        }

        guard normalizedProfiles.contains(where: { $0.id == selectedID }) else {
            throw VoicePowerError.invalidConfig(reason: "Selected cleanup prompt preset was not found")
        }

        return normalizedProfiles
    }

    private func persistUpdatedConfig(_ updatedConfig: AppConfig, to url: URL, errorPrefix: String) {
        do {
            try AppConfigLoader.save(updatedConfig, to: url)
            currentConfig = updatedConfig
            configureApplication()
        } catch {
            presentRuntimeAlert(message: "\(errorPrefix): \(error.localizedDescription)")
        }
    }

    private func hasStoredGroqAPIKey() -> Bool {
        do {
            return try groqAPIKeyStore.load() != nil
        } catch {
            return false
        }
    }
}
