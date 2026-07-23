import Foundation

enum SelfTests {
    @MainActor
    static func run() throws {
        var session = FocusSession()
        let start = Date(timeIntervalSince1970: 1_000)
        session.phase = .focus
        session.phaseDurationSeconds = 1_500
        session.phaseEndsAt = start.addingTimeInterval(1_500)
        try check(session.remainingSeconds(at: start.addingTimeInterval(125)) == 1_375, "focus timestamp")

        var health = HealthState()
        try check(health.waterDue(at: start), "initial water reminder")
        health.lastWaterAt = start
        try check(!health.waterDue(at: start.addingTimeInterval(100)), "water interval")
        health.consecutiveSitFocusBlocks = 2
        try check(health.tiredDue, "sit reminder")

        var state = AppState()
        state.tasks = [TaskItem(title: "联调", estimateMinutes: 50)]
        let encoded = try JSONEncoder.unwind.encode(state)
        let decoded = try JSONDecoder.unwind.decode(AppState.self, from: encoded)
        try check(decoded.version == state.version && decoded.tasks.first?.title == "联调" && decoded.tasks.first?.estimateMinutes == 50, "state codable")

        let pcm = PCMCodec.int16LittleEndianData([0, 1, -1])
        try check(Array(pcm) == [0, 0, 255, 127, 0, 128], "PCM endian")
        let resampled = PCMCodec.resampleTo16k((0..<480).map { Float($0) / 480 }, fromRate: 48_000)
        try check(resampled.count == 160 && abs(resampled[1] - Float(3) / 480) < 0.0001, "PCM resample")

        let json = #"{"action":"future","asset":null,"job_id":null,"remix_job_id":null,"reply":null,"reasons":[],"planner_meta":null,"selected_skill":null,"tool_calls":[],"skill_card":{"type":"ritual_receipt"},"reply_audio_url":null,"timer_sec":null,"fade_out":null}"#
        let decision = try JSONDecoder.unwind.decode(ChatDecision.self, from: Data(json.utf8))
        try check(decision.action == .unknown, "forward-compatible action")
        try check(decision.skillCard?.objectValue?["type"]?.stringValue == "ritual_receipt", "dynamic skill card")

        let observableStore = AppStore(state: state)
        var firstStateObserverCalls = 0
        var secondStateObserverCalls = 0
        _ = observableStore.observeState { _ in firstStateObserverCalls += 1 }
        _ = observableStore.observeState { _ in secondStateObserverCalls += 1 }
        try check(firstStateObserverCalls == 1 && secondStateObserverCalls == 1, "multiple state observers")

        let observableAudio = AudioCoordinator()
        var firstAudioObserverCalls = 0
        var secondAudioObserverCalls = 0
        _ = observableAudio.observePlayback { _, _ in firstAudioObserverCalls += 1 }
        _ = observableAudio.observePlayback { _, _ in secondAudioObserverCalls += 1 }
        observableAudio.stop()
        try check(firstAudioObserverCalls == 2 && secondAudioObserverCalls == 2, "multiple audio observers")

        // Custom duration codable round-trip
        var customState = AppState()
        customState.focusSession.customDuration = .custom(focusMinutes: 35, breakMinutes: 7)
        customState.settings.lastCustomFocusMinutes = 35
        customState.settings.lastCustomBreakMinutes = 7
        let customEncoded = try JSONEncoder.unwind.encode(customState)
        let customDecoded = try JSONDecoder.unwind.decode(AppState.self, from: customEncoded)
        try check(customDecoded.focusSession.customDuration == .custom(focusMinutes: 35, breakMinutes: 7), "custom duration codable")
        try check(customDecoded.focusSession.duration.focusMinutes == 35, "custom duration focusMinutes")
        try check(customDecoded.focusSession.duration.breakSeconds == 7 * 60, "custom duration breakSeconds")
        try check(customDecoded.settings.lastCustomFocusMinutes == 35, "custom settings codable")

        // Backward compat: state without customDuration decodes as nil
        let oldState = AppState()
        let oldEncoded = try JSONEncoder.unwind.encode(oldState)
        let oldDecoded = try JSONDecoder.unwind.decode(AppState.self, from: oldEncoded)
        try check(oldDecoded.focusSession.customDuration == nil, "backward compat custom duration")
        try check(oldDecoded.focusSession.duration.focusMinutes == 25, "backward compat preset fallback")

        // CompletedFocusBlock.effectiveMinutes
        let presetBlock = CompletedFocusBlock(completedAt: .now, preset: .medium)
        try check(presetBlock.effectiveMinutes == 50, "preset block effectiveMinutes")
        let customBlock = CompletedFocusBlock(completedAt: .now, preset: .short, focusDuration: .custom(focusMinutes: 40, breakMinutes: 8))
        try check(customBlock.effectiveMinutes == 40, "custom block effectiveMinutes")
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw SelfTestError.failed(name) }
    }
}

enum SelfTestError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case .failed(let name) = self { return "Self-test failed: \(name)" }
        return "Self-test failed"
    }
}
