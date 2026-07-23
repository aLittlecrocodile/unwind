import AppKit

// 桌宠的"外观件"：HUD 信息条、图标按钮。
// 视觉方向参考 Lofi Neko 一类桌宠的画面语言（紧凑图标条 + 小面板 HUD），
// 不引入 XP/货币/解锁那套养成经济。

/// 头顶 HUD 信息条：暖纸小胶囊，底色按番茄钟进度填充，提醒态换朱砂描边。
/// 点击 = 完成打卡（由 onTap 决定语义）。只放状态和进度，不放任何"资产"数字。
final class HudChipView: NSView {
    var text: String = "" {
        didSet {
            label.stringValue = text
            needsDisplay = true
        }
    }
    /// 0~1 的番茄钟进度；nil 表示不画进度底
    var progress: CGFloat? {
        didSet { needsDisplay = true }
    }
    /// 提醒态（该喝水/坐久了）：朱砂描边
    var emphasized = false {
        didSet { needsDisplay = true }
    }
    /// 可点（打卡/喘口气入口）：手型光标提示，和描边样式解耦
    var clickable = false {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    var onTap: (() -> Void)?

    private let label = NSTextField.label("", font: .systemFont(ofSize: 11, weight: .medium), color: UnwindPalette.woodDark)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -20)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let radius = bounds.height / 2
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
        UnwindPalette.inputSurface.setFill()
        pill.fill()
        if let progress, progress > 0 {
            NSGraphicsContext.current?.saveGraphicsState()
            pill.addClip()
            UnwindPalette.vermilion.withAlphaComponent(0.18).setFill()
            NSRect(x: 0, y: 0, width: bounds.width * min(progress, 1), height: bounds.height).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        pill.lineWidth = 1.5
        (emphasized ? UnwindPalette.vermilion : UnwindPalette.border.withAlphaComponent(0.7)).setStroke()
        pill.stroke()
    }

    override func resetCursorRects() {
        if clickable { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func mouseDown(with event: NSEvent) { onTap?() }
}

/// 紧凑圆形图标按钮（悬停工具条用），SF Symbol + 中文 tooltip。
final class IconButton: NSButton {
    private var handler: (() -> Void)?

    convenience init(symbol: String, tip: String, handler: @escaping () -> Void) {
        self.init(title: "", target: nil, action: nil)
        self.handler = handler
        isBordered = false
        toolTip = tip
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        contentTintColor = UnwindPalette.woodDark
        wantsLayer = true
        layer?.backgroundColor = UnwindPalette.inputSurface.cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = UnwindPalette.border.withAlphaComponent(0.6).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        target = self
        action = #selector(runAction)
    }

    @objc private func runAction() { handler?() }
}
