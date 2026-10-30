import AppKit

@MainActor
final class ClipboardPanel: NSPanel {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let searchField = NSSearchField()
    private let footerLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "No clipboard history yet")

    private var items: [ClipboardItem] = []
    private var filtered: [ClipboardItem] = []
    private var selectedIndex = 0
    private var pasteTarget: NSRunningApplication?

    private static let panelSize = NSSize(width: 440, height: 380)
    private static let rowHeight: CGFloat = 48

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = .floating
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        setupUI()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func setupUI() {
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        contentView = background

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search clipboard history"
        searchField.delegate = self
        searchField.focusRingType = .none

        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.style = .plain
        tableView.allowsMultipleSelection = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(pasteSelected)
        tableView.action = #selector(tableClicked)
        tableView.menu = makeContextMenu()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = .tertiaryLabelColor

        background.addSubview(searchField)
        background.addSubview(scrollView)
        background.addSubview(emptyLabel)
        background.addSubview(footerLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),

            footerLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            footerLabel.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            footerLabel.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            footerLabel.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])

        installKeyMonitor()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let pin = NSMenuItem(title: "Pin / Unpin", action: #selector(togglePinSelected), keyEquivalent: "")
        pin.target = self
        let remove = NSMenuItem(title: "Delete", action: #selector(deleteSelected), keyEquivalent: "")
        remove.target = self
        menu.addItem(pin)
        menu.addItem(remove)
        return menu
    }

    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "p" {
                self.togglePinSelected()
                return nil
            }
            switch event.keyCode {
            case 53: self.dismiss(); return nil
            case 125: self.moveSelection(1); return nil
            case 126: self.moveSelection(-1); return nil
            case 36, 76: self.pasteSelected(); return nil
            case 51, 117: self.deleteSelected(); return nil
            default: return event
            }
        }
    }

    func show() {
        pasteTarget = NSWorkspace.shared.frontmostApplication
        items = HistoryService.shared.items
        filtered = items
        selectedIndex = 0
        searchField.stringValue = ""
        reload()
        positionOnActiveScreen()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        searchField.becomeFirstResponder()
        if !filtered.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(x: visible.midX - Self.panelSize.width / 2,
                             y: visible.midY - Self.panelSize.height / 2)
        setFrameOrigin(origin)
    }

    private func reload() {
        tableView.reloadData()
        if selectedIndex >= filtered.count {
            selectedIndex = max(0, filtered.count - 1)
        }
        if !filtered.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(selectedIndex)
        }
        emptyLabel.isHidden = !filtered.isEmpty
        emptyLabel.stringValue = items.isEmpty ? "No clipboard history yet" : "No matches"
        footerLabel.stringValue = "↑↓ navigate  ·  ↩ paste  ·  ⌘P pin  ·  ⌫ delete  ·  esc close"
    }

    private func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        selectedIndex = max(0, min(filtered.count - 1, selectedIndex + delta))
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
    }

    private var contextIndex: Int {
        let row = tableView.clickedRow
        return row >= 0 ? row : selectedIndex
    }

    @objc private func tableClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < filtered.count else { return }
        selectedIndex = row
        pasteSelected()
    }

    @objc private func togglePinSelected() {
        let index = contextIndex
        guard index >= 0, index < filtered.count else { return }
        HistoryService.shared.togglePin(filtered[index].id)
        items = HistoryService.shared.items
        applyFilter()
    }

    @objc private func deleteSelected() {
        let index = contextIndex
        guard index >= 0, index < filtered.count else { return }
        HistoryService.shared.delete(filtered[index].id)
        items = HistoryService.shared.items
        applyFilter()
    }

    @objc private func pasteSelected() {
        guard selectedIndex >= 0, selectedIndex < filtered.count else { return }
        paste(filtered[selectedIndex])
    }

    private func paste(_ item: ClipboardItem) {
        dismiss()
        HistoryService.shared.paste(item)
        guard HotkeyService.hasAccessibilityAccess else { return }
        pasteTarget?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            ClipboardItem.simulatePaste()
        }
    }

    private func dismiss() {
        orderOut(nil)
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        filtered = query.isEmpty ? items : items.filter {
            $0.preview.lowercased().contains(query) || ($0.text?.lowercased().contains(query) ?? false)
        }
        selectedIndex = 0
        reload()
    }
}

extension ClipboardPanel: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        applyFilter()
    }
}

extension ClipboardPanel: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        HoverTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("HistoryCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? HistoryCellView
            ?? HistoryCellView(identifier: identifier)
        cell.frame.size.width = tableView.bounds.width
        cell.configure(with: filtered[row])
        return cell
    }
}

private final class HistoryCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let pinLabel = NSTextField(labelWithString: "📌")
    private var labelLeading: NSLayoutConstraint!
    private var iconWidth: NSLayoutConstraint!
    private var iconHeight: NSLayoutConstraint!

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        wantsLayer = true

        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 13)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.isBordered = false
        label.drawsBackground = false
        label.isEditable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        pinLabel.font = .systemFont(ofSize: 11)
        pinLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pinLabel)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        labelLeading = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12)
        iconWidth = iconView.widthAnchor.constraint(equalToConstant: 34)
        iconHeight = iconView.heightAnchor.constraint(equalToConstant: 34)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidth,
            iconHeight,
            labelLeading,
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: pinLabel.leadingAnchor, constant: -6),
            pinLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pinLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with item: ClipboardItem) {
        label.stringValue = item.preview
        pinLabel.isHidden = !item.pinned

        if item.type == .image, let data = item.imageData, let image = NSImage(data: data) {
            iconView.image = image
            iconView.isHidden = false
            iconWidth.constant = 34
            iconHeight.constant = 34
            labelLeading.constant = 54
        } else {
            iconView.image = nil
            iconView.isHidden = true
            iconWidth.constant = 0
            iconHeight.constant = 0
            labelLeading.constant = 12
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

private final class HoverTableRowView: NSTableRowView {
    private var hovered = false { didSet { applyBackground() } }

    override var isSelected: Bool {
        didSet { applyBackground() }
    }

    override var isEmphasized: Bool {
        didSet { applyBackground() }
    }

    private func applyBackground() {
        wantsLayer = true
        layer?.cornerRadius = 8
        let color: NSColor
        if isSelected {
            color = NSColor.controlAccentColor.withAlphaComponent(isEmphasized ? 0.28 : 0.18)
        } else if hovered {
            color = NSColor.controlAccentColor.withAlphaComponent(0.10)
        } else {
            color = .clear
        }
        layer?.backgroundColor = color.cgColor
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
}
