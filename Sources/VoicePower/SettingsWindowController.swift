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

enum VoicePowerModelCatalog {
    static let whisperOptions: [ModelOption] = [
        ModelOption(id: "mlx-community/whisper-large-v3-turbo", title: "Whisper Large v3 Turbo"),
        ModelOption(id: "mlx-community/whisper-medium-mlx", title: "Whisper Medium"),
        ModelOption(id: "mlx-community/whisper-small-mlx", title: "Whisper Small"),
        ModelOption(id: "mlx-community/whisper-tiny-mlx", title: "Whisper Tiny"),
    ]

    static let cleanupOptions: [ModelOption] = [
        ModelOption(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", title: "Qwen2.5 1.5B Instruct 4-bit"),
        ModelOption(id: "mlx-community/Qwen2.5-3B-Instruct-4bit", title: "Qwen2.5 3B Instruct 4-bit"),
        ModelOption(id: "mlx-community/Qwen3-4B-Instruct-2507-4bit", title: "Qwen3 4B Instruct 4-bit"),
        ModelOption(id: "mlx-community/Qwen2-1.5B-Instruct-4bit", title: "Qwen2 1.5B Instruct 4-bit"),
    ]

    static func optionsIncludingCurrent(_ currentID: String, from base: [ModelOption]) -> [ModelOption] {
        if base.contains(where: { $0.id == currentID }) {
            return base
        }

        return base + [ModelOption(id: currentID, title: "Custom: \(currentID)")]
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    var onWhisperModelChange: ((String) -> Void)?
    var onCleanupModelChange: ((String) -> Void)?
    var onCleanupEnabledChange: ((Bool) -> Void)?
    var onAutoPunctuationChange: ((Bool) -> Void)?
    var onSaveAudioChange: ((Bool) -> Void)?
    var onVocabularySave: ((Bool, String) -> Void)?
    var onPrepareRuntime: (() -> Void)?

    private let whisperModelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cleanupModelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cleanupEnabledCheckbox = NSButton(checkboxWithTitle: "Enable cleanup", target: nil, action: nil)
    private let autoPunctuationCheckbox = NSButton(checkboxWithTitle: "Auto punctuation", target: nil, action: nil)
    private let saveAudioCheckbox = NSButton(checkboxWithTitle: "Save recorded audio files", target: nil, action: nil)
    private let vocabularyEnabledCheckbox = NSButton(checkboxWithTitle: "Enable vocabulary corrections", target: nil, action: nil)
    private let runtimeStatusLabel = NSTextField(labelWithString: "Runtime: Pending")
    private let workerStatusLabel = NSTextField(labelWithString: "Worker: Pending")
    private let whisperStatusLabel = NSTextField(labelWithString: "Whisper model: Pending Download")
    private let cleanupStatusLabel = NSTextField(labelWithString: "Cleanup model: Optional")
    private let setupNoteLabel = NSTextField(labelWithString: "Changing models updates the app config immediately. Use “Download Selected Models” to prefetch the selected models.")
    private let vocabularyNoteLabel = NSTextField(labelWithString: "Vocabulary entries stay on this Mac only. Add one mapping per row. Use | between aliases.")
    private let addVocabularyButton = NSButton(title: "Add Mapping", target: nil, action: nil)
    private let downloadButton = NSButton(title: "Download Selected Models", target: nil, action: nil)
    private let saveVocabularyButton = NSButton(title: "Save Vocabulary", target: nil, action: nil)
    private let downloadProgressIndicator = NSProgressIndicator()
    private let vocabularyRowsStack = NSStackView()

    private var whisperOptions: [ModelOption] = VoicePowerModelCatalog.whisperOptions
    private var cleanupOptions: [ModelOption] = VoicePowerModelCatalog.cleanupOptions
    private var vocabularyRows: [VocabularyMappingRow] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoicePower Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(with config: AppConfig) {
        apply(config: config)
        window?.center()
        showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func apply(config: AppConfig) {
        let transcriptionModel = config.resolvedTranscription.resolvedModel
        let cleanupModel = config.resolvedCleanup.resolvedModel

        whisperOptions = VoicePowerModelCatalog.optionsIncludingCurrent(
            transcriptionModel,
            from: VoicePowerModelCatalog.whisperOptions
        )
        cleanupOptions = VoicePowerModelCatalog.optionsIncludingCurrent(
            cleanupModel,
            from: VoicePowerModelCatalog.cleanupOptions
        )

        repopulate(whisperModelPopup, with: whisperOptions, selectedID: transcriptionModel)
        repopulate(cleanupModelPopup, with: cleanupOptions, selectedID: cleanupModel)
        cleanupEnabledCheckbox.state = config.cleanupEnabled ? .on : .off
        autoPunctuationCheckbox.state = config.resolvedCleanup.autoPunctuationEnabled ? .on : .off
        saveAudioCheckbox.state = config.saveAudioFilesEnabled ? .on : .off
        vocabularyEnabledCheckbox.state = config.resolvedVocabulary.enabled ? .on : .off
        setVocabularyRows(from: config.resolvedVocabulary.entries)
        cleanupStatusLabel.stringValue = config.cleanupEnabled ? cleanupStatusLabel.stringValue : "Cleanup model: Optional"
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
        if isPreparing {
            downloadProgressIndicator.startAnimation(nil)
        } else {
            downloadProgressIndicator.stopAnimation(nil)
        }
        downloadButton.isEnabled = !isPreparing
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        setupNoteLabel.lineBreakMode = .byWordWrapping
        setupNoteLabel.maximumNumberOfLines = 0
        vocabularyNoteLabel.lineBreakMode = .byWordWrapping
        vocabularyNoteLabel.maximumNumberOfLines = 0
        setupNoteLabel.textColor = .secondaryLabelColor
        vocabularyNoteLabel.textColor = .secondaryLabelColor
        runtimeStatusLabel.textColor = .secondaryLabelColor
        workerStatusLabel.textColor = .secondaryLabelColor
        whisperStatusLabel.textColor = .secondaryLabelColor
        cleanupStatusLabel.textColor = .secondaryLabelColor
        downloadProgressIndicator.style = .spinning
        downloadProgressIndicator.controlSize = .small
        downloadProgressIndicator.isDisplayedWhenStopped = false
        vocabularyRowsStack.orientation = .vertical
        vocabularyRowsStack.alignment = .leading
        vocabularyRowsStack.spacing = 8
        vocabularyRowsStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        setVocabularyRows(from: [])

        whisperModelPopup.target = self
        whisperModelPopup.action = #selector(handleWhisperModelChanged)
        cleanupModelPopup.target = self
        cleanupModelPopup.action = #selector(handleCleanupModelChanged)

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

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(runtimeStatusLabel)
        stack.addArrangedSubview(workerStatusLabel)
        stack.addArrangedSubview(whisperStatusLabel)
        stack.addArrangedSubview(cleanupStatusLabel)
        stack.addArrangedSubview(makeLabeledRow(label: "Whisper model", control: whisperModelPopup))
        stack.addArrangedSubview(makeLabeledRow(label: "Cleanup model", control: cleanupModelPopup))
        stack.addArrangedSubview(cleanupEnabledCheckbox)
        stack.addArrangedSubview(autoPunctuationCheckbox)
        stack.addArrangedSubview(saveAudioCheckbox)
        stack.addArrangedSubview(setupNoteLabel)
        stack.addArrangedSubview(makeDownloadRow())
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(vocabularyEnabledCheckbox)
        stack.addArrangedSubview(vocabularyNoteLabel)
        stack.addArrangedSubview(makeVocabularyEditor())
        stack.addArrangedSubview(makeVocabularyButtonRow())

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            whisperModelPopup.widthAnchor.constraint(equalToConstant: 290),
            cleanupModelPopup.widthAnchor.constraint(equalToConstant: 290),
        ])
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

    private func makeDownloadRow() -> NSView {
        let row = NSStackView(views: [downloadButton, downloadProgressIndicator])
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

    private func repopulate(_ popup: NSPopUpButton, with options: [ModelOption], selectedID: String) {
        popup.removeAllItems()
        popup.addItems(withTitles: options.map(\.title))
        if let index = options.firstIndex(where: { $0.id == selectedID }) {
            popup.selectItem(at: index)
        }
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
        let width: CGFloat = 500
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

    @objc private func handleWhisperModelChanged() {
        let index = whisperModelPopup.indexOfSelectedItem
        guard whisperOptions.indices.contains(index) else {
            return
        }

        onWhisperModelChange?(whisperOptions[index].id)
    }

    @objc private func handleCleanupModelChanged() {
        let index = cleanupModelPopup.indexOfSelectedItem
        guard cleanupOptions.indices.contains(index) else {
            return
        }

        onCleanupModelChange?(cleanupOptions[index].id)
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
}
