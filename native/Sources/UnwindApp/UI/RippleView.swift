import AppKit

final class RippleView: NSView {
    var levels: [Float] = [0, 0, 0] { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let colors: [NSColor] = [.systemRed, .systemGreen, .systemTeal]
        for index in 0..<min(3, levels.count) {
            let level = CGFloat(levels[index])
            let radius = 70 + CGFloat(index) * 55 + level * 80
            let path = NSBezierPath(ovalIn: NSRect(x: bounds.midX - radius, y: -radius * 0.75, width: radius * 2, height: radius * 2))
            path.lineWidth = 1.2 + level * 5
            colors[index].withAlphaComponent(0.08 + level * 0.18).setStroke()
            path.stroke()
        }
    }
}
