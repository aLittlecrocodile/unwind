import Foundation

enum FocusPreset: Int, Codable, CaseIterable, Sendable {
    case short = 25
    case medium = 50
    case long = 90

    var breakMinutes: Int {
        switch self { case .short: 5; case .medium: 10; case .long: 15 }
    }
}

enum FocusDuration: Codable, Equatable, Sendable {
    case preset(FocusPreset)
    case custom(focusMinutes: Int, breakMinutes: Int)

    var focusMinutes: Int {
        switch self {
        case .preset(let p): return p.rawValue
        case .custom(let focus, _): return focus
        }
    }

    var focusSeconds: Int { focusMinutes * 60 }

    var breakSeconds: Int {
        switch self {
        case .preset(let p): return p.breakMinutes * 60
        case .custom(_, let brk): return brk * 60
        }
    }
}

enum SessionPhase: String, Codable, Sendable {
    case idle, focus, `break`, paused
}

struct FocusSession: Codable, Equatable, Sendable {
    var phase: SessionPhase = .idle
    var preset: FocusPreset = .short
    var customDuration: FocusDuration?
    var taskID: UUID?
    var phaseDurationSeconds = 0
    var phaseEndsAt: Date?
    var pausedRemainingSeconds: Int?
    var pausedFromPhase: SessionPhase?

    /// The effective duration source — custom if set, otherwise derived from preset.
    var duration: FocusDuration {
        customDuration ?? .preset(preset)
    }

    func remainingSeconds(at now: Date = .now) -> Int {
        if phase == .paused { return max(0, pausedRemainingSeconds ?? 0) }
        guard let phaseEndsAt else { return 0 }
        return max(0, Int((phaseEndsAt.timeIntervalSince(now)).rounded()))
    }
}

struct TaskItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var estimateMinutes: Int
    var done: Bool
    let createdAt: Date
    var completedAt: Date?

    init(title: String, estimateMinutes: Int) {
        id = UUID()
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.estimateMinutes = estimateMinutes
        done = false
        createdAt = .now
    }
}

struct HealthState: Codable, Equatable, Sendable {
    var lastWaterAt: Date?
    var waterCount = 0
    var lastStandAt: Date?
    var consecutiveSitFocusBlocks = 0

    func waterDue(at now: Date = .now) -> Bool {
        guard let lastWaterAt else { return true }
        return now.timeIntervalSince(lastWaterAt) >= 3600
    }

    var tiredDue: Bool { consecutiveSitFocusBlocks >= 2 }
}

struct CompletedFocusBlock: Codable, Equatable, Sendable {
    let completedAt: Date
    let preset: FocusPreset
    var focusDuration: FocusDuration?

    var effectiveMinutes: Int {
        focusDuration?.focusMinutes ?? preset.rawValue
    }
}

struct DailyStats: Equatable, Sendable {
    let pomodoroCount: Int
    let focusMinutes: Int
    let tasksCompleted: Int
    let waterCount: Int
}

struct AppSettings: Codable, Equatable, Sendable {
    var alwaysOnTop = true
    var speakReplies = true
    var lastCustomFocusMinutes: Int = 25
    var lastCustomBreakMinutes: Int = 5
}

struct AppState: Codable, Equatable, Sendable {
    var version = 1
    var tasks: [TaskItem] = []
    var focusSession = FocusSession()
    var health = HealthState()
    var focusBlocks: [CompletedFocusBlock] = []
    var waterLogs: [Date] = []
    var settings = AppSettings()
}

enum BuddyState: Sendable {
    case idle, focus, rest, tired, water, done, hydrated, stood
}
