import AppKit

@MainActor
final class UnwindWindowController: NSWindowController {
    private let backend: BackendClientProtocol
    private let audio = AudioCoordinator.shared
    private let ptt = PushToTalkClient()
    private let breathing = BreathingWindowController()
    private let call = CallWindowController()

    private let healthLabel = NSTextField.label("检测服务状态…", font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
    private let chatStack = NSStackView.vertical(spacing: 9)
    private let prompt = NSTextField()
    private let traceIntent = NSTextField.label("等待请求", color: .secondaryLabelColor)
    private let traceSkill = NSTextField.label("等待请求", color: .secondaryLabelColor)
    private let tracePlan = NSTextField.label("等待请求", color: .secondaryLabelColor)
    private let traceResult = NSTextField.label("等待请求", color: .secondaryLabelColor)
    private let skillStack = NSStackView.vertical(spacing: 7)
    private let playerBar = CardView(material: .hudWindow)
    private let playerTitle = NSTextField.label("", font: .systemFont(ofSize: 13, weight: .semibold))
    private let playerSubtitle = NSTextField.label("", font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
    private let playButton = ActionButton("▶") {}
    private let ripple = RippleView()
    private let speakButton = ActionButton("开口说话") {}
    private let pttButton = PressButton(title: "按住说话", target: nil, action: nil)
    private var currentUserText = ""
    private var chatTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var skills: [SkillDescriptor] = []
    private var speakReplies = true
    private var audioObservers: [UUID] = []

    init(backend: BackendClientProtocol = BackendClient.shared) {
        self.backend = backend
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1220, height: 800), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Unwind · 把压力，呼出去"
        window.backgroundColor = UnwindPalette.canvas
        window.minSize = NSSize(width: 980, height: 680)
        window.isReleasedWhenClosed = false
        buildUI()
        bind()
        Task { await loadInitialData() }
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let root = window?.contentView else { return }
        root.addSubview(ripple); pin(ripple, to: root)
        ripple.wantsLayer = true
        ripple.layer?.zPosition = -1

        let headline = NSTextField.label("把压力，呼出去。", font: .systemFont(ofSize: 28, weight: .bold))
        let breathe = ActionButton("呼吸 60 秒") { [weak self] in self?.breathing.start() }
        let scenarios = NSPopUpButton()
        scenarios.addItems(withTitles: ["情境演示", "刚连开 3 小时会", "周四晚 · 周报未交", "周报代写", "OKR 实据重构", "差旅报销流程"])
        scenarios.target = self; scenarios.action = #selector(runScenario(_:))
        let voiceCall = ActionButton("语音通话") { [weak self] in self?.call.start() }
        speakButton.actionHandler = { [weak self] in self?.toggleSpeak() }
        let header = NSStackView.horizontal(spacing: 8, views: [headline, healthLabel, speakButton, breathe, scenarios, voiceCall])
        header.distribution = .fillProportionally

        let chatColumn = buildChatColumn()
        let traceColumn = buildTraceColumn()
        let skillsColumn = buildSkillsColumn()
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(chatColumn)
        split.addArrangedSubview(traceColumn)
        split.addArrangedSubview(skillsColumn)
        chatColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 430).isActive = true
        traceColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 245).isActive = true
        skillsColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 245).isActive = true

        playButton.actionHandler = { [weak self] in self?.audio.toggle() }
        let playerText = NSStackView.vertical(spacing: 1, views: [playerTitle, playerSubtitle])
        let playerRow = NSStackView.horizontal(spacing: 10, views: [playButton, playerText])
        playerBar.addSubview(playerRow); pin(playerRow, to: playerBar, inset: 10)
        playerBar.isHidden = true

        let content = NSStackView.vertical(spacing: 12, views: [header, split, playerBar])
        content.distribution = .fill
        root.addSubview(content); pin(content, to: root, inset: 16)
        [header, split, playerBar].forEach {
            $0.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        header.heightAnchor.constraint(equalToConstant: 42).isActive = true
        playerBar.heightAnchor.constraint(equalToConstant: 54).isActive = true
        split.setContentHuggingPriority(.defaultLow, for: .vertical)
        split.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        split.heightAnchor.constraint(greaterThanOrEqualTo: content.heightAnchor, constant: -120).isActive = true
    }

    private func buildChatColumn() -> NSView {
        let card = CardView()
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true
        scroll.applyWarmBackground()
        chatStack.alignment = .leading
        scroll.documentView = chatStack
        chatStack.translatesAutoresizingMaskIntoConstraints = false
        chatStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        addMessage("assistant", "先坐一会儿。你可以告诉我现在的状态，也可以直接挑一个声音。")
        let chips = NSStackView.horizontal(spacing: 5)
        ["刚下线一个大版本，帮我放松", "夸夸我", "加一点雨声", "五分钟呼吸冥想", "给我安心签"].forEach { text in
            chips.addArrangedSubview(ActionButton(text) { [weak self] in self?.send(text) })
        }
        prompt.placeholderString = "用一句话描述你现在的状态或想听的内容…"
        prompt.applyWarmInputStyle()
        prompt.target = self; prompt.action = #selector(submitPrompt)
        pttButton.bezelStyle = .rounded
        let send = ActionButton("发送") { [weak self] in self?.send(self?.prompt.stringValue ?? "") }
        let inputRow = NSStackView.horizontal(spacing: 7, views: [prompt, pttButton, send])
        let stack = NSStackView.vertical(spacing: 10, views: [NSTextField.label("对话", font: .systemFont(ofSize: 16, weight: .semibold)), scroll, chips, inputRow])
        card.addSubview(stack); pin(stack, to: card, inset: 12)
        return card
    }

    private func buildTraceColumn() -> NSView {
        let card = CardView()
        let title = NSTextField.label("智能体决策轨迹", font: .systemFont(ofSize: 16, weight: .semibold))
        let traceCards = [
            traceCard("1  理解意图", traceIntent), traceCard("2  选择技能", traceSkill),
            traceCard("3  生成/工具计划", tracePlan), traceCard("4  执行结果", traceResult)
        ]
        let stack = NSStackView.vertical(spacing: 10, views: [title] + traceCards)
        traceCards.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        card.addSubview(stack); pin(stack, to: card, inset: 12)
        return card
    }

    private func traceCard(_ title: String, _ body: NSTextField) -> NSView {
        let card = CardView(material: .underWindowBackground)
        let stack = NSStackView.vertical(spacing: 5, views: [NSTextField.label(title, font: .systemFont(ofSize: 12, weight: .semibold)), body])
        card.addSubview(stack); pin(stack, to: card, inset: 9)
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        return card
    }

    private func buildSkillsColumn() -> NSView {
        let card = CardView()
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = skillStack
        scroll.applyWarmBackground()
        skillStack.translatesAutoresizingMaskIntoConstraints = false
        skillStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        let stack = NSStackView.vertical(spacing: 9, views: [NSTextField.label("技能矩阵", font: .systemFont(ofSize: 16, weight: .semibold)), scroll])
        card.addSubview(stack); pin(stack, to: card, inset: 12)
        return card
    }

    private func bind() {
        pttButton.onPress = { [weak self] in self?.startPTT() }
        pttButton.onRelease = { [weak self] in self?.ptt.endRecording(); self?.pttButton.title = "按住说话" }
        ptt.onUserText = { [weak self] text, _ in self?.addMessage("user", text) }
        ptt.onAssistantText = { [weak self] text in self?.addMessage("assistant", text) }
        ptt.onAsset = { [weak self] url, title in Task { try? await self?.audio.play(url: url, title: title, assetID: nil) } }
        ptt.onError = { [weak self] error in self?.addMessage("system", error) }
        audioObservers.append(audio.observePlayback { [weak self] playing, title in
            self?.playerBar.isHidden = title == nil
            self?.playerTitle.stringValue = title ?? ""
            self?.playButton.title = playing ? "❚❚" : "▶"
        })
        audioObservers.append(audio.observeLevels { [weak self] levels in self?.ripple.levels = levels })
        audioObservers.append(audio.observeSleepTimer { [weak self] seconds in
            guard let self else { return }
            playerSubtitle.stringValue = seconds.map { "定时 · \(String(format: "%02d:%02d", $0 / 60, $0 % 60))" } ?? ""
        })
    }

    @objc private func submitPrompt() { send(prompt.stringValue) }

    @objc private func runScenario(_ sender: NSPopUpButton) {
        defer { sender.selectItem(at: 0) }
        switch sender.indexOfSelectedItem {
        case 1: Task { await showNudge("post_meeting") }
        case 2: Task { await showNudge("weekly_due") }
        case 3: send("周报还没写，帮我搞定")
        case 4: send("这季度 OKR 感觉要完不成了")
        case 5: send("差旅报销流程怎么走？")
        default: break
        }
    }

    private func loadInitialData() async {
        do {
            let health = try await backend.health()
            healthLabel.stringValue = health.status == "ok" ? "● 后端正常 · Hermes \(health.hermes)" : "● 后端异常"
            healthLabel.textColor = health.status == "ok" ? .systemGreen : .systemRed
        } catch {
            healthLabel.stringValue = "● 后端未连接"
            healthLabel.textColor = .systemRed
        }
        do { skills = try await backend.skills(); renderSkills() }
        catch { skillStack.addArrangedSubview(NSTextField.label("技能列表加载失败", color: .secondaryLabelColor)) }
    }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return }
        currentUserText = text
        prompt.stringValue = ""
        addMessage("user", text)
        let thinking = addMessage("assistant", "Unwind 正在思考…")
        resetTrace()
        chatTask?.cancel(); pollTask?.cancel()
        chatTask = Task { [weak self, weak thinking] in
            guard let self else { return }
            do {
                let response = try await backend.chat(text, currentAssetID: audio.currentAssetID)
                thinking?.stringValue = response.reply ?? defaultReply(response.action)
                renderDecision(response)
                if speakReplies, let raw = response.replyAudioURL, let url = URL(string: raw) { await audio.playReply(url: url) }
                if let seconds = response.timerSeconds { audio.armSleepTimer(seconds: seconds, fade: response.fadeOut != false) }
                if let card = response.skillCard { renderSkillCard(card, response: response) }
                if response.selectedSkill == "comfort_card", let reply = response.reply { addComfortCard(reply) }
                switch response.action {
                case .playAsset:
                    if let asset = response.asset { try await play(asset) }
                case .generateJob:
                    if let id = response.jobID { pollTask = Task { await pollGeneration(id) } }
                case .remixCurrent:
                    if let asset = response.asset { try await play(asset) }
                    else if let id = response.remixJobID { pollTask = Task { await pollRemix(id) } }
                case .noMatch: await showRecommendations()
                default: break
                }
            } catch is CancellationError { }
            catch {
                thinking?.stringValue = "这次请求没有成功：\(error.localizedDescription)"
                traceResult.stringValue = "失败"
            }
        }
    }

    @discardableResult
    private func addMessage(_ role: String, _ text: String) -> NSTextField {
        let label = NSTextField.label(text, font: .systemFont(ofSize: 13))
        label.preferredMaxLayoutWidth = 390
        let card = CardView(material: role == "user" ? .selection : .contentBackground)
        card.addSubview(label); pin(label, to: card, inset: 9)
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 390).isActive = true
        card.widthAnchor.constraint(lessThanOrEqualToConstant: 410).isActive = true
        chatStack.addArrangedSubview(card)
        return label
    }

    private func renderDecision(_ response: ChatDecision) {
        traceIntent.stringValue = response.reasons.first ?? "已解析用户请求"
        traceSkill.stringValue = response.selectedSkill ?? response.action.rawValue
        if let directive = response.toolCalls.first(where: { $0.name != "hermes_agent" }) {
            tracePlan.stringValue = "\(directive.name)\n\(directive.reason ?? "")\n\(directive.latencyMS) ms"
        } else { tracePlan.stringValue = "以对话回应" }
        traceResult.stringValue = defaultReply(response.action)
    }

    private func resetTrace() {
        traceIntent.stringValue = "理解中…"; traceSkill.stringValue = "选择中…"; tracePlan.stringValue = "等待…"; traceResult.stringValue = "等待…"
    }

    private func defaultReply(_ action: ChatDecision.Action) -> String {
        switch action {
        case .playAsset: "找到适合你的声音，现在开始播放。"
        case .generateJob: "正在为你生成专属音频。"
        case .remixCurrent: "正在调整当前声音。"
        case .noMatch: "没有匹配到合适内容。"
        case .chat: "我在。"
        case .unknown: "收到。"
        }
    }

    private func play(_ asset: AudioAsset) async throws {
        guard let raw = asset.playbackURL, let url = URL(string: raw) else { return }
        try await audio.play(url: url, title: asset.title, assetID: asset.id)
        traceResult.stringValue = "已就绪，即刻播放"
    }

    private func pollGeneration(_ id: String) async {
        let deadline = Date.now.addingTimeInterval(240)
        while Date.now < deadline && !Task.isCancelled {
            do {
                let job = try await backend.generationJob(id: id)
                traceResult.stringValue = job.status == "queued" ? "排队中" : "生成中"
                if let directive = job.directive {
                    tracePlan.stringValue = ([directive.contentBrief] + directive.outline).filter { !$0.isEmpty }.joined(separator: "\n• ")
                }
                if job.status == "succeeded", let asset = job.asset { try await play(asset); return }
                if job.status == "failed" { addMessage("system", job.errorMessage ?? "生成没有成功"); await showRecommendations(); return }
            } catch { }
            try? await Task.sleep(for: .seconds(2))
        }
        if !Task.isCancelled { addMessage("system", "生成超时了") }
    }

    private func pollRemix(_ id: String) async {
        let deadline = Date.now.addingTimeInterval(90)
        while Date.now < deadline && !Task.isCancelled {
            if let job = try? await backend.remixJob(id: id) {
                traceResult.stringValue = "正在混音…"
                if job.status == "succeeded", let asset = job.outputAsset { try? await play(asset); return }
                if job.status == "failed" { addMessage("system", job.errorMessage ?? "混音没有成功"); return }
            }
            try? await Task.sleep(for: .seconds(2))
        }
        if !Task.isCancelled { addMessage("system", "混音超时了") }
    }

    private func showRecommendations() async {
        guard let values = try? await backend.recommendations(limit: 3) else { return }
        for recommendation in values {
            let asset = recommendation.asset
            let button = ActionButton("▶  \(asset.title)") { [weak self] in Task { try? await self?.play(asset) } }
            chatStack.addArrangedSubview(button)
        }
    }

    private func renderSkills() {
        skillStack.arrangedSubviews.forEach { skillStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let categories = [("onetool", "厂内能力"), ("ritual", "减压仪式"), ("sound", "声音引擎")]
        for (key, title) in categories {
            skillStack.addArrangedSubview(NSTextField.label(title, font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor))
            for skill in skills.filter({ $0.category == key }) {
                let indicator = skill.status == "live" ? "●" : skill.status == "demo" ? "◐" : "○"
                let button = ActionButton("\(indicator)  \(skill.label)", bezelStyle: .inline) { [weak self] in self?.run(skill) }
                button.alignment = .left; button.toolTip = skill.desc
                skillStack.addArrangedSubview(button)
            }
        }
    }

    private func run(_ skill: SkillDescriptor) {
        if skill.demoCall == true { call.start() }
        else if let scenario = skill.demoScenario { Task { await showNudge(scenario) } }
        else if let text = skill.demoSay { send(text) }
        else { addMessage("system", "\(skill.label)：\(skill.desc)") }
    }

    private func showNudge(_ scenario: String) async {
        guard let value = try? await backend.nudge(scenario: scenario) else { return }
        let alert = NSAlert(); alert.messageText = "\(value.icon)  \(value.title)"; alert.informativeText = value.text
        alert.addButton(withTitle: value.actionLabel); alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            if value.action == "breathe" { breathing.start() }
            else if let text = value.actionText { send(text) }
        }
    }

    private func renderSkillCard(_ value: JSONValue, response: ChatDecision) {
        guard let card = value.objectValue, let type = card["type"]?.stringValue else { return }
        let container = CardView(material: .underWindowBackground)
        let stack = NSStackView.vertical(spacing: 6)
        container.addSubview(stack); pin(stack, to: container, inset: 10)
        if type == "weekly_draft" {
            stack.addArrangedSubview(NSTextField.label(card["title"]?.stringValue ?? "本周周报 · 草稿", font: .systemFont(ofSize: 14, weight: .semibold)))
            for row in card["rows"]?.arrayValue ?? [] {
                guard let object = row.objectValue else { continue }
                stack.addArrangedSubview(NSTextField.label(object["section"]?.stringValue ?? "", font: .systemFont(ofSize: 12, weight: .semibold)))
                for item in object["items"]?.arrayValue ?? [] { stack.addArrangedSubview(NSTextField.label("• \(item.stringValue ?? "")")) }
            }
        } else if type == "okr_progress" {
            stack.addArrangedSubview(NSTextField.label(card["objective"]?.stringValue ?? "OKR 实况", font: .systemFont(ofSize: 14, weight: .semibold)))
            for kr in card["krs"]?.arrayValue ?? [] {
                guard let object = kr.objectValue else { continue }
                stack.addArrangedSubview(NSTextField.label("\(object["name"]?.stringValue ?? "KR") · \(Int(object["pct"]?.numberValue ?? 0))%"))
            }
            if let insight = card["insight"]?.stringValue { stack.addArrangedSubview(NSTextField.label(insight, color: .secondaryLabelColor)) }
        } else if type == "ritual_receipt" {
            stack.addArrangedSubview(NSTextField.label(card["title"]?.stringValue ?? "已记录", font: .systemFont(ofSize: 14, weight: .semibold)))
            for line in card["lines"]?.arrayValue ?? [] { stack.addArrangedSubview(NSTextField.label(line.stringValue ?? "")) }
            if card["skill"]?.stringValue == "worry_parking" { animateWorry(text: card["worry_text"]?.stringValue ?? currentUserText) }
        } else if ["neisou_answer", "neisou_results"].contains(type) {
            stack.addArrangedSubview(NSTextField.label("内搜 · 确定性答案", font: .systemFont(ofSize: 14, weight: .semibold)))
            if let answer = card["answer"]?.stringValue { stack.addArrangedSubview(NSTextField.label(answer)) }
            for item in card["results"]?.arrayValue ?? [] {
                if let object = item.objectValue { stack.addArrangedSubview(NSTextField.label("• \(object["title"]?.stringValue ?? "")\n\(object["snippet"]?.stringValue ?? "")")) }
            }
        } else { return }
        chatStack.addArrangedSubview(container)
    }

    private func addComfortCard(_ text: String) {
        let button = ActionButton("保存安心签") { [weak self] in ComfortCardRenderer.save(text: text, from: self?.window) }
        let stack = NSStackView.vertical(spacing: 7, views: [NSTextField.label(text, font: .systemFont(ofSize: 15, weight: .medium)), button])
        let card = CardView(); card.addSubview(stack); pin(stack, to: card, inset: 12)
        chatStack.addArrangedSubview(card)
    }

    private func animateWorry(text: String) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let root = window?.contentView else { return }
        let note = NSTextField.label(text, font: .systemFont(ofSize: 18, weight: .medium))
        note.alignment = .center; note.wantsLayer = true; note.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.9).cgColor; note.layer?.cornerRadius = 8
        root.addSubview(note); note.frame = NSRect(x: root.bounds.midX - 150, y: root.bounds.midY - 60, width: 300, height: 120)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.5; note.animator().alphaValue = 0; note.animator().frame = NSRect(x: root.bounds.midX, y: root.bounds.midY, width: 1, height: 1)
        } completionHandler: { Task { @MainActor in note.removeFromSuperview() } }
    }

    private func toggleSpeak() {
        speakReplies.toggle(); speakButton.title = speakReplies ? "开口说话" : "静音回复"
    }

    private func startPTT() {
        do { try ptt.startRecording(); pttButton.title = "松开结束" }
        catch { addMessage("system", error.localizedDescription) }
    }
}
