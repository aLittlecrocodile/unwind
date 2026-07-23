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
    /// 图标条容器：透明，只承担布局和点击穿透判定；圆钮各自带底色
    private let toolbarCard = NSView()
    private var timerButton: IconButton?
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
    /// 头顶 HUD：提醒一键打卡 + 番茄钟进度（见 PetChromeViews）
    private let statusChip = HudChipView(frame: .zero)
    /// 卷轴待办：点工具条"待办"图标，从小人上方展开（见 TodoScrollController）
    private var todoScroll: TodoScrollController?
    private var lastBuddyState: BuddyState = .idle

    // 折叠态在小人头顶留一条芯片位
    private let collapsedContentSize = NSSize(width: 150, height: 150)
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

        statusChip.isHidden = true
        statusChip.onTap = { [weak self] in self?.ackReminder() }
        root.addSubview(statusChip)

        let timer = IconButton(symbol: "timer", tip: "番茄钟") { [weak self] in self?.showTimerMenu() }
        timerButton = timer
        toolbar.addArrangedSubview(timer)
        toolbar.addArrangedSubview(IconButton(symbol: "checklist", tip: "今日待办") { [weak self] in self?.toggleTodoScroll() })
        toolbar.addArrangedSubview(IconButton(symbol: "figure.walk", tip: "我起来了") { [weak self] in self?.store.recordStand() })
        toolbar.addArrangedSubview(IconButton(symbol: "wind", tip: "喘口气") { [weak self] in self?.onOpenUnwind?() })
        toolbar.addArrangedSubview(IconButton(symbol: "square.grid.2x2", tip: "工作台") { [weak self] in self?.onOpenWorkbench?() })
        toolbar.addArrangedSubview(IconButton(symbol: "moon.zzz", tip: "躲起来（10 分钟）") { [weak self] in
            guard let self else { return }
            self.todoScroll?.close(animated: false)
            self.onHideTemporarily?()
        })
        toolbarCard.addSubview(toolbar); pin(toolbar, to: toolbarCard, inset: 5)
        root.addSubview(toolbarCard)

        // The desktop pet switches between two known sizes.  Frames make the
        // expanded layout deterministic: chat (top), character (middle), and
        // controls (bottom) cannot overlap as the card contents change.
        [chatCard, buddy, toolbarCard, statusChip].forEach { $0.translatesAutoresizingMaskIntoConstraints = true }
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
            // 图标工具条居中：6 × 28 + 间距 + 内边距
            toolbarCard.frame = NSRect(x: 66, y: 72, width: 208, height: 40)
            statusChip.frame = .zero
        } else {
            // 小人居中站底部，头顶留 HUD 芯片位
            buddy.frame = NSRect(x: (collapsedContentSize.width - 108) / 2, y: 0, width: 108, height: 108)
            statusChip.frame = NSRect(x: 5, y: 118, width: collapsedContentSize.width - 10, height: 24)
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

    /// 卷轴待办：顶轴挂在图标条正下方展开/收起
    private func toggleTodoScroll() {
        guard let window else { return }
        if todoScroll == nil {
            let controller = TodoScrollController(store: store)
            controller.onOpenWorkbench = { [weak self] in self?.onOpenWorkbench?() }
            todoScroll = controller
        }
        let toolbarOnScreen = window.convertToScreen(toolbarCard.convert(toolbarCard.bounds, to: nil))
        todoScroll?.toggle(below: toolbarOnScreen, fallbackAbove: window.frame)
    }

    /// 番茄钟小菜单：待机给三档时长，进行中给暂停/继续和结束；
    /// 进度显示走小人头顶的 HUD 芯片，不需要额外窗口
    private func showTimerMenu() {
        guard let timerButton else { return }
        let menu = NSMenu()
        if store.state.focusSession.phase == .idle {
            for preset in FocusPreset.allCases {
                let item = NSMenuItem(title: "专注 \(preset.rawValue) 分钟", action: #selector(timerMenuStart(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.rawValue
                menu.addItem(item)
            }
        } else {
            let paused = store.state.focusSession.phase == .paused
            let pause = NSMenuItem(title: paused ? "继续" : "暂停", action: #selector(timerMenuPauseResume), keyEquivalent: "")
            pause.target = self
            menu.addItem(pause)
            let end = NSMenuItem(title: "结束这一轮", action: #selector(timerMenuEnd), keyEquivalent: "")
            end.target = self
            menu.addItem(end)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: timerButton.bounds.height + 6), in: timerButton)
    }

    @objc private func timerMenuStart(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int, let preset = FocusPreset(rawValue: raw) else { return }
        store.startFocus(preset)
    }

    @objc private func timerMenuPauseResume() {
        store.state.focusSession.phase == .paused ? store.resume() : store.pause()
    }

    @objc private func timerMenuEnd() {
        store.endSession()
    }

    private func drag(phase: NSEvent.Phase, point: NSPoint) {
        guard let window else { return }
        switch phase {
        case .began:
            // 拖动时先把挂着的卷轴收掉，避免卷轴留在原地悬空
            todoScroll?.close(animated: false)
            dragOrigin = window.frame.origin; dragMouseStart = point
        case .changed:
            guard let origin = dragOrigin, let start = dragMouseStart else { return }
            window.setFrameOrigin(NSPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y))
        case .ended: dragOrigin = nil; dragMouseStart = nil
        default: break
        }
    }

    private func refresh() {
        let value = store.buddyState
        if value != lastBuddyState {
            // 起身/完成用"整只小人跳一下"庆祝——比原地缩放醒目得多，
            // 且窗口坐标方向确定，不受 backing layer 坐标系翻转影响
            if value == .stood { celebrateHop(second: false) }
            if value == .done { celebrateHop(second: true) }
            lastBuddyState = value
        }
        buddy.state = value
        refreshChip()
    }

    private func refreshChip() {
        let text: String
        var emphasized = false
        switch store.buddyState {
        case .stood: text = "起身打卡 ✓"
        case .hydrated: text = "补水打卡 ✓"
        case .done: text = "搞定一件 🎉"
        case .water: text = "该喝水了 · 点我打卡"; emphasized = true
        case .tired: text = "坐久了 · 点我打卡"; emphasized = true
        case .focus: text = "专注中 · 还剩 \(max(1, (store.state.focusSession.remainingSeconds() + 59) / 60))m"
        case .rest: text = "休息中 · 喘口气"
        case .idle: text = ""
        }
        let session = store.state.focusSession
        statusChip.progress = [.focus, .break].contains(session.phase) && session.phaseDurationSeconds > 0
            ? 1 - CGFloat(session.remainingSeconds()) / CGFloat(session.phaseDurationSeconds)
            : nil
        statusChip.text = text
        statusChip.emphasized = emphasized
        statusChip.isHidden = isExpanded || text.isEmpty
    }

    /// 点提醒芯片 = 直接打卡，不需要打开工作台
    private func ackReminder() {
        switch store.buddyState {
        case .water: store.recordWater()
        case .tired: store.recordStand()
        default: break
        }
    }

    /// 小人原地起跳（带一点回弹落地）；second 为真时再补一小跳
    private func celebrateHop(second: Bool) {
        guard let window, window.isVisible, dragOrigin == nil else { return }
        let base = window.frame
        func hop(_ height: CGFloat, then: (() -> Void)? = nil) {
            var up = base
            up.origin.y += height
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(up, display: true)
            }) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.20
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    window.animator().setFrame(base, display: true)
                }) { then?() }
            }
        }
        // 姿势切换（站姿贴图）才是主角，窗口跳跃只做点缀，幅度收小
        hop(12) { if second { hop(7) } }
    }

    private func refreshPlaying() {
        let audio = AudioCoordinator.shared
        playingButton.isHidden = !isExpanded || audio.currentTitle == nil
        playingButton.title = audio.currentTitle.map { "♪ \($0) · 停" } ?? ""
    }

    private func updateClickThrough() {
        guard let window, window.isVisible, let root = window.contentView else { return }
        let local = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let interactive = [chatCard, buddy, toolbarCard, statusChip]
            .filter { !$0.isHidden }
            .contains { $0.frame.insetBy(dx: -4, dy: -4).contains(root.convert(local, from: nil)) }
        window.ignoresMouseEvents = !interactive
    }
}
