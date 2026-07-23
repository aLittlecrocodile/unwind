import AppKit

enum UnwindPalette {
    static let canvas = NSColor(srgbRed: 0.969, green: 0.929, blue: 0.855, alpha: 1)
    static let surface = NSColor(srgbRed: 1.000, green: 0.949, blue: 0.835, alpha: 1)
    static let insetSurface = NSColor(srgbRed: 0.973, green: 0.886, blue: 0.718, alpha: 1)
    static let elevatedSurface = NSColor(srgbRed: 0.953, green: 0.847, blue: 0.659, alpha: 1)
    static let inputSurface = NSColor(srgbRed: 1.000, green: 0.974, blue: 0.910, alpha: 1)
    static let selectionSurface = NSColor(srgbRed: 0.953, green: 0.831, blue: 0.631, alpha: 1)
    static let border = NSColor(srgbRed: 0.702, green: 0.537, blue: 0.337, alpha: 1)
}

final class ActionButton: NSButton {
    var actionHandler: (() -> Void)?

    convenience init(_ title: String, bezelStyle: NSButton.BezelStyle = .rounded, handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.bezelStyle = bezelStyle
        actionHandler = handler
        target = self
        action = #selector(runAction)
    }

    @objc private func runAction() { actionHandler?() }
}

final class PressButton: NSButton {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        highlight(true)
        onPress?()
        window?.trackEvents(matching: [.leftMouseUp], timeout: .infinity, mode: .eventTracking) { [weak self] event, _ in
            guard event != nil else { return }
            self?.highlight(false)
            self?.onRelease?()
        }
    }
}

extension NSTextField {
    static func label(_ text: String, font: NSFont = .systemFont(ofSize: 13), color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    func applyWarmInputStyle() {
        drawsBackground = true
        backgroundColor = UnwindPalette.inputSurface
    }
}

extension NSScrollView {
    func applyWarmBackground() {
        drawsBackground = true
        backgroundColor = UnwindPalette.surface
        contentView.drawsBackground = true
        contentView.backgroundColor = UnwindPalette.surface
    }
}

extension NSStackView {
    static func vertical(spacing: CGFloat = 8, views: [NSView] = []) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    static func horizontal(spacing: CGFloat = 8, views: [NSView] = []) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }
}

final class CardView: NSView {
    private let fillKind: FillKind

    private enum FillKind {
        case surface, inset, elevated, selection
    }

    init(material: NSVisualEffectView.Material = .contentBackground) {
        switch material {
        case .underWindowBackground: fillKind = .inset
        case .hudWindow: fillKind = .elevated
        case .selection: fillKind = .selection
        default: fillKind = .surface
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        updateWarmColors()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateWarmColors()
    }

    private func updateWarmColors() {
        let fill: NSColor
        switch fillKind {
        case .surface: fill = UnwindPalette.surface
        case .inset: fill = UnwindPalette.insetSurface
        case .elevated: fill = UnwindPalette.elevatedSurface
        case .selection: fill = UnwindPalette.selectionSurface
        }
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = UnwindPalette.border.withAlphaComponent(0.82).cgColor
    }
}

@MainActor
func pin(_ view: NSView, to parent: NSView, inset: CGFloat = 0) {
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
        view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
        view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
        view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
    ])
}
