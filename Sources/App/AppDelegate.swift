import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var permissionItem: NSMenuItem?
    private let panel = ClipboardPanel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard Win")
            button.toolTip = "Clipboard Win (Shift+⌘+V)"
        }

        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show Clipboard History", action: #selector(showClipboard), keyEquivalent: "v")
        showItem.keyEquivalentModifierMask = [.command, .shift]
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())
        let clearItem = NSMenuItem(title: "Clear Unpinned", action: #selector(clearUnpinned), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        menu.addItem(.separator())

        let permission = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(requestAccess), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)
        permissionItem = permission

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Clipboard Win", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu

        _ = HistoryService.shared

        let hotkey = HotkeyService.shared
        hotkey.onHotkey = { [weak self] in self?.showClipboard() }
        hotkey.onUnavailable = { [weak self] in self?.updatePermissionState() }
        hotkey.start()
        updatePermissionState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidBecomeActive() {
        updatePermissionState()
    }

    private func updatePermissionState() {
        let trusted = HotkeyService.hasAccessibilityAccess
        permissionItem?.title = trusted ? "Accessibility Access Granted ✓" : "Grant Accessibility Access…"
        permissionItem?.isEnabled = !trusted
        if trusted && !HotkeyService.shared.isRunning {
            HotkeyService.shared.start()
        }
    }

    @objc private func requestAccess() {
        HotkeyService.requestAccessibilityAccess()
        openAccessibilitySettings()
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func showClipboard() {
        panel.show()
    }

    @objc private func clearUnpinned() {
        HistoryService.shared.clearUnpinned()
    }
}
