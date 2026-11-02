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
            button.toolTip = "Clipboard Win (Control+Shift+V)"
        }

        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show Clipboard History", action: #selector(showClipboard), keyEquivalent: "v")
        showItem.keyEquivalentModifierMask = [.control, .shift]
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
        hotkey.onHotkey = { [weak self] in self?.panel.toggle() }
        hotkey.onStateChange = { [weak self] in self?.refreshPermissionItem() }
        hotkey.start()
        if !HotkeyService.hasRequiredAccess {
            // Without access the hotkey silently does nothing, so ask up front.
            HotkeyService.requestAccess()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidBecomeActive() {
        refreshPermissionItem()
        HotkeyService.shared.start()
    }

    private func refreshPermissionItem() {
        let title: String
        if !HotkeyService.hasAccessibilityAccess {
            title = "Grant Accessibility Access…"
        } else if !HotkeyService.hasInputMonitoringAccess {
            title = "Grant Input Monitoring Access…"
        } else {
            title = "Permissions Granted ✓"
        }
        permissionItem?.title = title
        permissionItem?.isEnabled = !HotkeyService.hasRequiredAccess
    }

    @objc private func requestAccess() {
        HotkeyService.requestAccess()
        openPrivacySettings()
    }

    private func openPrivacySettings() {
        let pane = HotkeyService.hasAccessibilityAccess ? "Privacy_ListenEvent" : "Privacy_Accessibility"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func showClipboard() {
        panel.show()
    }

    @objc private func clearUnpinned() {
        HistoryService.shared.clearUnpinned()
    }
}
