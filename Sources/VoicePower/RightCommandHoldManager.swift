import ApplicationServices
import Foundation

final class RightCommandHoldManager: @unchecked Sendable {
    private static let rightCommandKeyCode: Int64 = 54
    private static let leftControlMask: UInt64 = 0x00000001
    private static let leftShiftMask: UInt64 = 0x00000002
    private static let rightShiftMask: UInt64 = 0x00000004
    private static let leftCommandMask: UInt64 = 0x00000008
    private static let rightCommandMask: UInt64 = 0x00000010
    private static let leftOptionMask: UInt64 = 0x00000020
    private static let rightOptionMask: UInt64 = 0x00000040
    private static let capsLockMask: UInt64 = 0x00000080
    private static let rightControlMask: UInt64 = 0x00002000
    private static let functionMask: UInt64 = 0x00800000

    private let activationDelay: TimeInterval
    private let onPress: @MainActor () -> Void
    private let onRelease: @MainActor () -> Void
    private let stateQueue = DispatchQueue(label: "local.voicepower.right-command-hold")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationWorkItem: DispatchWorkItem?
    private var isRightCommandDown = false
    private var isHoldActive = false
    private var suppressUntilRelease = false

    init(
        activationDelay: TimeInterval,
        onPress: @escaping @MainActor () -> Void,
        onRelease: @escaping @MainActor () -> Void
    ) throws {
        self.activationDelay = activationDelay
        self.onPress = onPress
        self.onRelease = onRelease

        let keyDownMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let flagsChangedMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let mask = keyDownMask | flagsChangedMask

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let manager = Unmanaged<RightCommandHoldManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handleEvent(type: type, event: event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            throw VoicePowerError.holdToTalkRegistrationFailed(
                reason: "CGEvent.tapCreate returned nil. Check Accessibility permission."
            )
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource else {
            throw VoicePowerError.holdToTalkRegistrationFailed(
                reason: "CFMachPortCreateRunLoopSource returned nil"
            )
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    deinit {
        stateQueue.sync {
            activationWorkItem?.cancel()
            activationWorkItem = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        case .flagsChanged, .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let rawFlags = event.flags.rawValue
            stateQueue.async { [weak self] in
                self?.processEvent(type: type, keyCode: keyCode, rawFlags: rawFlags)
            }
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func processEvent(type: CGEventType, keyCode: Int64, rawFlags: UInt64) {
        switch type {
        case .flagsChanged:
            processFlagsChanged(keyCode: keyCode, rawFlags: rawFlags)
        case .keyDown:
            processKeyDown()
        default:
            break
        }
    }

    private func processFlagsChanged(keyCode: Int64, rawFlags: UInt64) {
        if keyCode == Self.rightCommandKeyCode {
            let isPressed = (rawFlags & Self.rightCommandMask) != 0
            if isPressed {
                handleRightCommandDown(rawFlags: rawFlags)
            } else {
                handleRightCommandUp()
            }
            return
        }

        guard isRightCommandDown else {
            return
        }

        cancelOrStopForShortcutUse()
    }

    private func processKeyDown() {
        guard isRightCommandDown else {
            return
        }

        cancelOrStopForShortcutUse()
    }

    private func handleRightCommandDown(rawFlags: UInt64) {
        guard !isRightCommandDown else {
            return
        }

        isRightCommandDown = true
        suppressUntilRelease = hasDisallowedModifiers(rawFlags)
        guard !suppressUntilRelease else {
            return
        }

        let activationWorkItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.stateQueue.async {
                guard self.isRightCommandDown, !self.suppressUntilRelease, !self.isHoldActive else {
                    return
                }

                self.activationWorkItem = nil
                self.isHoldActive = true
                Task { @MainActor in
                    self.onPress()
                }
            }
        }

        self.activationWorkItem = activationWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay, execute: activationWorkItem)
    }

    private func handleRightCommandUp() {
        guard isRightCommandDown else {
            return
        }

        isRightCommandDown = false
        cancelActivation()
        let shouldRelease = isHoldActive
        isHoldActive = false
        suppressUntilRelease = false

        guard shouldRelease else {
            return
        }

        Task { @MainActor in
            onRelease()
        }
    }

    private func cancelOrStopForShortcutUse() {
        if activationWorkItem != nil {
            cancelActivation()
            suppressUntilRelease = true
            return
        }

        guard isHoldActive else {
            return
        }

        isHoldActive = false
        suppressUntilRelease = true

        Task { @MainActor in
            onRelease()
        }
    }

    private func cancelActivation() {
        activationWorkItem?.cancel()
        activationWorkItem = nil
    }

    private func hasDisallowedModifiers(_ rawFlags: UInt64) -> Bool {
        let disallowedMask =
            Self.leftControlMask |
            Self.leftShiftMask |
            Self.rightShiftMask |
            Self.leftCommandMask |
            Self.leftOptionMask |
            Self.rightOptionMask |
            Self.capsLockMask |
            Self.rightControlMask |
            Self.functionMask

        return (rawFlags & disallowedMask) != 0
    }
}
