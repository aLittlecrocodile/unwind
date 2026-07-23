import AppKit

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PetTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}

@MainActor
final class PetWindowController: NSWindowController {
    var onOpenWorkbench: (() -> Void)?
    var onOpenUnwind: (() -> Void)?
    var onHideTemporarily: (() -> Void)?

    private let store: AppStore
    private let backend: BackendClientProtocol
    private let buddy = BuddyView(frame: .zero)
    private let bubble = NSTextField.label("输入文字或按住麦克风说话", font: .systemFont(ofSize: 12, weight: .medium), color: .secondaryLabelColor)
    private let input = PetTextField()
    private let chatCard = CardView()
    private let toolbar = NSStackView.horizontal(spacing: 6)
    private let toolbarCard = CardView()
    private let playingButton = ActionButton("", bezelStyle: .roundRect) {}
    private let micButton = PressButton(title: "🎙", target: nil, action: nil)
    private var clickTimer: Timer?
    private var dragOrigin: NSPoint?
    private var dragMouseStart: NSPoint?
    private var chatTask: Task<Void, Never>?
    private let ptt = PushToTalkClient()
    private var assistantText = ""
    private var storeObservers: [UUID] = []
    private var audioObserver: UUID?
    private var isExpanded = false

    private let collapsedContentSize = NSSize(width: 108, height: 108)
    private let expandedContentSize = NSSize(width: 340, height: 370)

