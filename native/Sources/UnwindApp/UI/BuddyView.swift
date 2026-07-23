import AppKit

enum BuddyGender: String, CaseIterable {
    case male
    case female

    var title: String {
        switch self {
        case .male: "男生"
        case .female: "女生"
        }
    }
}

final class BuddyView: NSView {
    var state: BuddyState = .idle {
        didSet {
            guard oldValue != state else { return }
            needsDisplay = true
            applyMotion(entering: state)
        }
    }
    var gender: BuddyGender = .male { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    var onDrag: ((NSEvent.Phase, NSPoint) -> Void)?
    var onGenderChange: ((BuddyGender) -> Void)?
    private var downPoint: NSPoint?
    private var dragged = false
    private var lastMotionSize: CGSize = .zero
    private lazy var maleImage = Self.loadImage(named: "buddy-male")
    private lazy var femaleImage = Self.loadImage(named: "buddy-female")
    /// 状态专属贴图缓存；value 为 nil 表示查过且不存在，避免反复走文件系统
    private var stateImageCache: [String: NSImage?] = [:]
    /// 状态贴图的自动裁剪框缓存（按 alpha 包围盒算一次）
    private var stateSourceRects: [String: NSRect?] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    // 动作关键帧里的支点坐标依赖 bounds，尺寸一变（含初次布局）都要重挂。
    // 本视图用手动 frame 布局，auto-layout 的 layout() 不可靠，改挂这两个钩子。
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize != lastMotionSize {
            lastMotionSize = newSize
            applyMotion(entering: state)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { applyMotion(entering: state) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 状态专属贴图优先（如 buddy-male-stand.png），没有就退回基础姿势。
        // 状态贴图不假设画布布局：按 alpha 边界自动裁剪（AI 生成的素材
        // 人物位置/大小各不相同，写死裁剪框会切头）。
        let image: NSImage
        let sourceRect: NSRect
        if let sprite = stateSprite(for: state) {
            (image, sourceRect) = sprite
        } else if let base = gender == .male ? maleImage : femaleImage {
            image = base
            // Crop only transparent padding, with a 12px safety margin on every
            // side, before scaling the complete opaque character into the pet
            // area. This avoids the canvas margins making the artwork look cut off.
            sourceRect = gender == .male
                ? NSRect(x: 200, y: 142, width: 718, height: 718)
                : NSRect(x: 208, y: 146, width: 718, height: 718)
        } else {
            return
        }
        image.draw(
            // A square destination intentionally scales the entire supplied
            // character to the desktop-pet target, without clipping it.
            in: bounds.insetBy(dx: 1, dy: 1),
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = NSEvent.mouseLocation
        dragged = false
        onDrag?(.began, NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint else { return }
        let point = NSEvent.mouseLocation
        if abs(point.x - downPoint.x) + abs(point.y - downPoint.y) >= 5 { dragged = true }
        onDrag?(.changed, point)
    }

    override func mouseUp(with event: NSEvent) {
        onDrag?(.ended, NSEvent.mouseLocation)
        if !dragged { onClick?() }
        downPoint = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        for value in BuddyGender.allCases {
            let item = NSMenuItem(title: value.title, action: #selector(selectGender(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value.rawValue
            item.state = value == gender ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }

    @objc private func selectGender(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let value = BuddyGender(rawValue: rawValue) else { return }
        gender = value
        onGenderChange?(value)
    }

    private static func loadImage(named name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        var sourceRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { sourceRoot.deleteLastPathComponent() }
        return NSImage(contentsOf: sourceRoot.appendingPathComponent("Resources/\(name).png"))
    }

    /// 按状态找专属贴图：起身/休息用站姿、疲惫瘫姿、口渴、庆祝。
    /// 只是"槽位"——素材没到位时返回 nil，一切照旧用基础姿势 + 动作系统。
    private func stateSprite(for state: BuddyState) -> (image: NSImage, source: NSRect)? {
        let suffix: String?
        switch state {
        case .stood, .rest: suffix = "stand"
        case .tired: suffix = "tired"
        case .water: suffix = "water"
        case .done, .hydrated: suffix = "happy"
        case .idle, .focus: suffix = nil
        }
        guard let suffix else { return nil }
        let name = "buddy-\(gender.rawValue)-\(suffix)"
        if stateImageCache[name] == nil {
            stateImageCache[name] = Self.loadImage(named: name)
        }
        guard let image = stateImageCache[name] ?? nil else { return nil }
        if stateSourceRects[name] == nil {
            stateSourceRects[name] = Self.squareContentRect(of: image)
        }
        guard let source = stateSourceRects[name] ?? nil else { return nil }
        return (image, source)
    }

    /// 扫 alpha 求人物的不透明包围盒，加 12px 余量后扩成正方形（绘制目标是
    /// 正方形，非正方形源会拉伸变形），并夹回画布内。隔 2px 采样，误差远小于余量。
    private static func squareContentRect(of image: NSImage) -> NSRect? {
        var proposed = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        guard let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        let step = 2
        var row = 0
        while row < height {
            var col = 0
            while col < width {
                if pixels[(row * width + col) * 4 + 3] > 16 {
                    if col < minX { minX = col }
                    if col > maxX { maxX = col }
                    if row < minY { minY = row }
                    if row > maxY { maxY = row }
                }
                col += step
            }
            row += step
        }
        guard maxX >= 0 else { return nil }
        // 位图行 0 在顶部，而 draw(from:) 的源矩形原点在左下，翻转 y
        var box = NSRect(
            x: CGFloat(minX),
            y: CGFloat(height - 1 - maxY),
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        ).insetBy(dx: -12, dy: -12)
        let side = min(max(box.width, box.height), CGFloat(min(width, height)))
        box = NSRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side)
        box.origin.x = min(max(box.origin.x, 0), CGFloat(width) - side)
        box.origin.y = min(max(box.origin.y, 0), CGFloat(height) - side)
        return box
    }

    // MARK: - 状态动作系统
    //
    // 贴图是单一姿势，小人的"身体语言"全靠 transform：每个状态一个常驻
    // 小动作（呼吸/摇摆/瘫喘），切换状态时再叠一段一次性入场过渡（起身
    // 弹跳、瘫下去的下沉），避免"状态一变画面瞬间跳变"的生硬感。
    //
    // 只用绕视图中心的 scale/rotate，不用位移：AppKit 托管的 backing layer
    // 坐标系上下方向不可靠，位移动画有方向翻转风险，缩放/旋转则无所谓。

    private func applyMotion(entering value: BuddyState) {
        guard let layer, bounds.width > 1 else { return }
        layer.removeAnimation(forKey: "buddy.entrance")
        layer.removeAnimation(forKey: "buddy.loop")
        // 桌宠的入场过渡是它唯一的"身体语言"，减弱动态效果时也保留
        // （短促且有含义）；只有常驻循环（呼吸/摇摆）遵从系统设置关掉。
        let entranceDuration = addEntrance(for: value, to: layer)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        addLoop(for: value, to: layer, delay: entranceDuration)
    }

    /// 绕视图中心组合出一帧姿势（AppKit 会把 layer 的 anchorPoint 钉在原点，
    /// 所以每帧自带"绕中心变换"的平移补偿）。
    private func pose(scaleX sx: CGFloat = 1, scaleY sy: CGFloat = 1, rotation: CGFloat = 0) -> CATransform3D {
        let pivot = CGPoint(x: bounds.midX, y: bounds.midY)
        var t = CATransform3DMakeTranslation(pivot.x, pivot.y, 0)
        t = CATransform3DRotate(t, rotation, 0, 0, 1)
        t = CATransform3DScale(t, sx, sy, 1)
        return CATransform3DTranslate(t, -pivot.x, -pivot.y, 0)
    }

    /// 瘫倒程度 k（0~1.1）：歪头 + 塌腰的组合姿势
    private func sag(_ k: CGFloat) -> CATransform3D {
        pose(scaleX: 1 + 0.012 * k, scaleY: 1 - 0.03 * k, rotation: 0.075 * k)
    }

    /// 返回入场动画时长（无入场时为 0），常驻循环等它播完再开始
    private func addEntrance(for value: BuddyState, to layer: CALayer) -> CFTimeInterval {
        let frames: [CATransform3D]
        let duration: CFTimeInterval
        switch value {
        case .stood:
            // 起身：先蹲下蓄力，再弹起来带一点回弹——"我起来了"的过渡动作
            frames = [
                pose(),
                pose(scaleX: 1.08, scaleY: 0.86),
                pose(scaleX: 0.94, scaleY: 1.11),
                pose(scaleX: 1.03, scaleY: 0.96),
                pose(scaleX: 0.99, scaleY: 1.02),
                pose()
            ]
            duration = 0.85
        case .done:
            // 任务完成：连蹦两下
            frames = [
                pose(),
                pose(scaleX: 1.06, scaleY: 0.90), pose(scaleX: 0.96, scaleY: 1.08),
                pose(scaleX: 1.05, scaleY: 0.92), pose(scaleX: 0.97, scaleY: 1.06),
                pose()
            ]
            duration = 1.0
        case .hydrated:
            // 喝完水：满足地左右摆两下
            frames = [pose(), pose(rotation: 0.07), pose(rotation: -0.07), pose(rotation: 0.04), pose()]
            duration = 0.7
        case .tired:
            // 累了：慢慢瘫下去，而不是瞬间歪掉
            frames = [pose(), sag(0.9)]
            duration = 0.5
        case .water:
            // 口渴提醒：先晃两下把注意力抓过来
            frames = [pose(), pose(rotation: -0.06), pose(rotation: 0.06), pose(rotation: -0.04), pose()]
            duration = 0.6
        case .idle, .focus, .rest:
            return 0
        }
        let anim = CAKeyframeAnimation(keyPath: "transform")
        anim.values = frames.map { NSValue(caTransform3D: $0) }
        anim.duration = duration
        anim.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: max(frames.count - 1, 1))
        layer.add(anim, forKey: "buddy.entrance")
        return duration
    }

    private func addLoop(for value: BuddyState, to layer: CALayer, delay: CFTimeInterval) {
        let from: CATransform3D
        let to: CATransform3D
        let halfCycle: CFTimeInterval
        switch value {
        case .idle:
            from = pose(); to = pose(scaleX: 1.012, scaleY: 1.025); halfCycle = 1.7   // 慢呼吸
        case .focus:
            from = pose(); to = pose(scaleX: 1.008, scaleY: 1.016); halfCycle = 1.0   // 干活时呼吸更快更浅
        case .rest:
            from = pose(rotation: -0.024); to = pose(rotation: 0.024); halfCycle = 1.4 // 舒展摇摆
        case .tired:
            from = sag(0.9); to = sag(1.1); halfCycle = 1.3                            // 瘫着喘
        case .water:
            from = pose(rotation: -0.045); to = pose(rotation: 0.045); halfCycle = 0.55 // 口渴小幅扭动
        case .done, .stood, .hydrated:
            from = pose(); to = pose(scaleX: 1.014, scaleY: 1.03); halfCycle = 0.9    // 庆祝后的轻快呼吸
        }
        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = NSValue(caTransform3D: from)
        anim.toValue = NSValue(caTransform3D: to)
        anim.duration = halfCycle
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.beginTime = CACurrentMediaTime() + delay
        layer.add(anim, forKey: "buddy.loop")
    }
}
