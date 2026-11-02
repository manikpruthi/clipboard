import AppKit

@MainActor
final class HistoryService {
    static let shared = HistoryService()

    private(set) var items: [ClipboardItem] = []
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let maxItems = 50
    /// Cap on memory held by unpinned entries; oldest unpinned entries are dropped first.
    private let maxUnpinnedBytes = 200 * 1024 * 1024

    private init() {
        startMonitoring()
    }

    private func startMonitoring() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPasteboard() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkPasteboard() {
        let changeCount = NSPasteboard.general.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard let item = ClipboardItem.fromPasteboard() else { return }
        insert(item)
    }

    private func insert(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.contentMatches(item) }) {
            let existing = items.remove(at: index)
            // Same text, but keep the newest copy's formatting. Pinned entries keep their
            // place; unpinned ones move to the top.
            var updated = item
            updated.pinned = existing.pinned
            items.insert(updated, at: existing.pinned ? index : pinnedCount)
        } else {
            items.insert(item, at: pinnedCount)
        }
        trim()
    }

    private var pinnedCount: Int {
        items.prefix { $0.pinned }.count
    }

    private func trim() {
        var kept: [ClipboardItem] = []
        var unpinned = 0
        var unpinnedBytes = 0
        for item in items {
            if item.pinned {
                kept.append(item)
            } else if unpinned < maxItems, unpinnedBytes + item.byteCount <= maxUnpinnedBytes {
                kept.append(item)
                unpinned += 1
                unpinnedBytes += item.byteCount
            }
        }
        items = kept
    }

    func paste(_ item: ClipboardItem) {
        item.writeToPasteboard()
        lastChangeCount = NSPasteboard.general.changeCount
        guard !item.pinned, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.insert(items.remove(at: index), at: pinnedCount)
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
