import AppKit

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

final class CardView: NSVisualEffectView {
    init(material: NSVisualEffectView.Material = .contentBackground) {
        super.init(frame: .zero)
        self.material = material
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
    }

    required init?(coder: NSCoder) { nil }
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
