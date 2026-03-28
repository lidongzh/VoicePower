import AppKit

struct ModelOption: Equatable {
    let id: String
    let title: String
}

@MainActor
private final class VocabularyMappingRow {
    let containerView = NSStackView()
    let targetField = NSTextField()
    let aliasesField = NSTextField()
    let removeButton = NSButton(title: "Remove", target: nil, action: nil)

    init(target: String, aliases: String) {
        targetField.translatesAutoresizingMaskIntoConstraints = false
        targetField.stringValue = target
        targetField.placeholderString = "Target phrase"
        targetField.widthAnchor.constraint(equalToConstant: 150).isActive = true

        aliasesField.translatesAutoresizingMaskIntoConstraints = false
        aliasesField.stringValue = aliases
        aliasesField.placeholderString = "alias one | alias two"
        aliasesField.widthAnchor.constraint(equalToConstant: 260).isActive = true

        removeButton.bezelStyle = .rounded

        containerView.orientation = .horizontal
        containerView.alignment = .centerY
        containerView.spacing = 8
        containerView.addArrangedSubview(targetField)
        containerView.addArrangedSubview(aliasesField)
        containerView.addArrangedSubview(removeButton)
    }
}

@MainActor
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}

enum VoicePowerModelCatalog {
    static let localWhisperOptions: [ModelOption] = [
        ModelOption(id: "mlx-community/whisper-large-v3-turbo", title: "Whisper Large v3 Turbo"),
        ModelOption(id: "mlx-community/whisper-medium-mlx", title: "Whisper Medium"),
        ModelOption(id: "mlx-community/whisper-small-mlx", title: "Whisper Small"),
        ModelOption(id: "mlx-community/whisper-tiny-mlx", title: "Whisper Tiny"),
    ]

    static let groqWhisperOptions: [ModelOption] = [
        ModelOption(id: "whisper-large-v3-turbo", title: "Whisper Large v3 Turbo"),
        ModelOption(id: "whisper-large-v3", title: "Whisper Large v3"),
    ]

