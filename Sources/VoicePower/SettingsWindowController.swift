import AppKit

struct ModelOption: Equatable {
    let id: String
    let title: String
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
    var onPrepareRuntime: (() -> Void)?

    private let whisperModelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cleanupModelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cleanupEnabledCheckbox = NSButton(checkboxWithTitle: "Enable cleanup", target: nil, action: nil)
    private let autoPunctuationCheckbox = NSButton(checkboxWithTitle: "Auto punctuation", target: nil, action: nil)
    private let saveAudioCheckbox = NSButton(checkboxWithTitle: "Save recorded audio files", target: nil, action: nil)
    private let runtimeStatusLabel = NSTextField(labelWithString: "Runtime: Pending")
    private let whisperStatusLabel = NSTextField(labelWithString: "Whisper model: Pending Download")
    private let cleanupStatusLabel = NSTextField(labelWithString: "Cleanup model: Optional")
    private let setupNoteLabel = NSTextField(labelWithString: "Changing models updates the app config immediately. Use “Download Selected Models” to prefetch the selected models.")
    private let downloadButton = NSButton(title: "Download Selected Models", target: nil, action: nil)
    private let downloadProgressIndicator = NSProgressIndicator()

    private var whisperOptions: [ModelOption] = VoicePowerModelCatalog.whisperOptions
    private var cleanupOptions: [ModelOption] = VoicePowerModelCatalog.cleanupOptions

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
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
        cleanupStatusLabel.stringValue = config.cleanupEnabled ? cleanupStatusLabel.stringValue : "Cleanup model: Optional"
    }

    func setRuntimeStatus(_ value: String) {
        runtimeStatusLabel.stringValue = "Runtime: \(value)"
    }

    func setWhisperModelStatus(_ value: String) {
        whisperStatusLabel.stringValue = "Whisper model: \(value)"
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
        setupNoteLabel.textColor = .secondaryLabelColor
        runtimeStatusLabel.textColor = .secondaryLabelColor
        whisperStatusLabel.textColor = .secondaryLabelColor
        cleanupStatusLabel.textColor = .secondaryLabelColor
        downloadProgressIndicator.style = .spinning
        downloadProgressIndicator.controlSize = .small
        downloadProgressIndicator.isDisplayedWhenStopped = false

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
        downloadButton.target = self
        downloadButton.action = #selector(handlePrepareRuntime)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(runtimeStatusLabel)
        stack.addArrangedSubview(whisperStatusLabel)
        stack.addArrangedSubview(cleanupStatusLabel)
        stack.addArrangedSubview(makeLabeledRow(label: "Whisper model", control: whisperModelPopup))
        stack.addArrangedSubview(makeLabeledRow(label: "Cleanup model", control: cleanupModelPopup))
        stack.addArrangedSubview(cleanupEnabledCheckbox)
        stack.addArrangedSubview(autoPunctuationCheckbox)
        stack.addArrangedSubview(saveAudioCheckbox)
        stack.addArrangedSubview(setupNoteLabel)
        stack.addArrangedSubview(makeDownloadRow())

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
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

    private func repopulate(_ popup: NSPopUpButton, with options: [ModelOption], selectedID: String) {
        popup.removeAllItems()
        popup.addItems(withTitles: options.map(\.title))
        if let index = options.firstIndex(where: { $0.id == selectedID }) {
            popup.selectItem(at: index)
        }
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

    @objc private func handlePrepareRuntime() {
        onPrepareRuntime?()
    }
}
