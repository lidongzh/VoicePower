import AppKit

@MainActor
final class StatusMenuController: NSObject {
    var onToggle: (() -> Void)?
    var onToggleCleanup: (() -> Void)?
    var onToggleSaveAudio: (() -> Void)?
    var onReload: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let statusLineItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
    private lazy var toggleItem = NSMenuItem(title: "Start Recording", action: #selector(handleToggle), keyEquivalent: "")
    private lazy var cleanupItem = NSMenuItem(title: "Cleanup: Off", action: #selector(handleToggleCleanup), keyEquivalent: "")
    private lazy var saveAudioItem = NSMenuItem(title: "Save Audio: On", action: #selector(handleToggleSaveAudio), keyEquivalent: "")
    private lazy var reloadItem = NSMenuItem(title: "Reload Config", action: #selector(handleReload), keyEquivalent: "r")
    private lazy var quitItem = NSMenuItem(title: "Quit", action: #selector(handleQuit), keyEquivalent: "q")
    private let configPathItem = NSMenuItem(title: "Config: -", action: nil, keyEquivalent: "")

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        toggleItem.target = self
        cleanupItem.target = self
        saveAudioItem.target = self
        reloadItem.target = self
        quitItem.target = self

        menu.addItem(statusLineItem)
        menu.addItem(toggleItem)
        menu.addItem(cleanupItem)
        menu.addItem(saveAudioItem)
        menu.addItem(reloadItem)
        menu.addItem(.separator())
        menu.addItem(configPathItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.button?.title = "VP"
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
        statusItem.button?.title = state.shortTitle
    }

    func setCleanupEnabled(_ enabled: Bool) {
        cleanupItem.title = "Cleanup: \(enabled ? "On" : "Off")"
        cleanupItem.state = enabled ? .on : .off
    }

    func setSaveAudioEnabled(_ enabled: Bool) {
        saveAudioItem.title = "Save Audio: \(enabled ? "On" : "Off")"
        saveAudioItem.state = enabled ? .on : .off
    }

    @objc private func handleToggle() {
        onToggle?()
    }

    @objc private func handleToggleCleanup() {
        onToggleCleanup?()
    }

    @objc private func handleToggleSaveAudio() {
        onToggleSaveAudio?()
    }

    @objc private func handleReload() {
        onReload?()
    }

    @objc private func handleQuit() {
        onQuit?()
    }
}
