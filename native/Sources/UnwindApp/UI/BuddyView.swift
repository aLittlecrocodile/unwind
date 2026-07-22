import AppKit

enum BuddyGender: String, CaseIterable {
    case male
    case female

    var title: String {
        switch self {
        case .male: "男生"
        case .female: "女生"
        }
    }
}

final class BuddyView: NSView {
    var state: BuddyState = .idle { didSet { needsDisplay = true } }
    var gender: BuddyGender = .male { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    var onDrag: ((NSEvent.Phase, NSPoint) -> Void)?
    var onGenderChange: ((BuddyGender) -> Void)?
    private var downPoint: NSPoint?
    private var dragged = false
    private lazy var maleImage = Self.loadImage(named: "buddy-male")
    private lazy var femaleImage = Self.loadImage(named: "buddy-female")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image = gender == .male ? maleImage : femaleImage else { return }
        let sourceRect = gender == .male
            ? NSRect(x: 210, y: 135, width: 725, height: 695)
            : NSRect(x: 200, y: 145, width: 735, height: 685)
        image.draw(
            in: bounds.insetBy(dx: 1, dy: 1),
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = NSEvent.mouseLocation
        dragged = false
        onDrag?(.began, NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint else { return }
        let point = NSEvent.mouseLocation
        if abs(point.x - downPoint.x) + abs(point.y - downPoint.y) >= 5 { dragged = true }
        onDrag?(.changed, point)
    }

    override func mouseUp(with event: NSEvent) {
        onDrag?(.ended, NSEvent.mouseLocation)
        if !dragged { onClick?() }
        downPoint = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        for value in BuddyGender.allCases {
            let item = NSMenuItem(title: value.title, action: #selector(selectGender(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value.rawValue
            item.state = value == gender ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }

    @objc private func selectGender(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let value = BuddyGender(rawValue: rawValue) else { return }
        gender = value
        onGenderChange?(value)
    }

    private static func loadImage(named name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        var sourceRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { sourceRoot.deleteLastPathComponent() }
        return NSImage(contentsOf: sourceRoot.appendingPathComponent("Resources/\(name).png"))
    }
}
