import AppKit

@MainActor
final class WorkbenchWindowController: NSWindowController {
    var onReturnToPet: (() -> Void)?
    var onOpenUnwind: (() -> Void)?

    private let store: AppStore
    private let phaseLabel = NSTextField.label("")
    private let timerLabel = NSTextField.label("25:00", font: .monospacedDigitSystemFont(ofSize: 38, weight: .semibold))
    private let taskField = NSTextField()
    private let taskStack = NSStackView.vertical(spacing: 5)
    private let statsLabel = NSTextField.label("")
    private let controls = NSStackView.horizontal(spacing: 8)
    private var storeObserver: UUID?
    private var customButton: ActionButton!
    private var customPopover: NSPopover?

    init(store: AppStore = .shared) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "工作台"
        window.backgroundColor = UnwindPalette.canvas
        window.minSize = NSSize(width: 430, height: 620)
        window.isReleasedWhenClosed = false
        buildUI()
        storeObserver = store.observeState { [weak self] _ in self?.refresh() }
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let root = window?.contentView else { return }
        let title = NSTextField.label("打工小人", font: .systemFont(ofSize: 22, weight: .bold))
        let subtitle = NSTextField.label("陪你分段工作，顺手照顾自己。", color: .secondaryLabelColor)
        let headerButtons = NSStackView.horizontal(views: [
            ActionButton("喘口气") { [weak self] in self?.onOpenUnwind?() },
            ActionButton("回到桌宠") { [weak self] in self?.onReturnToPet?() }
        ])
        let header = NSStackView.horizontal(spacing: 12, views: [NSStackView.vertical(spacing: 2, views: [title, subtitle]), headerButtons])
        header.distribution = .fillProportionally

        let timerCard = CardView()
        var presetViews: [NSView] = FocusPreset.allCases.map { preset in
            ActionButton("\(preset.rawValue)m") { [weak self] in self?.store.startFocus(preset) }
        }
        customButton = ActionButton("自定义") { [weak self] in self?.showCustomDurationPopover() }
        presetViews.append(customButton)
        let presetButtons = NSStackView.horizontal(spacing: 8, views: presetViews)
        let pause = ActionButton("暂停/继续") { [weak self] in
            guard let self else { return }
            self.store.state.focusSession.phase == .paused ? self.store.resume() : self.store.pause()
        }
        let end = ActionButton("结束") { [weak self] in self?.store.endSession() }
        controls.addArrangedSubview(presetButtons)
        controls.addArrangedSubview(pause)
        controls.addArrangedSubview(end)
        let timerStack = NSStackView.vertical(spacing: 8, views: [phaseLabel, timerLabel, controls])
        timerStack.alignment = .centerX
        timerCard.addSubview(timerStack); pin(timerStack, to: timerCard, inset: 14)

        let todoCard = CardView()
        taskField.placeholderString = "写下一个任务"
        taskField.applyWarmInputStyle()
        let add = ActionButton("添加") { [weak self] in
            guard let self else { return }
            self.store.addTask(title: self.taskField.stringValue)
            self.taskField.stringValue = ""
        }
        let form = NSStackView.horizontal(spacing: 7, views: [taskField, add])
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.applyWarmBackground()
        scroll.documentView = taskStack
        taskStack.translatesAutoresizingMaskIntoConstraints = false
        taskStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        let todo = NSStackView.vertical(spacing: 10, views: [NSTextField.label("今日 Todo", font: .systemFont(ofSize: 15, weight: .semibold)), form, scroll])
        form.widthAnchor.constraint(equalTo: todo.widthAnchor).isActive = true
        scroll.widthAnchor.constraint(equalTo: todo.widthAnchor).isActive = true
        todoCard.addSubview(todo); pin(todo, to: todoCard, inset: 14)

        let health = NSStackView.horizontal(spacing: 8, views: [
            ActionButton("我起来了") { [weak self] in self?.store.recordStand() },
            ActionButton("喝水了") { [weak self] in self?.store.recordWater() },
            ActionButton("归零") { [weak self] in self?.store.resetTodayStats() }, statsLabel
        ])

