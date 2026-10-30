import AppKit
import ApplicationServices

@MainActor
final class HotkeyService {
    static let shared = HotkeyService()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    var onHotkey: (() -> Void)?
    var onUnavailable: (() -> Void)?

    static var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    var isRunning: Bool { eventTap != nil }

    func start() {
        guard eventTap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
                DispatchQueue.main.async { service.reenable() }
                return Unmanaged.passUnretained(event)
            }

            guard type == .keyDown else { return Unmanaged.passUnretained(event) }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let modifiers = flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
            guard keyCode == 9, modifiers == [.maskCommand, .maskShift] else {
                return Unmanaged.passUnretained(event)
            }

            let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { service.onHotkey?() }
            return nil
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            onUnavailable?()
            scheduleRetry()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func reenable() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isRunning else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                if Self.hasAccessibilityAccess { self.start() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }
}