    init(store: AppStore = .shared, backend: BackendClientProtocol = BackendClient.shared) {
        self.store = store
        self.backend = backend
        let panel = PetPanel(
            contentRect: NSRect(origin: .zero, size: collapsedContentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)
        configureWindow(panel)
        buildUI()
        bind()
    }

    required init?(coder: NSCoder) { nil }

    func positionAtBottomRight() {
        guard let screen = NSScreen.main, let window else { return }
        let area = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: area.maxX - window.frame.width - 24, y: area.minY + 8))
    }

    private func configureWindow(_ panel: NSPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
    }

    private func buildUI() {
        guard let root = window?.contentView else { return }
        root.addSubview(chatCard)
        input.placeholderString = "打字也行…"
        input.applyWarmInputStyle()
        let send = ActionButton("发送") { [weak self] in self?.sendChat(self?.input.stringValue ?? "") }
        let chips = NSStackView.horizontal(spacing: 4, views: [
            ActionButton("压力好大") { [weak self] in self?.sendChat("我压力好大") },
            ActionButton("来点雨声") { [weak self] in self?.sendChat("来点雨声") },
            ActionButton("安心签") { [weak self] in self?.sendChat("给我一张安心签") }
        ])
        micButton.bezelStyle = .circular
        micButton.font = .systemFont(ofSize: 14)
        let inputRow = NSStackView.horizontal(spacing: 6, views: [input, micButton, send])
        let chatStack = NSStackView.vertical(spacing: 6, views: [bubble, playingButton, chips, inputRow])
        inputRow.widthAnchor.constraint(equalTo: chatStack.widthAnchor).isActive = true
        bubble.widthAnchor.constraint(lessThanOrEqualTo: chatStack.widthAnchor).isActive = true
        bubble.maximumNumberOfLines = 2
        bubble.lineBreakMode = .byTruncatingTail
        chatCard.addSubview(chatStack); pin(chatStack, to: chatCard, inset: 10)

        buddy.state = store.buddyState
        buddy.gender = BuddyGender(rawValue: UserDefaults.standard.string(forKey: "buddyGender") ?? "") ?? .male
        root.addSubview(buddy)

        playingButton.isHidden = true
        playingButton.actionHandler = { AudioCoordinator.shared.stop() }

        toolbar.addArrangedSubview(ActionButton("喘口气") { [weak self] in self?.onOpenUnwind?() })
        toolbar.addArrangedSubview(ActionButton("工作台") { [weak self] in self?.onOpenWorkbench?() })
        toolbar.addArrangedSubview(ActionButton("躲起来") { [weak self] in self?.onHideTemporarily?() })
        toolbarCard.addSubview(toolbar); pin(toolbar, to: toolbarCard, inset: 5)
        root.addSubview(toolbarCard)

        // The desktop pet switches between two known sizes.  Frames make the
        // expanded layout deterministic: chat (top), character (middle), and
        // controls (bottom) cannot overlap as the card contents change.
        [chatCard, buddy, toolbarCard].forEach { $0.translatesAutoresizingMaskIntoConstraints = true }
        micButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        micButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        layoutPet(expanded: false)
        applyExpandedState()
    }

    private func bind() {
        storeObservers.append(store.observeState { [weak self] _ in self?.refresh() })
        storeObservers.append(store.observeBuddyState { [weak self] _ in self?.refresh() })
        buddy.onClick = { [weak self] in self?.toggleExpanded() }
        buddy.onDrag = { [weak self] phase, point in self?.drag(phase: phase, point: point) }
        buddy.onGenderChange = { value in UserDefaults.standard.set(value.rawValue, forKey: "buddyGender") }
        micButton.onPress = { [weak self] in self?.startPTT() }
        micButton.onRelease = { [weak self] in self?.endPTT() }
        input.target = self
        input.action = #selector(submitInput)

        ptt.onUserText = { [weak self] text, final in self?.bubble.stringValue = final ? "你：\(text)\n让我想想……" : "「\(text)」" }
        ptt.onAssistantText = { [weak self] text in self?.assistantText += text; self?.bubble.stringValue = self?.assistantText ?? text }
        ptt.onAsset = { [weak self] url, title in Task { try? await AudioCoordinator.shared.play(url: url, title: title, assetID: nil); self?.refreshPlaying() } }
        ptt.onState = { [weak self] state in self?.bubble.stringValue = state }
        ptt.onError = { [weak self] error in self?.bubble.stringValue = error }

        audioObserver = AudioCoordinator.shared.observePlayback { [weak self] _, _ in self?.refreshPlaying() }
        clickTimer = .scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateClickThrough() }
        }
        refresh()
    }

    private func toggleExpanded() {
        guard let window, let root = window.contentView else { return }
        let oldBuddyOrigin = window.convertPoint(toScreen: buddy.frame.origin)
        isExpanded.toggle()
        applyExpandedState()

        let contentSize = isExpanded ? expandedContentSize : collapsedContentSize
        var frame = window.frame
        frame.size = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        window.setFrame(frame, display: false)
        layoutPet(expanded: isExpanded)
        root.layoutSubtreeIfNeeded()
        let newBuddyOrigin = window.convertPoint(toScreen: buddy.frame.origin)
        frame = window.frame
        frame.origin.x += oldBuddyOrigin.x - newBuddyOrigin.x
        frame.origin.y += oldBuddyOrigin.y - newBuddyOrigin.y
        frame = constrainedToVisibleScreen(frame)
        window.setFrame(frame, display: true)

        if isExpanded {
            window.makeKey()
            window.makeFirstResponder(input)
        } else {
            window.makeFirstResponder(nil)
        }
    }

    private func layoutPet(expanded: Bool) {
        if expanded {
            // Content view is non-flipped: y=0 is the bottom.  These values form
            // Three independent bands: chat card → character → toolbar.
            // The card uses its content height (rather than extra empty space),
            // while the 42pt/52pt gaps keep it from covering the PNG artwork.
            chatCard.frame = NSRect(x: 15, y: 225, width: 310, height: 108)
            buddy.frame = NSRect(x: 122, y: 110, width: 108, height: 108)
            toolbarCard.frame = NSRect(x: 66, y: 75, width: 208, height: 38)
        } else {
            buddy.frame = NSRect(origin: .zero, size: collapsedContentSize)
            chatCard.frame = .zero
            toolbarCard.frame = .zero
        }
    }

    private func constrainedToVisibleScreen(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main else { return frame }
        let area = screen.visibleFrame
        var result = frame
        result.origin.x = min(max(result.minX, area.minX), area.maxX - result.width)
        result.origin.y = min(max(result.minY, area.minY), area.maxY - result.height)
        return result
    }

    private func applyExpandedState() {
        chatCard.isHidden = !isExpanded
        toolbarCard.isHidden = !isExpanded
        refreshPlaying()
    }

    @objc private func submitInput() { sendChat(input.stringValue) }

    private func sendChat(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return }
        input.stringValue = ""
        bubble.stringValue = "你：\(text)\n我想想……"
        chatTask?.cancel()
        chatTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await backend.chat(text, currentAssetID: AudioCoordinator.shared.currentAssetID)
                bubble.stringValue = response.reply ?? "我在呢。"
                if let raw = response.replyAudioURL, store.state.settings.speakReplies,
                   let url = URL(string: raw) { await AudioCoordinator.shared.playReply(url: url) }
                if let asset = response.asset, let raw = asset.playbackURL, let url = URL(string: raw) {
                    try await AudioCoordinator.shared.play(url: url, title: asset.title, assetID: asset.id)
                }
                if let seconds = response.timerSeconds { AudioCoordinator.shared.armSleepTimer(seconds: seconds, fade: response.fadeOut != false) }
            } catch is CancellationError { }
            catch { bubble.stringValue = "后端没有接住：\(error.localizedDescription)" }
        }
    }

    private func startPTT() {
        assistantText = ""
        do { try ptt.startRecording() }
        catch { bubble.stringValue = error.localizedDescription }
    }

    private func endPTT() { ptt.endRecording() }

    private func drag(phase: NSEvent.Phase, point: NSPoint) {
        guard let window else { return }
        switch phase {
        case .began: dragOrigin = window.frame.origin; dragMouseStart = point
        case .changed:
            guard let origin = dragOrigin, let start = dragMouseStart else { return }
            window.setFrameOrigin(NSPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y))
        case .ended: dragOrigin = nil; dragMouseStart = nil
        default: break
        }
    }

    private func refresh() {
        buddy.state = store.buddyState
    }

    private func refreshPlaying() {
        let audio = AudioCoordinator.shared
        playingButton.isHidden = !isExpanded || audio.currentTitle == nil
        playingButton.title = audio.currentTitle.map { "♪ \($0) · 停" } ?? ""
    }

    private func updateClickThrough() {
        guard let window, window.isVisible, let root = window.contentView else { return }
        let local = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let interactive = [chatCard, buddy, toolbarCard]
            .filter { !$0.isHidden }
            .contains { $0.frame.insetBy(dx: -4, dy: -4).contains(root.convert(local, from: nil)) }
        window.ignoresMouseEvents = !interactive
    }
}
