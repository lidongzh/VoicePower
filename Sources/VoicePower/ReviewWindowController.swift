import AppKit

@MainActor
final class ReviewWindowController: NSWindowController, NSWindowDelegate {
    private static let defaultWindowSize = NSSize(width: 500, height: 420)
    private static let savedWidthKey = "VoicePowerReviewWindow.v2.width"
    private static let savedHeightKey = "VoicePowerReviewWindow.v2.height"
    private let noteLabel: NSTextField = {
        let label = NSTextField(
            wrappingLabelWithString: "Edit this dictation result, then choose Ready To Paste. VoicePower will put the edited text on the clipboard and switch back to the target app. Use that app’s normal paste shortcut there, typically Cmd+V on macOS or Ctrl+V in apps that use it."
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }()
    private let textView = NSTextView()
    private let readyButton = NSButton(title: "Ready To Paste", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    private var continuation: CheckedContinuation<String?, Never>?

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Review Dictation"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 320)
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func review(text: String) async -> String? {
        if continuation != nil {
            finish(with: nil)
        }

        textView.string = text
        applyPreferredWindowSize()
        showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        fitWindowToVisibleScreen()
        window?.contentView?.layoutSubtreeIfNeeded()
        updateTextViewLayout()
        window?.makeFirstResponder(readyButton)

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func windowWillClose(_ notification: Notification) {
        finish(with: nil)
    }

    func windowDidResize(_ notification: Notification) {
        saveCurrentWindowSize()
        updateTextViewLayout()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        fitWindowToVisibleScreen()
        updateTextViewLayout()
    }

    private func fitWindowToVisibleScreen() {
        guard let window else {
            return
        }

        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame.insetBy(dx: 12, dy: 12) else {
            return
        }

        var frame = window.frame
        frame.size.width = min(max(frame.size.width, window.minSize.width), visibleFrame.width)
        frame.size.height = min(max(frame.size.height, window.minSize.height), visibleFrame.height)

        let centeredX = visibleFrame.minX + max(0, (visibleFrame.width - frame.width) / 2)
        let centeredY = visibleFrame.minY + max(0, (visibleFrame.height - frame.height) / 2)

        if frame.minX < visibleFrame.minX || frame.maxX > visibleFrame.maxX {
            frame.origin.x = centeredX
        }
        if frame.minY < visibleFrame.minY || frame.maxY > visibleFrame.maxY {
            frame.origin.y = centeredY
        }

        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)

        window.setFrame(frame, display: false)
        saveCurrentWindowSize()
    }

    private func applyPreferredWindowSize() {
        guard let window else {
            return
        }

        let savedSize = loadSavedWindowSize() ?? Self.defaultWindowSize
        let frame = NSRect(origin: .zero, size: savedSize)
        window.setFrame(frame, display: false)
        window.center()
    }

    private func saveCurrentWindowSize() {
        guard let window else {
            return
        }

        UserDefaults.standard.set(window.frame.width, forKey: Self.savedWidthKey)
        UserDefaults.standard.set(window.frame.height, forKey: Self.savedHeightKey)
    }

    private func loadSavedWindowSize() -> NSSize? {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: Self.savedWidthKey)
        let height = defaults.double(forKey: Self.savedHeightKey)
        guard width > 0, height > 0 else {
            return nil
        }

        return NSSize(width: width, height: height)
    }

    private func updateTextViewLayout() {
        guard let scrollView = textView.enclosingScrollView,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return
        }

        let availableWidth = max(scrollView.contentSize.width, 1)
        let minimumHeight = max(scrollView.contentSize.height, 1)
        textContainer.containerSize = NSSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height + (textView.textContainerInset.height * 2))
        textView.frame = NSRect(x: 0, y: 0, width: availableWidth, height: max(minimumHeight, usedHeight))
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: 420, height: 280)
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView

        readyButton.target = self
        readyButton.action = #selector(handleReady)
        readyButton.keyEquivalent = "\r"
        readyButton.keyEquivalentModifierMask = []
        if let readyButtonCell = readyButton.cell as? NSButtonCell {
            window?.defaultButtonCell = readyButtonCell
        }

        cancelButton.target = self
        cancelButton.action = #selector(handleCancel)

        let buttonRow = NSStackView(views: [readyButton, cancelButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10

        contentView.addSubview(noteLabel)
        contentView.addSubview(scrollView)
        contentView.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            noteLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            noteLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            noteLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -12),

            buttonRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            buttonRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    @objc private func handleReady() {
        finish(with: textView.string)
        window?.orderOut(nil)
    }

    @objc private func handleCancel() {
        finish(with: nil)
        window?.orderOut(nil)
    }

    private func finish(with result: String?) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        continuation.resume(returning: result)
    }
}
