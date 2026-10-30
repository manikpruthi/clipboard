import AppKit

@MainActor
final class HistoryService {
    static let shared = HistoryService()

    private(set) var items: [ClipboardItem] = []
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let maxItems = 50

    private init() {
        startMonitoring()
    }

    private func startMonitoring() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPasteboard() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        let changeCount = pb.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard let item = ClipboardItem.fromPasteboard() else { return }
        insert(item)
    }

    private func insert(_ item: ClipboardItem) {
        if let existing = items.first(where: { $0.contentMatches(item) }) {
            remove(content: item)
            var updated = existing
            updated.pinned = existing.pinned || item.pinned
            insertRespectingPins(updated)
        } else {
            insertRespectingPins(item)
        }
        trim()
    }

    private func insertRespectingPins(_ item: ClipboardItem) {
        let pinnedCount = items.prefix { $0.pinned }.count
        items.insert(item, at: item.pinned ? 0 : pinnedCount)
    }

    private func remove(content item: ClipboardItem) {
        items.removeAll { $0.contentMatches(item) }
    }

    private func trim() {
        var kept: [ClipboardItem] = []
        var unpinned = 0
        for item in items {
            if item.pinned {
                kept.append(item)
            } else if unpinned < maxItems {
                kept.append(item)
                unpinned += 1
            }
        }
        items = kept
    }

    func paste(_ item: ClipboardItem) {
        item.writeToPasteboard()
        lastChangeCount = NSPasteboard.general.changeCount
        if !item.pinned {
            remove(content: item)
            insertRespectingPins(item)
            trim()
        }
    }

    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        let pinned = items.filter(\.pinned)
        let unpinned = items.filter { !$0.pinned }
        items = pinned + unpinned
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clearUnpinned() {
        items.removeAll { !$0.pinned }
    }
}