    static let localCleanupOptions: [ModelOption] = [
        ModelOption(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", title: "Qwen2.5 1.5B Instruct 4-bit"),
        ModelOption(id: "mlx-community/Qwen2.5-3B-Instruct-4bit", title: "Qwen2.5 3B Instruct 4-bit"),
        ModelOption(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit", title: "Qwen3 4B Instruct 4-bit"),
        ModelOption(id: "mlx-community/Qwen2-1.5B-Instruct-4bit", title: "Qwen2 1.5B Instruct 4-bit"),
    ]

    static let groqCleanupOptions: [ModelOption] = [
        ModelOption(id: "llama-3.1-8b-instant", title: "Llama 3.1 8B Instant"),
        ModelOption(id: "qwen/qwen3-32b", title: "Qwen3 32B"),
        ModelOption(id: "llama-3.3-70b-versatile", title: "Llama 3.3 70B Versatile"),
    ]

    static func whisperOptions(for provider: InferenceProvider) -> [ModelOption] {
        switch provider {
        case .local:
            return localWhisperOptions
        case .groq:
            return groqWhisperOptions
        }
    }

    static func cleanupOptions(for provider: InferenceProvider) -> [ModelOption] {
        switch provider {
        case .local:
            return localCleanupOptions
        case .groq:
            return groqCleanupOptions
        }
    }

    static func optionsIncludingCurrent(_ currentID: String, from base: [ModelOption]) -> [ModelOption] {
        if base.contains(where: { $0.id == currentID }) {
            return base
        }

        return base + [ModelOption(id: currentID, title: "Custom: \(currentID)")]
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    var onTranscriptionProviderChange: ((InferenceProvider) -> Void)?
    var onWhisperModelChange: ((String) -> Void)?
    var onCleanupProviderChange: ((InferenceProvider) -> Void)?
    var onCleanupModelChange: ((String) -> Void)?
    var onCleanupEnabledChange: ((Bool) -> Void)?
    var onAutoPunctuationChange: ((Bool) -> Void)?
    var onSaveAudioChange: ((Bool) -> Void)?
    var onVocabularySave: ((Bool, String) -> Void)?
    var onPrepareRuntime: (() -> Void)?
    var onSaveGroqAPIKey: ((String) -> Void)?
    var onClearGroqAPIKey: (() -> Void)?

    private let transcriptionProviderPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let whisperModelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let whisperCustomModelField = NSTextField()
    private let whisperCustomModelButton = NSButton(title: "Use Custom", target: nil, action: nil)
    private let cleanupProviderPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cleanupModelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cleanupCustomModelField = NSTextField()
    private let cleanupCustomModelButton = NSButton(title: "Use Custom", target: nil, action: nil)
    private let groqAPIKeyField = NSTextField()
    private let pasteGroqAPIKeyButton = NSButton(title: "Paste", target: nil, action: nil)
    private let saveGroqAPIKeyButton = NSButton(title: "Save Groq API Key", target: nil, action: nil)
    private let clearGroqAPIKeyButton = NSButton(title: "Clear Groq API Key", target: nil, action: nil)
    private let cleanupEnabledCheckbox = NSButton(checkboxWithTitle: "Enable cleanup", target: nil, action: nil)
    private let autoPunctuationCheckbox = NSButton(checkboxWithTitle: "Auto punctuation", target: nil, action: nil)
    private let saveAudioCheckbox = NSButton(checkboxWithTitle: "Save recorded audio files", target: nil, action: nil)
    private let vocabularyEnabledCheckbox = NSButton(checkboxWithTitle: "Enable vocabulary corrections", target: nil, action: nil)
    private let runtimeStatusLabel = NSTextField(labelWithString: "Runtime: Pending")
    private let workerStatusLabel = NSTextField(labelWithString: "Worker: Pending")
    private let whisperStatusLabel = NSTextField(labelWithString: "Whisper model: Pending Download")
    private let cleanupStatusLabel = NSTextField(labelWithString: "Cleanup model: Optional")
    private let groqAPIKeyStatusLabel = NSTextField(labelWithString: "Groq API key: Not Saved")
    private let setupNoteLabel = NSTextField(labelWithString: "Changing providers and models updates the app config immediately. Use “Download Selected Local Models” to prefetch only the local runtime and models still in use.")
    private let groqNoteLabel = NSTextField(labelWithString: "When Groq is selected, recorded audio or cleanup text is sent to Groq for inference. The Groq API key is stored in this Mac’s Keychain, not in the config file.")
    private let vocabularyNoteLabel = NSTextField(labelWithString: "Vocabulary entries stay on this Mac only. Add one mapping per row. Use | between aliases.")
    private let addVocabularyButton = NSButton(title: "Add Mapping", target: nil, action: nil)
    private let downloadButton = NSButton(title: "Download Selected Local Models", target: nil, action: nil)
    private let saveVocabularyButton = NSButton(title: "Save Vocabulary", target: nil, action: nil)
    private let downloadProgressIndicator = NSProgressIndicator()
    private let vocabularyRowsStack = NSStackView()

    private var whisperOptions: [ModelOption] = VoicePowerModelCatalog.localWhisperOptions
    private var cleanupOptions: [ModelOption] = VoicePowerModelCatalog.localCleanupOptions
    private var vocabularyRows: [VocabularyMappingRow] = []
    private var currentTranscriptionProvider: InferenceProvider = .local
    private var currentCleanupProvider: InferenceProvider = .local
    private var runtimePreparationNeeded = true
    private var isPreparingRuntime = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoicePower Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 720)
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(with config: AppConfig, hasGroqAPIKey: Bool) {
        apply(config: config, hasGroqAPIKey: hasGroqAPIKey)
        window?.center()
        showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func apply(config: AppConfig, hasGroqAPIKey: Bool) {
        currentTranscriptionProvider = config.resolvedTranscription.resolvedProvider
        currentCleanupProvider = config.resolvedCleanup.resolvedProvider
        runtimePreparationNeeded = config.localRuntimeRequirements.needsPreparation

        let transcriptionModel = config.resolvedTranscription.resolvedModel
        let cleanupModel = config.resolvedCleanup.resolvedModel

        repopulateProviderPopup(transcriptionProviderPopup, selected: currentTranscriptionProvider)
        repopulateProviderPopup(cleanupProviderPopup, selected: currentCleanupProvider)

        whisperOptions = VoicePowerModelCatalog.optionsIncludingCurrent(
            transcriptionModel,
            from: VoicePowerModelCatalog.whisperOptions(for: currentTranscriptionProvider)
        )
        cleanupOptions = VoicePowerModelCatalog.optionsIncludingCurrent(
            cleanupModel,
            from: VoicePowerModelCatalog.cleanupOptions(for: currentCleanupProvider)
        )

        repopulate(whisperModelPopup, with: whisperOptions, selectedID: transcriptionModel)
        repopulate(cleanupModelPopup, with: cleanupOptions, selectedID: cleanupModel)
        whisperCustomModelField.stringValue = isCustomModel(
            transcriptionModel,
            in: VoicePowerModelCatalog.whisperOptions(for: currentTranscriptionProvider)
        ) ? transcriptionModel : ""
        cleanupCustomModelField.stringValue = isCustomModel(
            cleanupModel,
            in: VoicePowerModelCatalog.cleanupOptions(for: currentCleanupProvider)
        ) ? cleanupModel : ""
        cleanupEnabledCheckbox.state = config.cleanupEnabled ? .on : .off
        autoPunctuationCheckbox.state = config.resolvedCleanup.autoPunctuationEnabled ? .on : .off
        saveAudioCheckbox.state = config.saveAudioFilesEnabled ? .on : .off
        vocabularyEnabledCheckbox.state = config.resolvedVocabulary.enabled ? .on : .off
        setVocabularyRows(from: config.resolvedVocabulary.entries)
        setGroqAPIKeySaved(hasGroqAPIKey)
        updateCustomModelPlaceholders()
        updateRuntimePreparationControlState()
    }

    func setRuntimeStatus(_ value: String) {
        runtimeStatusLabel.stringValue = "Runtime: \(value)"
    }

    func setWhisperModelStatus(_ value: String) {
        whisperStatusLabel.stringValue = "Whisper model: \(value)"
    }

    func setWorkerStatus(_ value: String) {
        workerStatusLabel.stringValue = "Worker: \(value)"
    }

    func setCleanupModelStatus(_ value: String) {
        cleanupStatusLabel.stringValue = "Cleanup model: \(value)"
    }

    func setRuntimePreparationInProgress(_ isPreparing: Bool) {
        isPreparingRuntime = isPreparing
        if isPreparing {
            downloadProgressIndicator.startAnimation(nil)
        } else {
            downloadProgressIndicator.stopAnimation(nil)
        }
        updateRuntimePreparationControlState()
    }

    func setGroqAPIKeySaved(_ saved: Bool) {
        groqAPIKeyStatusLabel.stringValue = "Groq API key: \(saved ? "Saved" : "Not Saved")"
        if saved {
            groqAPIKeyField.stringValue = ""
        }
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        setupNoteLabel.lineBreakMode = .byWordWrapping
        setupNoteLabel.maximumNumberOfLines = 0
        groqNoteLabel.lineBreakMode = .byWordWrapping
        groqNoteLabel.maximumNumberOfLines = 0
        vocabularyNoteLabel.lineBreakMode = .byWordWrapping
        vocabularyNoteLabel.maximumNumberOfLines = 0
        setupNoteLabel.textColor = .secondaryLabelColor
        groqNoteLabel.textColor = .secondaryLabelColor
        vocabularyNoteLabel.textColor = .secondaryLabelColor
        runtimeStatusLabel.textColor = .secondaryLabelColor
        workerStatusLabel.textColor = .secondaryLabelColor
        whisperStatusLabel.textColor = .secondaryLabelColor
        cleanupStatusLabel.textColor = .secondaryLabelColor
        groqAPIKeyStatusLabel.textColor = .secondaryLabelColor
        downloadProgressIndicator.style = .spinning
        downloadProgressIndicator.controlSize = .small
        downloadProgressIndicator.isDisplayedWhenStopped = false
        vocabularyRowsStack.orientation = .vertical
        vocabularyRowsStack.alignment = .leading
        vocabularyRowsStack.spacing = 8
        vocabularyRowsStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        setVocabularyRows(from: [])

        configureTextField(whisperCustomModelField)
        configureTextField(cleanupCustomModelField)
        configureTextField(groqAPIKeyField)

        repopulateProviderPopup(transcriptionProviderPopup, selected: .local)
        repopulateProviderPopup(cleanupProviderPopup, selected: .local)
        transcriptionProviderPopup.target = self
        transcriptionProviderPopup.action = #selector(handleTranscriptionProviderChanged)
        whisperModelPopup.target = self
        whisperModelPopup.action = #selector(handleWhisperModelChanged)
        whisperCustomModelButton.target = self
        whisperCustomModelButton.action = #selector(handleUseCustomWhisperModel)
        cleanupProviderPopup.target = self
        cleanupProviderPopup.action = #selector(handleCleanupProviderChanged)
        cleanupModelPopup.target = self
        cleanupModelPopup.action = #selector(handleCleanupModelChanged)
        cleanupCustomModelButton.target = self
        cleanupCustomModelButton.action = #selector(handleUseCustomCleanupModel)

        cleanupEnabledCheckbox.target = self
        cleanupEnabledCheckbox.action = #selector(handleCleanupEnabledChanged)
        autoPunctuationCheckbox.target = self
        autoPunctuationCheckbox.action = #selector(handleAutoPunctuationChanged)
        saveAudioCheckbox.target = self
        saveAudioCheckbox.action = #selector(handleSaveAudioChanged)
        addVocabularyButton.target = self
        addVocabularyButton.action = #selector(handleAddVocabularyRow)
        saveVocabularyButton.target = self
        saveVocabularyButton.action = #selector(handleSaveVocabulary)
        downloadButton.target = self
        downloadButton.action = #selector(handlePrepareRuntime)
        saveGroqAPIKeyButton.target = self
        saveGroqAPIKeyButton.action = #selector(handleSaveGroqAPIKey)
        pasteGroqAPIKeyButton.target = self
        pasteGroqAPIKeyButton.action = #selector(handlePasteGroqAPIKey)
        clearGroqAPIKeyButton.target = self
        clearGroqAPIKeyButton.action = #selector(handleClearGroqAPIKey)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(runtimeStatusLabel)
        stack.addArrangedSubview(workerStatusLabel)
        stack.addArrangedSubview(whisperStatusLabel)
        stack.addArrangedSubview(cleanupStatusLabel)
        stack.addArrangedSubview(makeLabeledRow(label: "Whisper provider", control: transcriptionProviderPopup))
        stack.addArrangedSubview(makeLabeledRow(label: "Whisper model", control: whisperModelPopup))
        stack.addArrangedSubview(makeCustomModelRow(field: whisperCustomModelField, button: whisperCustomModelButton))
        stack.addArrangedSubview(makeLabeledRow(label: "Cleanup provider", control: cleanupProviderPopup))
        stack.addArrangedSubview(makeLabeledRow(label: "Cleanup model", control: cleanupModelPopup))
        stack.addArrangedSubview(makeCustomModelRow(field: cleanupCustomModelField, button: cleanupCustomModelButton))
        stack.addArrangedSubview(cleanupEnabledCheckbox)
        stack.addArrangedSubview(autoPunctuationCheckbox)
        stack.addArrangedSubview(saveAudioCheckbox)
        stack.addArrangedSubview(setupNoteLabel)
        stack.addArrangedSubview(makeDownloadRow())
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(groqAPIKeyStatusLabel)
        stack.addArrangedSubview(makeLabeledRow(label: "Groq API key", control: makeInlineFieldRow(field: groqAPIKeyField, button: pasteGroqAPIKeyButton)))
        stack.addArrangedSubview(makeGroqButtonRow())
        stack.addArrangedSubview(groqNoteLabel)
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(vocabularyEnabledCheckbox)
        stack.addArrangedSubview(vocabularyNoteLabel)
        stack.addArrangedSubview(makeVocabularyEditor())
        stack.addArrangedSubview(makeVocabularyButtonRow())

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let documentView = FlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        documentView.addSubview(stack)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -20),
            transcriptionProviderPopup.widthAnchor.constraint(equalToConstant: 180),
            whisperModelPopup.widthAnchor.constraint(equalToConstant: 290),
            whisperCustomModelField.widthAnchor.constraint(equalToConstant: 320),
            cleanupProviderPopup.widthAnchor.constraint(equalToConstant: 180),
            cleanupModelPopup.widthAnchor.constraint(equalToConstant: 290),
            cleanupCustomModelField.widthAnchor.constraint(equalToConstant: 320),
            groqAPIKeyField.widthAnchor.constraint(equalToConstant: 320),
        ])

        updateCustomModelPlaceholders()
        updateRuntimePreparationControlState()
    }

