import AppKit

@MainActor
final class ReviewWindowController: NSWindowController, NSWindowDelegate {
    private let noteLabel = NSTextField(
        labelWithString: "Edit this dictation result, then choose Ready To Paste. VoicePower will put the edited text on the clipboard and switch back to the target app. Use that app’s normal paste shortcut there, typically Cmd+V on macOS or Ctrl+V in apps that use it."
    )
    private let textView = NSTextView()
    private let readyButton = NSButton(title: "Ready To Paste", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    private var continuation: CheckedContinuation<String?, Never>?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Review Dictation"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 320)
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
        window?.center()
        showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func windowWillClose(_ notification: Notification) {
        finish(with: nil)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        noteLabel.lineBreakMode = .byWordWrapping
        noteLabel.maximumNumberOfLines = 0
        noteLabel.textColor = .secondaryLabelColor

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: 640, height: 280)
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
        readyButton.keyEquivalentModifierMask = [.command]

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
