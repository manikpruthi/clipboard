import AppKit
import ApplicationServices
import os

/// Global Control+Shift+V hotkey via a session event tap.
@MainActor
final class HotkeyService {
    static let shared = HotkeyService()

    /// Virtual key code for V (ANSI position).
    nonisolated static let keyCode: Int64 = 9
    nonisolated static let modifiers: CGEventFlags = [.maskControl, .maskShift]

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    var onHotkey: (() -> Void)?
    /// Called whenever the tap starts or fails to start. Must not call `start()`.
    var onStateChange: (() -> Void)?

    static var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    /// Keyboard event taps also need Input Monitoring on current macOS.
    static var hasInputMonitoringAccess: Bool {
        CGPreflightListenEventAccess()
    }

    static var hasRequiredAccess: Bool {
        hasAccessibilityAccess && hasInputMonitoringAccess
    }

    /// Shows the system prompts for whichever permissions are missing.
    static func requestAccess() {
        if !hasAccessibilityAccess {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if !hasInputMonitoringAccess {
            _ = CGRequestListenEventAccess()
        }
    }

    var isRunning: Bool { eventTap != nil }

    private let log = Logger(subsystem: "com.manikpruthi.clipboardwin", category: "hotkey")
    private var loggedFailure = false

    /// Idempotent. On failure, keeps retrying in the background until the tap is created.
    func start() {
        guard !isRunning else { return }
        if createTap() {
            log.info("Hotkey tap started")
            loggedFailure = false
            stopRetrying()
        } else {
            if !loggedFailure {
                log.error("Hotkey tap unavailable (accessibility: \(Self.hasAccessibilityAccess, privacy: .public), input monitoring: \(Self.hasInputMonitoringAccess, privacy: .public))")
                loggedFailure = true
            }
            scheduleRetry()
        }
        onStateChange?()
    }

    private func createTap() -> Bool {
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
            let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
            guard keyCode == HotkeyService.keyCode, modifiers == HotkeyService.modifiers else {
                return Unmanaged.passUnretained(event)
            }

            // Swallow key repeats too, but only act on the initial press.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
                DispatchQueue.main.async { service.onHotkey?() }
            }
            return nil
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func reenable() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isRunning else { return }
                self.start()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    private func stopRetrying() {
        retryTimer?.invalidate()
        retryTimer = nil
    }
}