    private func makeLabeledRow(label: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func makeCustomModelRow(field: NSTextField, button: NSButton) -> NSView {
        let row = NSStackView(views: [field, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeInlineFieldRow(field: NSTextField, button: NSButton) -> NSView {
        let row = NSStackView(views: [field, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeDownloadRow() -> NSView {
        let row = NSStackView(views: [downloadButton, downloadProgressIndicator])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeGroqButtonRow() -> NSView {
        let row = NSStackView(views: [saveGroqAPIKeyButton, clearGroqAPIKeyButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeVocabularyEditor() -> NSView {
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = vocabularyRowsStack
        scrollView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        return scrollView
    }

    private func makeVocabularyButtonRow() -> NSView {
        let row = NSStackView(views: [addVocabularyButton, saveVocabularyButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    private func configureTextField(_ field: NSTextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    private func repopulateProviderPopup(_ popup: NSPopUpButton, selected provider: InferenceProvider) {
        popup.removeAllItems()
        popup.addItems(withTitles: InferenceProvider.allCases.map(\.title))
        popup.selectItem(at: InferenceProvider.allCases.firstIndex(of: provider) ?? 0)
    }

    private func repopulate(_ popup: NSPopUpButton, with options: [ModelOption], selectedID: String) {
        popup.removeAllItems()
        popup.addItems(withTitles: options.map(\.title))
        if let index = options.firstIndex(where: { $0.id == selectedID }) {
            popup.selectItem(at: index)
        }
    }

    private func isCustomModel(_ modelID: String, in options: [ModelOption]) -> Bool {
        !options.contains(where: { $0.id == modelID })
    }

    private func updateWhisperOptions(selectedModel: String) {
        let baseOptions = VoicePowerModelCatalog.whisperOptions(for: currentTranscriptionProvider)
        whisperOptions = VoicePowerModelCatalog.optionsIncludingCurrent(selectedModel, from: baseOptions)
        repopulate(whisperModelPopup, with: whisperOptions, selectedID: selectedModel)
        whisperCustomModelField.stringValue = isCustomModel(selectedModel, in: baseOptions) ? selectedModel : ""
        updateCustomModelPlaceholders()
    }

    private func updateCleanupOptions(selectedModel: String) {
        let baseOptions = VoicePowerModelCatalog.cleanupOptions(for: currentCleanupProvider)
        cleanupOptions = VoicePowerModelCatalog.optionsIncludingCurrent(selectedModel, from: baseOptions)
        repopulate(cleanupModelPopup, with: cleanupOptions, selectedID: selectedModel)
        cleanupCustomModelField.stringValue = isCustomModel(selectedModel, in: baseOptions) ? selectedModel : ""
        updateCustomModelPlaceholders()
    }

    private func updateCustomModelPlaceholders() {
        whisperCustomModelField.placeholderString = currentTranscriptionProvider == .groq
            ? "Custom Groq Whisper model ID"
            : "Custom local Whisper model ID"
        cleanupCustomModelField.placeholderString = currentCleanupProvider == .groq
            ? "Custom Groq cleanup model ID"
            : "Custom local cleanup model ID"
        groqAPIKeyField.placeholderString = "gsk_..."
    }

    private func updateRuntimePreparationControlState() {
        downloadButton.isEnabled = runtimePreparationNeeded && !isPreparingRuntime
        downloadButton.title = runtimePreparationNeeded ? "Download Selected Local Models" : "No Local Runtime Needed"
    }

    private func setVocabularyRows(from entries: [VocabularyEntry]) {
        vocabularyRows.forEach { row in
            vocabularyRowsStack.removeArrangedSubview(row.containerView)
            row.containerView.removeFromSuperview()
        }
        vocabularyRows.removeAll()

        if entries.isEmpty {
            appendVocabularyRow()
        } else {
            entries.forEach { entry in
                appendVocabularyRow(
                    target: entry.resolvedTarget,
                    aliases: entry.resolvedAliases.joined(separator: " | ")
                )
            }
        }

        updateVocabularyRowsLayout()
    }

    private func appendVocabularyRow(target: String = "", aliases: String = "") {
        let row = VocabularyMappingRow(target: target, aliases: aliases)
        row.removeButton.target = self
        row.removeButton.action = #selector(handleRemoveVocabularyRow(_:))
        vocabularyRows.append(row)
        vocabularyRowsStack.addArrangedSubview(row.containerView)
        updateVocabularyRowsLayout()
    }

    private func updateVocabularyRowsLayout() {
        let width: CGFloat = 580
        let height = max(vocabularyRowsStack.fittingSize.height, 1)
        vocabularyRowsStack.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    private func vocabularyRawText() -> String {
        vocabularyRows
            .compactMap { row in
                let target = row.targetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let aliases = row.aliasesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !target.isEmpty || !aliases.isEmpty else {
                    return nil
                }

                return "\(target) => \(aliases)"
            }
            .joined(separator: "\n")
    }

    @objc private func handleTranscriptionProviderChanged() {
        let index = transcriptionProviderPopup.indexOfSelectedItem
        guard InferenceProvider.allCases.indices.contains(index) else {
            return
        }

        let provider = InferenceProvider.allCases[index]
        currentTranscriptionProvider = provider
        updateWhisperOptions(selectedModel: TranscriptionConfig.defaultModel(for: provider))
        onTranscriptionProviderChange?(provider)
    }

    @objc private func handleWhisperModelChanged() {
        let index = whisperModelPopup.indexOfSelectedItem
        guard whisperOptions.indices.contains(index) else {
            return
        }

        onWhisperModelChange?(whisperOptions[index].id)
    }

    @objc private func handleUseCustomWhisperModel() {
        let customModel = whisperCustomModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !customModel.isEmpty else {
            return
        }

        onWhisperModelChange?(customModel)
    }

    @objc private func handleCleanupProviderChanged() {
        let index = cleanupProviderPopup.indexOfSelectedItem
        guard InferenceProvider.allCases.indices.contains(index) else {
            return
        }

        let provider = InferenceProvider.allCases[index]
        currentCleanupProvider = provider
        updateCleanupOptions(selectedModel: CleanupConfig.defaultModel(for: provider))
        onCleanupProviderChange?(provider)
    }

    @objc private func handleCleanupModelChanged() {
        let index = cleanupModelPopup.indexOfSelectedItem
        guard cleanupOptions.indices.contains(index) else {
            return
        }

        onCleanupModelChange?(cleanupOptions[index].id)
    }

    @objc private func handleUseCustomCleanupModel() {
        let customModel = cleanupCustomModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !customModel.isEmpty else {
            return
        }

        onCleanupModelChange?(customModel)
    }

    @objc private func handleCleanupEnabledChanged() {
        onCleanupEnabledChange?(cleanupEnabledCheckbox.state == .on)
    }

    @objc private func handleAutoPunctuationChanged() {
        onAutoPunctuationChange?(autoPunctuationCheckbox.state == .on)
    }

    @objc private func handleSaveAudioChanged() {
        onSaveAudioChange?(saveAudioCheckbox.state == .on)
    }

    @objc private func handleAddVocabularyRow() {
        appendVocabularyRow()
    }

    @objc private func handleRemoveVocabularyRow(_ sender: NSButton) {
        guard let index = vocabularyRows.firstIndex(where: { $0.removeButton === sender }) else {
            return
        }

        if vocabularyRows.count == 1 {
            vocabularyRows[index].targetField.stringValue = ""
            vocabularyRows[index].aliasesField.stringValue = ""
            return
        }

        let row = vocabularyRows.remove(at: index)
        vocabularyRowsStack.removeArrangedSubview(row.containerView)
        row.containerView.removeFromSuperview()
        updateVocabularyRowsLayout()
    }

    @objc private func handleSaveVocabulary() {
        onVocabularySave?(vocabularyEnabledCheckbox.state == .on, vocabularyRawText())
    }

    @objc private func handlePrepareRuntime() {
        onPrepareRuntime?()
    }

    @objc private func handleSaveGroqAPIKey() {
        onSaveGroqAPIKey?(groqAPIKeyField.stringValue)
    }

    @objc private func handlePasteGroqAPIKey() {
        guard let pasted = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !pasted.isEmpty else {
            return
        }

        groqAPIKeyField.stringValue = pasted
    }

    @objc private func handleClearGroqAPIKey() {
        groqAPIKeyField.stringValue = ""
        onClearGroqAPIKey?()
    }
}
