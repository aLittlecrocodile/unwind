import Foundation

@MainActor
final class AppStore {
    static let shared = AppStore()

    private(set) var state: AppState
    private var timer: Timer?
    private var transientState: BuddyState?
    private var stateObservers: [UUID: (AppState) -> Void] = [:]
    private var buddyStateObservers: [UUID: (BuddyState) -> Void] = [:]
    var onFocusCompleted: (() -> Void)?
    var onBreakCompleted: (() -> Void)?
    var now: () -> Date = { .now }

    init(state: AppState? = nil) {
        self.state = state ?? Self.load()
        startTicker()
        Self.startDebugChannel()
    }

    // 本地调试/演示通道：shell 里发分布式通知即可触发状态动作，
    // 驱动小人的动画和提醒（自动化测试、上台前彩排提醒场景都用它）。
    // 用法：
    //   osascript -l JavaScript -e 'ObjC.import("Foundation");
    //     $.NSDistributedNotificationCenter.defaultCenter
    //       .postNotificationNameObjectUserInfoDeliverImmediately(
    //         "com.unwind.native.debug", null, $({action:"stand"}), true)'
    // 支持 action：stand / water / done / thirst（强制口渴提醒）/ sit（强制久坐提醒）
    private static func startDebugChannel() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.unwind.native.debug"), object: nil, queue: nil
        ) { note in
            let action = (note.userInfo?["action"] as? String) ?? ""
            Task { @MainActor in AppStore.shared.handleDebugAction(action) }
        }
    }

    func handleDebugAction(_ action: String) {
        switch action {
        case "stand": recordStand()
        case "water": recordWater()
        case "done": setTransient(.done)
        case "thirst":
            state.health.lastWaterAt = now().addingTimeInterval(-4000)
            changed()
        case "sit":
            state.health.consecutiveSitFocusBlocks = 2
            changed()
        default: break
        }
    }

    var currentTask: TaskItem? { state.tasks.first { $0.id == state.focusSession.taskID } }

    var sortedTasks: [TaskItem] {
        state.tasks.sorted {
            if $0.done != $1.done { return !$0.done }
            return $0.createdAt < $1.createdAt
        }
    }

    var buddyState: BuddyState {
        if let transientState { return transientState }
        if state.health.waterDue(at: now()) { return .water }
        if state.health.tiredDue { return .tired }
        switch state.focusSession.phase {
        case .focus: return .focus
        case .break: return .rest
        default: return .idle
        }
    }

    var dailyStats: DailyStats {
        let calendar = Calendar.current
        let day = now()
        let blocks = state.focusBlocks.filter { calendar.isDate($0.completedAt, inSameDayAs: day) }
        return DailyStats(
            pomodoroCount: blocks.count,
            focusMinutes: blocks.reduce(0) { $0 + $1.effectiveMinutes },
            tasksCompleted: state.tasks.filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }.count,
            waterCount: state.waterLogs.filter { calendar.isDate($0, inSameDayAs: day) }.count
        )
    }

    @discardableResult
    func observeState(_ observer: @escaping (AppState) -> Void) -> UUID {
        let id = UUID()
        stateObservers[id] = observer
        observer(state)
        return id
    }

    @discardableResult
    func observeBuddyState(_ observer: @escaping (BuddyState) -> Void) -> UUID {
        let id = UUID()
        buddyStateObservers[id] = observer
        observer(buddyState)
        return id
    }

    func removeObserver(_ id: UUID) {
        stateObservers[id] = nil
        buddyStateObservers[id] = nil
    }

    func addTask(title: String) {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Keep the persisted field for compatibility with existing state files;
        // Todo items no longer expose or control a duration in the UI.
        let task = TaskItem(title: title, estimateMinutes: state.focusSession.preset.rawValue)
        state.tasks.append(task)
        if state.focusSession.phase == .idle {
            state.focusSession.taskID = task.id
        }
        changed()
    }

    func selectTask(_ id: UUID) {
        guard state.tasks.contains(where: { $0.id == id && !$0.done }) else { return }
        state.focusSession.taskID = id
        changed()
    }

    func completeTask(_ id: UUID) {
        guard let index = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[index].done = true
        state.tasks[index].completedAt = now()
        if state.focusSession.taskID == id { state.focusSession.taskID = nil }
        setTransient(.done)
        changed()
    }

    func deleteTask(_ id: UUID) {
        state.tasks.removeAll { $0.id == id }
        if state.focusSession.taskID == id { state.focusSession.taskID = nil }
        changed()
    }

    func startFocus(_ preset: FocusPreset) {
        let seconds = preset.rawValue * 60
        state.focusSession.phase = .focus
        state.focusSession.preset = preset
        state.focusSession.customDuration = nil
        state.focusSession.phaseDurationSeconds = seconds
        state.focusSession.phaseEndsAt = now().addingTimeInterval(TimeInterval(seconds))
        state.focusSession.pausedRemainingSeconds = nil
        state.focusSession.pausedFromPhase = nil
        changed()
    }

    func startCustomFocus(focusMinutes: Int, breakMinutes: Int) {
        let focus = max(1, min(240, focusMinutes))
        let brk = max(1, min(240, breakMinutes))
        let duration = FocusDuration.custom(focusMinutes: focus, breakMinutes: brk)
        let seconds = duration.focusSeconds
        state.focusSession.phase = .focus
        state.focusSession.preset = .short
        state.focusSession.customDuration = duration
        state.focusSession.phaseDurationSeconds = seconds
        state.focusSession.phaseEndsAt = now().addingTimeInterval(TimeInterval(seconds))
        state.focusSession.pausedRemainingSeconds = nil
        state.focusSession.pausedFromPhase = nil
        state.settings.lastCustomFocusMinutes = focus
        state.settings.lastCustomBreakMinutes = brk
        changed()
    }

    func pause() {
        guard [.focus, .break].contains(state.focusSession.phase) else { return }
        state.focusSession.pausedRemainingSeconds = state.focusSession.remainingSeconds(at: now())
        state.focusSession.pausedFromPhase = state.focusSession.phase
        state.focusSession.phase = .paused
        changed()
    }

    func resume() {
        guard state.focusSession.phase == .paused,
              let remaining = state.focusSession.pausedRemainingSeconds,
              let phase = state.focusSession.pausedFromPhase else { return }
        state.focusSession.phase = phase
        state.focusSession.phaseEndsAt = now().addingTimeInterval(TimeInterval(remaining))
        state.focusSession.pausedRemainingSeconds = nil
        state.focusSession.pausedFromPhase = nil
        changed()
    }

    func endSession() {
        let taskID = state.focusSession.taskID
        state.focusSession = FocusSession()
        state.focusSession.taskID = taskID
        changed()
    }

    func recordWater() {
        state.health.lastWaterAt = now()
        state.health.waterCount += 1
        state.waterLogs.append(now())
        setTransient(.hydrated)
        changed()
    }

    func recordStand() {
        state.health.lastStandAt = now()
        state.health.consecutiveSitFocusBlocks = 0
        setTransient(.stood)
        changed()
    }

    /// 归零今日统计：清掉今天的番茄记录、喝水记录，并抹去今天任务的完成时间戳
    /// （任务本身保留、勾选状态不变——归零的是统计口径，不是待办数据）。
    func resetTodayStats() {
        let calendar = Calendar.current
        let day = now()
        state.focusBlocks.removeAll { calendar.isDate($0.completedAt, inSameDayAs: day) }
        state.waterLogs.removeAll { calendar.isDate($0, inSameDayAs: day) }
        for index in state.tasks.indices {
            if let completedAt = state.tasks[index].completedAt, calendar.isDate(completedAt, inSameDayAs: day) {
                state.tasks[index].completedAt = nil
            }
        }
        changed()
    }

    func setAlwaysOnTop(_ value: Bool) {
        state.settings.alwaysOnTop = value
        changed()
    }

    private func tick() {
        guard [.focus, .break].contains(state.focusSession.phase) else { return }
        if state.focusSession.remainingSeconds(at: now()) <= 0 {
            if state.focusSession.phase == .focus { finishFocus() }
            else { finishBreak() }
        } else {
            notifyStateObservers()
        }
    }

    private func finishFocus() {
        let start = now().addingTimeInterval(-TimeInterval(state.focusSession.phaseDurationSeconds))
        let duration = state.focusSession.duration
        state.focusBlocks.append(.init(completedAt: now(), preset: state.focusSession.preset, focusDuration: state.focusSession.customDuration))
        if state.health.lastStandAt == nil || state.health.lastStandAt! < start {
            state.health.consecutiveSitFocusBlocks += 1
        }
        let breakSeconds = duration.breakSeconds
        state.focusSession.phase = .break
        state.focusSession.phaseDurationSeconds = breakSeconds
        state.focusSession.phaseEndsAt = now().addingTimeInterval(TimeInterval(breakSeconds))
        setTransient(.done)
        changed()
        onFocusCompleted?()
    }

    private func finishBreak() {
        endSession()
        onBreakCompleted?()
    }

    private func setTransient(_ value: BuddyState) {
        transientState = value
        notifyBuddyStateObservers()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.transientState = nil
            self?.notifyBuddyStateObservers()
        }
    }

    private func changed() {
        Self.save(state)
        notifyStateObservers()
        notifyBuddyStateObservers()
    }

    private func notifyStateObservers() {
        for observer in stateObservers.values { observer(state) }
    }

    private func notifyBuddyStateObservers() {
        let value = buddyState
        for observer in buddyStateObservers.values { observer(value) }
    }

    private func startTicker() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Unwind", isDirectory: true).appendingPathComponent("app-state-v1.json")
    }

    private static func load() -> AppState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder.unwind.decode(AppState.self, from: data) else { return AppState() }
        return state
    }

    private static func save(_ state: AppState) {
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.unwind.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension JSONEncoder {
    static var unwind: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var unwind: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
