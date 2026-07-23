import AppKit

@MainActor
final class WorkbenchWindowController: NSWindowController {
    var onReturnToPet: (() -> Void)?
    var onOpenUnwind: (() -> Void)?

    private let store: AppStore
    private let phaseLabel = NSTextField.label("")
    private let timerLabel = NSTextField.label("25:00", font: .monospacedDigitSystemFont(ofSize: 38, weight: .semibold))
    private let taskField = NSTextField()
    private let estimate = NSPopUpButton()
    private let taskStack = NSStackView.vertical(spacing: 5)
    private let statsLabel = NSTextField.label("")
    private let controls = NSStackView.horizontal(spacing: 8)
    private var storeObserver: UUID?

    init(store: AppStore = .shared) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Unwind 工作台"
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
        let presetButtons = NSStackView.horizontal(spacing: 8, views: FocusPreset.allCases.map { preset in
            ActionButton("\(preset.rawValue)m") { [weak self] in self?.store.startFocus(preset) }
        })
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
        estimate.addItems(withTitles: ["25m", "50m", "90m"])
        estimate.selectItem(withTitle: "50m")
        let add = ActionButton("添加") { [weak self] in
            guard let self else { return }
            self.store.addTask(title: self.taskField.stringValue, minutes: Int(self.estimate.titleOfSelectedItem?.dropLast() ?? "50") ?? 50)
            self.taskField.stringValue = ""
        }
        let form = NSStackView.horizontal(spacing: 7, views: [taskField, estimate, add])
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
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
        let seconds = session.phase == .idle ? session.preset.rawValue * 60 : session.remainingSeconds()
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
            let meta = NSTextField.label("\(task.estimateMinutes) 分钟", font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
            let remove = ActionButton("×", bezelStyle: .inline) { [weak self] in self?.store.deleteTask(task.id) }
            let row = NSStackView.horizontal(spacing: 6, views: [check, select, meta, remove])
            row.distribution = .fill
            taskStack.addArrangedSubview(row)
        }
        let stats = store.dailyStats
        statsLabel.stringValue = "今日：\(stats.pomodoroCount) 番茄 · \(stats.focusMinutes) 分钟 · 完成 \(stats.tasksCompleted) · 喝水 \(stats.waterCount)"
    }
}
