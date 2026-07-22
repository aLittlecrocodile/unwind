import AppKit

@MainActor
final class CallWindowController: NSWindowController {
    private let stateLabel = NSTextField.label("准备接通", font: .systemFont(ofSize: 16, weight: .semibold))
    private let timerLabel = NSTextField.label("00:00", font: .monospacedDigitSystemFont(ofSize: 13, weight: .medium), color: .secondaryLabelColor)
    private let transcript = NSTextView()
    private let muteButton = ActionButton("静音") {}
    private let client = RealtimeVoiceClient()
    private var startedAt: Date?
    private var timer: Timer?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "和 Unwind 聊一会儿"
        window.isReleasedWhenClosed = false
        window.delegate = self
        buildUI()
        bind()
    }

    required init?(coder: NSCoder) { nil }

    func start() {
        showWindow(nil); window?.center(); NSApp.activate(ignoringOtherApps: true)
        transcript.string = ""
        stateLabel.stringValue = "正在接通"
        do { try client.start() }
        catch { stateLabel.stringValue = error.localizedDescription }
    }

    private func buildUI() {
        guard let root = window?.contentView else { return }
        let avatar = BuddyView(frame: NSRect(x: 0, y: 0, width: 150, height: 180))
        avatar.state = .rest
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = transcript
        transcript.isEditable = false; transcript.font = .systemFont(ofSize: 13); transcript.textContainerInset = NSSize(width: 10, height: 10)
        muteButton.actionHandler = { [weak self] in
            guard let self else { return }
            client.setMuted(!client.muted); muteButton.title = client.muted ? "取消静音" : "静音"
        }
        let hangup = ActionButton("挂断") { [weak self] in self?.close() }
        hangup.contentTintColor = .systemRed
        let buttons = NSStackView.horizontal(spacing: 12, views: [muteButton, hangup])
        let stack = NSStackView.vertical(spacing: 12, views: [avatar, stateLabel, timerLabel, scroll, buttons])
        stack.alignment = .centerX
        root.addSubview(stack); pin(stack, to: root, inset: 18)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
    }

    private func bind() {
        client.onEvent = { [weak self] event in
            guard let self else { return }
            switch event.type {
            case "ready":
                stateLabel.stringValue = "已接通，我在听"; startedAt = .now; startTimer()
            case "asr_info": stateLabel.stringValue = "我在听"
            case "asr": if let text = event.text, event.isFinal { append("你：\(text)") }
            case "chat": if let text = event.text { append("Unwind：\(text)"); stateLabel.stringValue = "Unwind 正在回应" }
            case "tts_end": stateLabel.stringValue = "我在听"
            case "generation_started": append("系统：正在准备专属音频")
            case "generation_done": append("系统：专属音频已经准备好")
            case "session_end": close()
            case "error": stateLabel.stringValue = event.text ?? "通话发生错误"
            default: break
            }
        }
        client.onError = { [weak self] error in self?.stateLabel.stringValue = error }
    }

    private func append(_ line: String) {
        transcript.textStorage?.append(NSAttributedString(string: (transcript.string.isEmpty ? "" : "\n") + line, attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        transcript.scrollToEndOfDocument(nil)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = .scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                let value = Int(Date.now.timeIntervalSince(startedAt))
                self.timerLabel.stringValue = String(format: "%02d:%02d", value / 60, value % 60)
            }
        }
    }
}

extension CallWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { timer?.invalidate(); client.stop() }
}
