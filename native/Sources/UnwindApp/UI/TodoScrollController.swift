import AppKit

/// 挂轴式今日待办：点桌宠工具条的"待办"图标，从按钮条下方像卷轴一样向下
/// 舒展开（顶轴钉在按钮条下沿，纸面和底轴向下滑出）。小人贴近屏幕底部、
/// 下方铺不开时，自动翻到小人上方展开。
/// 只做"看一眼 + 勾完成"，添加/删除等重操作仍去工作台。

/// 卷轴横杆：木色胶囊 + 深棕勾边
private final class RodView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rod = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        UnwindPalette.wood.setFill()
        rod.fill()
        rod.lineWidth = 1.5
        UnwindPalette.woodDark.setStroke()
        rod.stroke()
    }
}

/// 纸面：暖纸底 + 左右描边（上下边被横杆压住，不画）
private final class PaperView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        UnwindPalette.surface.setFill()
        bounds.fill()
        UnwindPalette.border.withAlphaComponent(0.65).setFill()
        NSRect(x: 0, y: 0, width: 1.5, height: bounds.height).fill()
        NSRect(x: bounds.width - 1.5, y: 0, width: 1.5, height: bounds.height).fill()
    }
}

@MainActor
final class TodoScrollController: NSWindowController {
    var onOpenWorkbench: (() -> Void)?

    private let store: AppStore
    private let paper = PaperView(frame: .zero)
    private let topRod = RodView(frame: .zero)
    private let bottomRod = RodView(frame: .zero)
    private let rowsStack = NSStackView.vertical(spacing: 4)
    private var storeObserver: UUID?
    private var isOpen = false
    private var fullHeight: CGFloat = 160
    /// 展开期间固定不动的顶沿（屏幕坐标）与横向位置
    private var topEdgeY: CGFloat = 0
    private var anchorX: CGFloat = 0
    /// 本次展开可用的最大高度（按屏幕空间算，重建行时约束行数用）
    private var maxHeightBudget: CGFloat = 400

    private let scrollWidth: CGFloat = 232
    private let rodHeight: CGFloat = 14
    /// 收拢态高度：两根横杆叠在一起
    private let rolledHeight: CGFloat = 30
    /// 展开动画能成立的最小高度，低于它就换方向
    private let minUseful: CGFloat = 150

