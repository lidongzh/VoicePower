import AppKit

@MainActor
final class StatusMenuController: NSObject {
    var onToggle: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenInputMonitoringSettings: (() -> Void)?
    var onPrepareRuntime: (() -> Void)?
    var onReload: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let statusLineItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
    private let runtimeLineItem = NSMenuItem(title: "Runtime: Pending", action: nil, keyEquivalent: "")
    private let workerLineItem = NSMenuItem(title: "Worker: Pending", action: nil, keyEquivalent: "")
    private let whisperModelLineItem = NSMenuItem(title: "Whisper Model: Pending", action: nil, keyEquivalent: "")
    private let cleanupModelLineItem = NSMenuItem(title: "Cleanup Model: Optional", action: nil, keyEquivalent: "")
    private let holdToTalkPermissionLineItem = NSMenuItem(title: "Hold-to-talk: Ready", action: nil, keyEquivalent: "")
    private lazy var toggleItem = NSMenuItem(title: "Start Recording", action: #selector(handleToggle), keyEquivalent: "")
    private lazy var settingsItem = NSMenuItem(title: "Settings…", action: #selector(handleOpenSettings), keyEquivalent: ",")
    private lazy var openInputMonitoringSettingsItem = NSMenuItem(title: "Open Input Monitoring Settings", action: #selector(handleOpenInputMonitoringSettings), keyEquivalent: "")
    private lazy var prepareRuntimeItem = NSMenuItem(title: "Prepare Runtime", action: #selector(handlePrepareRuntime), keyEquivalent: "")
    private lazy var reloadItem = NSMenuItem(title: "Reload Config", action: #selector(handleReload), keyEquivalent: "r")
    private lazy var quitItem = NSMenuItem(title: "Quit", action: #selector(handleQuit), keyEquivalent: "q")
    private let configPathItem = NSMenuItem(title: "Config: -", action: nil, keyEquivalent: "")
    private let statusItemImage = StatusMenuController.loadStatusItemImage()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        toggleItem.target = self
        settingsItem.target = self
        openInputMonitoringSettingsItem.target = self
        prepareRuntimeItem.target = self
        reloadItem.target = self
        quitItem.target = self

        menu.addItem(statusLineItem)
        menu.addItem(runtimeLineItem)
        menu.addItem(workerLineItem)
        menu.addItem(whisperModelLineItem)
        menu.addItem(cleanupModelLineItem)
        menu.addItem(holdToTalkPermissionLineItem)
        menu.addItem(.separator())
        menu.addItem(toggleItem)
        menu.addItem(settingsItem)
        menu.addItem(openInputMonitoringSettingsItem)
        menu.addItem(prepareRuntimeItem)
        menu.addItem(reloadItem)
        menu.addItem(.separator())
        menu.addItem(configPathItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        updateStatusButton(shortTitle: "VP", statusText: "Idle")
        statusItem.menu = menu
    }

    convenience init(configPath: String) {
        self.init()
        setConfigPath(configPath)
    }

    func setConfigPath(_ configPath: String) {
        configPathItem.title = "Config: \(configPath)"
    }

    func update(for state: VoiceTypingState) {
        statusLineItem.title = "Status: \(state.statusText)"
        toggleItem.title = state.toggleTitle
        toggleItem.isEnabled = state.toggleEnabled
        updateStatusButton(shortTitle: state.shortTitle, statusText: state.statusText)
    }

    private static func loadStatusItemImage() -> NSImage? {
        let image =
            Bundle.main.url(forResource: "VoicePower", withExtension: "icns")
                .flatMap(NSImage.init(contentsOf:))
            ?? (NSApplication.shared.applicationIconImage.copy() as? NSImage)

        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = false
        return image
    }

    private func updateStatusButton(shortTitle: String, statusText: String) {
        guard let button = statusItem.button else {
            return
        }

        if let statusItemImage {
            button.image = statusItemImage
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = shortTitle == "VP" ? .imageOnly : .imageLeft
            button.title = shortTitle == "VP" ? "" : shortTitle
        } else {
            button.image = nil
            button.title = shortTitle
        }

        button.toolTip = "VoicePower: \(statusText)"
    }

    func setRuntimeStatus(_ value: String) {
        runtimeLineItem.title = "Runtime: \(value)"
    }

    func setWhisperModelStatus(_ value: String) {
        whisperModelLineItem.title = "Whisper Model: \(value)"
    }

    func setWorkerStatus(_ value: String) {
        workerLineItem.title = "Worker: \(value)"
    }

    func setCleanupModelStatus(_ value: String) {
        cleanupModelLineItem.title = "Cleanup Model: \(value)"
    }

    func setHoldToTalkPermissionStatus(_ value: String, needsAction: Bool) {
        holdToTalkPermissionLineItem.title = "Hold-to-talk: \(value)"
        openInputMonitoringSettingsItem.isHidden = !needsAction
    }

    @objc private func handleToggle() {
        onToggle?()
    }

    @objc private func handleOpenSettings() {
        onOpenSettings?()
    }

    @objc private func handleOpenInputMonitoringSettings() {
        onOpenInputMonitoringSettings?()
    }

    @objc private func handlePrepareRuntime() {
        onPrepareRuntime?()
    }

    @objc private func handleReload() {
        onReload?()
    }

    @objc private func handleQuit() {
        onQuit?()
    }
}
