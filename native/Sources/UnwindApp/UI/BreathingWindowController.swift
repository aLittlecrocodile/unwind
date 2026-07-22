import AppKit
import AVFoundation

@MainActor
final class BreathingWindowController: NSWindowController {
    private let orb = NSView()
    private let phase = NSTextField.label("准备", font: .systemFont(ofSize: 24, weight: .semibold))
    private let count = NSTextField.label("找个舒服的姿势，跟着圆球呼吸", color: .secondaryLabelColor)
    private let micButton = ActionButton("跟随我的呼吸") {}
    private var task: Task<Void, Never>?
    private let levelMonitor = MicrophoneLevelMonitor()
    private var micOn = false

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "呼吸 60 秒"
        window.isReleasedWhenClosed = false
        buildUI()
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func start() {
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        runGuided()
    }

    private func buildUI() {
        guard let root = window?.contentView else { return }
        orb.wantsLayer = true
        orb.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.78).cgColor
        orb.layer?.cornerRadius = 85
        orb.layer?.shadowColor = NSColor.controlAccentColor.cgColor
        orb.layer?.shadowOpacity = 0.35
        orb.layer?.shadowRadius = 30
        micButton.actionHandler = { [weak self] in self?.toggleMic() }
        let again = ActionButton("再来一轮") { [weak self] in self?.stopMic(); self?.runGuided() }
        let done = ActionButton("回到对话") { [weak self] in self?.close() }
        let buttons = NSStackView.horizontal(spacing: 10, views: [micButton, again, done])
        let stack = NSStackView.vertical(spacing: 18, views: [orb, phase, count, buttons])
        stack.alignment = .centerX
        root.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor), stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            orb.widthAnchor.constraint(equalToConstant: 170), orb.heightAnchor.constraint(equalToConstant: 170)
        ])
    }

    private func runGuided() {
        stopMic()
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            for round in 1...3 {
                for step in [("吸气", 4, 1.32), ("停留", 7, 1.32), ("呼气", 8, 0.72)] {
                    phase.stringValue = "\(step.0) · 第 \(round) 轮"
                    animateOrb(scale: step.2, duration: Double(step.1))
                    for second in stride(from: step.1, through: 1, by: -1) {
                        count.stringValue = "\(second)"
                        try? await Task.sleep(for: .seconds(1))
                        if Task.isCancelled { return }
                    }
                }
            }
            phase.stringValue = "很好"
            count.stringValue = "带着这口气回去吧"
        }
    }

    private func animateOrb(scale: CGFloat, duration: Double) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration
            orb.animator().layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
    }

    private func toggleMic() { micOn ? stopMic() : startMic() }

    private func startMic() {
        task?.cancel()
        let relay = MainActorRelay<Float> { [weak self] level in
            self?.phase.stringValue = level > 0.22 ? "呼——" : "吸气"
            self?.count.stringValue = level > 0.22 ? "把它都吐出去" : "轻轻地"
            self?.orb.layer?.setAffineTransform(CGAffineTransform(scaleX: CGFloat(1.02 - level * 0.4), y: CGFloat(1.02 - level * 0.4)))
        }
        do {
            try levelMonitor.start(relay: relay); micOn = true; micButton.title = "停止跟随"
        } catch { count.stringValue = error.localizedDescription }
    }

    private func stopMic() {
        guard micOn else { return }
        levelMonitor.stop(); micOn = false; micButton.title = "跟随我的呼吸"
    }
}

extension BreathingWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { task?.cancel(); stopMic() }
}
