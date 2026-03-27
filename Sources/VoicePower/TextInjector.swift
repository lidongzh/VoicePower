import AppKit
import ApplicationServices
import Foundation

@MainActor
final class TextInjector {
    private let restoreClipboard: Bool

    init(restoreClipboard: Bool) {
        self.restoreClipboard = restoreClipboard
    }

    func insert(text: String, targeting application: NSRunningApplication?) throws {
        guard AXIsProcessTrusted() else {
            throw VoicePowerError.accessibilityPermissionMissing
        }

        let pasteboard = NSPasteboard.general
        let previousClipboard = restoreClipboard ? pasteboard.string(forType: .string) : nil

        if let application {
            application.activate(options: [.activateIgnoringOtherApps])
            Thread.sleep(forTimeInterval: 0.15)
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Thread.sleep(forTimeInterval: 0.05)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw VoicePowerError.textInjectionFailed("Unable to create paste events")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        guard restoreClipboard else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            pasteboard.clearContents()
            if let previousClipboard {
                pasteboard.setString(previousClipboard, forType: .string)
            }
        }
    }
}