    init(store: AppStore = .shared) {
        self.store = store
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: scrollWidth, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        super.init(window: panel)
        buildUI()
        storeObserver = store.observeState { [weak self] _ in
            guard let self, self.isOpen else { return }
            self.rebuildRows()
            self.animate(toHeight: self.fullHeight)
        }
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let root = window?.contentView else { return }
        root.wantsLayer = true
        root.layer?.masksToBounds = true

        // 纸面/横杆用钉边自适应：顶轴钉顶、底轴钉底、纸面撑中间——
        // 窗口高度动画时底轴跟着下沿走，正好是"卷轴展开"的画面
        let width = scrollWidth
        paper.frame = NSRect(x: 6, y: rodHeight / 2, width: width - 12, height: rolledHeight - rodHeight)
        paper.autoresizingMask = [.height]
        topRod.frame = NSRect(x: 0, y: rolledHeight - rodHeight, width: width, height: rodHeight)
        topRod.autoresizingMask = [.minYMargin]
        bottomRod.frame = NSRect(x: 0, y: 0, width: width, height: rodHeight)
        bottomRod.autoresizingMask = [.maxYMargin]
        root.addSubview(paper)

        // 行内容用约束钉在窗口"顶部"，展开时纸面从它身后长出来，
        // 收起时被窗口裁掉（比手算 frame + autoresizing 可靠）
        root.addSubview(rowsStack)
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.alignment = .leading
        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: root.topAnchor, constant: rodHeight + 10),
            rowsStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            rowsStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18)
        ])

        root.addSubview(topRod)
        root.addSubview(bottomRod)
    }

    /// 首选挂在图标条正下方向下展开；下方铺不开时翻到小人窗口上方
    func toggle(below toolbarFrame: NSRect, fallbackAbove petFrame: NSRect) {
        if isOpen {
            close(animated: true)
        } else {
            open(below: toolbarFrame, fallbackAbove: petFrame)
        }
    }

    private func open(below toolbarFrame: NSRect, fallbackAbove petFrame: NSRect) {
        guard let window else { return }
        let area = (NSScreen.screens.first(where: { $0.frame.intersects(petFrame) }) ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let spaceBelow = toolbarFrame.minY - area.minY - 12
        let spaceAbove = area.maxY - petFrame.maxY - 12
        let opensDownward = spaceBelow >= minUseful || spaceBelow >= spaceAbove
        maxHeightBudget = min(max(opensDownward ? spaceBelow : spaceAbove, minUseful), 420)

        rebuildRows()

        anchorX = min(max(toolbarFrame.midX - scrollWidth / 2, area.minX + 8), area.maxX - scrollWidth - 8)
        topEdgeY = opensDownward
            ? toolbarFrame.minY + 2
            : min(petFrame.maxY + 6 + fullHeight, area.maxY - 8)

        window.setFrame(NSRect(x: anchorX, y: topEdgeY - rolledHeight, width: scrollWidth, height: rolledHeight), display: true)
        window.orderFront(nil)
        isOpen = true
        animate(toHeight: fullHeight)
    }

    func close(animated: Bool) {
        guard let window, isOpen else { return }
        isOpen = false
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().setFrame(
                    NSRect(x: anchorX, y: topEdgeY - rolledHeight, width: scrollWidth, height: rolledHeight),
                    display: true
                )
            }) { [weak window] in window?.orderOut(nil) }
        } else {
            window.orderOut(nil)
        }
    }

    private func animate(toHeight height: CGFloat) {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(
                NSRect(x: anchorX, y: topEdgeY - height, width: scrollWidth, height: height),
                display: true
            )
        }
    }

    private func rebuildRows() {
        rowsStack.arrangedSubviews.forEach { rowsStack.removeArrangedSubview($0); $0.removeFromSuperview() }

        let title = NSTextField.label("今日待办", font: .systemFont(ofSize: 11, weight: .semibold), color: UnwindPalette.woodDark)
        rowsStack.addArrangedSubview(title)

        // 行数按本次可用高度动态适配：卷轴之外的固定开销（横杆/边距/标题/底部入口）
        // 大约 100pt，每行约 26pt，放不下的收进"…还有 N 件"
        let chrome: CGFloat = 100
        let rowHeight: CGFloat = 26
        let capacity = max(1, Int((maxHeightBudget - chrome) / rowHeight))

        let tasks = store.sortedTasks
        if tasks.isEmpty {
            rowsStack.addArrangedSubview(NSTextField.label("今天还没安排任务", font: .systemFont(ofSize: 12), color: .secondaryLabelColor))
        }
        let shown = tasks.prefix(capacity)
        for task in shown {
            let check = ActionButton(task.done ? "✓" : "○", bezelStyle: .inline) { [weak self] in
                guard !task.done else { return }
                self?.store.completeTask(task.id)
            }
            let label = NSTextField.label(
                task.title,
                font: .systemFont(ofSize: 12),
                color: task.done ? .secondaryLabelColor : UnwindPalette.woodDark
            )
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            let row = NSStackView.horizontal(spacing: 5, views: [check, label])
            rowsStack.addArrangedSubview(row)
        }
        if tasks.count > shown.count {
            rowsStack.addArrangedSubview(NSTextField.label("…还有 \(tasks.count - shown.count) 件", font: .systemFont(ofSize: 11), color: .secondaryLabelColor))
        }

        let workbench = ActionButton("去工作台安排 →", bezelStyle: .inline) { [weak self] in
            self?.close(animated: true)
            self?.onOpenWorkbench?()
        }
        rowsStack.addArrangedSubview(workbench)

        rowsStack.layoutSubtreeIfNeeded()
        fullHeight = min(max(rowsStack.fittingSize.height + rodHeight + 10 + rodHeight + 10, 120), maxHeightBudget)
    }
}