        let content = NSStackView.vertical(spacing: 14, views: [header, timerCard, todoCard, health])
        root.addSubview(content); pin(content, to: root, inset: 18)
        [header, timerCard, todoCard, health].forEach {
            $0.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        timerCard.heightAnchor.constraint(equalToConstant: 150).isActive = true
        todoCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
    }

    private func refresh() {
        let session = store.state.focusSession
        let seconds: Int
        if session.phase == .idle {
            seconds = session.duration.focusSeconds
        } else {
            seconds = session.remainingSeconds()
        }
        timerLabel.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        phaseLabel.stringValue = [
            SessionPhase.idle: "准备开始", .focus: "专注中", .break: "休息中", .paused: "已暂停"
        ][session.phase] ?? ""
        taskStack.arrangedSubviews.forEach { taskStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        if store.sortedTasks.isEmpty { taskStack.addArrangedSubview(NSTextField.label("还没有任务，先给小人安排点活。", color: .secondaryLabelColor)) }
        for task in store.sortedTasks {
            let check = ActionButton(task.done ? "✓" : "○", bezelStyle: .inline) { [weak self] in self?.store.completeTask(task.id) }
            let select = ActionButton(task.title, bezelStyle: .inline) { [weak self] in self?.store.selectTask(task.id) }
            select.alignment = .left
            select.isEnabled = !task.done
            let remove = ActionButton("×", bezelStyle: .inline) { [weak self] in self?.store.deleteTask(task.id) }
            let row = NSStackView.horizontal(spacing: 6, views: [check, select, remove])
            row.distribution = .fill
            taskStack.addArrangedSubview(row)
        }
        let stats = store.dailyStats
        statsLabel.stringValue = "今日：\(stats.pomodoroCount) 番茄 · \(stats.focusMinutes) 分钟 · 完成 \(stats.tasksCompleted) · 喝水 \(stats.waterCount)"
    }

    private func showCustomDurationPopover() {
        customPopover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 230, height: 130)

        let vc = NSViewController()
        let view = NSView(frame: NSRect(origin: .zero, size: popover.contentSize))
        vc.view = view

        let intFormatter = NumberFormatter()
        intFormatter.minimum = 1
        intFormatter.maximum = 240
        intFormatter.allowsFloats = false

        let focusLabel = NSTextField.label("专注:")
        let focusField = NSTextField()
        focusField.formatter = intFormatter
        focusField.integerValue = store.state.settings.lastCustomFocusMinutes
        focusField.applyWarmInputStyle()
        focusField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        let focusUnit = NSTextField.label("分钟")

        let breakLabel = NSTextField.label("休息:")
        let breakField = NSTextField()
        breakField.formatter = intFormatter
        breakField.integerValue = store.state.settings.lastCustomBreakMinutes
        breakField.applyWarmInputStyle()
        breakField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        let breakUnit = NSTextField.label("分钟")

        let startBtn = ActionButton("开始") { [weak self, weak popover] in
            let focus = max(1, min(240, focusField.integerValue))
            let brk = max(1, min(240, breakField.integerValue))
            self?.store.startCustomFocus(focusMinutes: focus, breakMinutes: brk)
            popover?.close()
        }

        let focusRow = NSStackView.horizontal(spacing: 6, views: [focusLabel, focusField, focusUnit])
        let breakRow = NSStackView.horizontal(spacing: 6, views: [breakLabel, breakField, breakUnit])
        let stack = NSStackView.vertical(spacing: 10, views: [focusRow, breakRow, startBtn])
        stack.alignment = .centerX
        view.addSubview(stack)
        pin(stack, to: view, inset: 14)

        popover.contentViewController = vc
        popover.show(relativeTo: customButton.bounds, of: customButton, preferredEdge: .maxY)
        customPopover = popover
    }
}
