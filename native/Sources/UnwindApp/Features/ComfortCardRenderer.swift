import AppKit

@MainActor
enum ComfortCardRenderer {
    static func save(text: String, from window: NSWindow?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "unwind-comfort-card.png"
        panel.allowedContentTypes = [.png]
        panel.beginSheetModal(for: window ?? NSApp.keyWindow ?? NSWindow()) { response in
            guard response == .OK, let url = panel.url else { return }
            let image = render(text: text)
            guard let data = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: data),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: url, options: .atomic)
        }
    }

    static func render(text: String) -> NSImage {
        let size = NSSize(width: 720, height: 960)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.94, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSColor(calibratedRed: 0.82, green: 0.25, blue: 0.19, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 70, y: 94, width: 64, height: 64), xRadius: 12, yRadius: 12).fill()
        "安".draw(at: NSPoint(x: 84, y: 106), withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: NSColor.white])
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 12
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 31, weight: .medium), .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: NSRect(x: 70, y: 300, width: 580, height: 430), withAttributes: attributes)
        "U N W I N D".draw(at: NSPoint(x: 154, y: 120), withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
        "把压力，呼出去".draw(at: NSPoint(x: 154, y: 96), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.tertiaryLabelColor])
        image.unlockFocus()
        return image
    }
}
