import AppKit

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let type: ItemType
    let timestamp: Date
    var pinned: Bool
    let text: String?
    let imageData: Data?
    let imageSize: CGSize?
    let preview: String

    enum ItemType: Equatable {
        case text
        case image
    }

    func contentMatches(_ other: ClipboardItem) -> Bool {
        type == other.type && text == other.text && imageData == other.imageData
    }

    static func fromPasteboard() -> ClipboardItem? {
        let pb = NSPasteboard.general

        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            let pngData = normalizePNG(data)
            guard let image = NSImage(data: pngData) else { return nil }
            let size = image.size
            let preview = "[Image \(Int(size.width))×\(Int(size.height))]"
            return ClipboardItem(id: UUID(), type: .image, timestamp: Date(), pinned: false,
                                 text: nil, imageData: pngData, imageSize: size, preview: preview)
        }

        if let string = pb.string(forType: .string) {
            let flat = string.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !flat.isEmpty else { return nil }
            return ClipboardItem(id: UUID(), type: .text, timestamp: Date(), pinned: false,
                                 text: string, imageData: nil, imageSize: nil,
                                 preview: String(flat.prefix(200)))
        }

        return nil
    }

    private static func normalizePNG(_ data: Data) -> Data {
        guard NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) == nil,
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return data }
        return png
    }

    func writeToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch type {
        case .text:
            if let text { pb.setString(text, forType: .string) }
        case .image:
            if let imageData {
                pb.setData(imageData, forType: .png)
                if let image = NSImage(data: imageData), let tiff = image.tiffRepresentation {
                    pb.setData(tiff, forType: .tiff)
                }
            }
        }
    }

    static func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
