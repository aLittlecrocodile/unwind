import Foundation

struct HealthResponse: Codable, Sendable {
    let status: String
    let app: String
    let hermes: String
    let publicBaseURL: String

    enum CodingKeys: String, CodingKey {
        case status, app, hermes
        case publicBaseURL = "public_base_url"
    }
}

struct AudioAsset: Codable, Identifiable, Sendable {
    let id: String
    let type: String
    let title: String
    let durationSeconds: Int
    let playbackURL: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title
        case durationSeconds = "duration_sec"
        case playbackURL = "playback_url"
    }
}

struct Recommendation: Codable, Sendable {
    let asset: AudioAsset
    let score: Double
    let reasons: [String]
}

struct PlannerMeta: Codable, Sendable {
    let plannerSource: String
    let plannerConfidence: Double
    let plannerLatencyMS: Int
    let fallbackReason: String?

    enum CodingKeys: String, CodingKey {
        case plannerSource = "planner_source"
        case plannerConfidence = "planner_confidence"
        case plannerLatencyMS = "planner_latency_ms"
        case fallbackReason = "fallback_reason"
    }
}

struct AgentToolCall: Codable, Sendable {
    let name: String
    let status: String
    let input: [String: JSONValue]
    let output: [String: JSONValue]?
    let latencyMS: Int
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case name, status, input, output, reason
        case latencyMS = "latency_ms"
    }
}

struct GenerationDirective: Codable, Sendable {
    let intent: String?
    let tone: String?
    let durationSeconds: Int?
    let voiceStyle: String?
    let contentBrief: String
    let outline: [String]
    let keyElements: [String]

    enum CodingKeys: String, CodingKey {
        case intent, tone, outline
        case durationSeconds = "duration_sec"
        case voiceStyle = "voice_style"
        case contentBrief = "content_brief"
        case keyElements = "key_elements"
    }
}

struct ChatDecision: Codable, Sendable {
    enum Action: String, Codable, Sendable {
        case chat
        case playAsset = "play_asset"
        case generateJob = "generate_job"
        case remixCurrent = "remix_current"
        case noMatch = "no_match"
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Action(rawValue: raw) ?? .unknown
        }
    }

    let action: Action
    let asset: AudioAsset?
    let jobID: String?
    let remixJobID: String?
    let reply: String?
    let reasons: [String]
    let plannerMeta: PlannerMeta?
    let selectedSkill: String?
    let toolCalls: [AgentToolCall]
    let skillCard: JSONValue?
    let replyAudioURL: String?
    let timerSeconds: Int?
    let fadeOut: Bool?

    enum CodingKeys: String, CodingKey {
        case action, asset, reply, reasons
        case jobID = "job_id"
        case remixJobID = "remix_job_id"
        case plannerMeta = "planner_meta"
        case selectedSkill = "selected_skill"
        case toolCalls = "tool_calls"
        case skillCard = "skill_card"
        case replyAudioURL = "reply_audio_url"
        case timerSeconds = "timer_sec"
        case fadeOut = "fade_out"
    }
}

struct GenerationJob: Codable, Sendable {
    let id: String
    let status: String
    let latencyMS: Int?
    let errorMessage: String?
    let directive: GenerationDirective?
    let asset: AudioAsset?

    enum CodingKeys: String, CodingKey {
        case id, status, directive, asset
        case latencyMS = "latency_ms"
        case errorMessage = "error_message"
    }
}

struct RemixJob: Codable, Sendable {
    let id: String
    let status: String
    let errorMessage: String?
    let outputAsset: AudioAsset?

    enum CodingKeys: String, CodingKey {
        case id, status
        case errorMessage = "error_message"
        case outputAsset = "output_asset"
    }
}

struct SkillDescriptor: Codable, Sendable {
    let key: String
    let label: String
    let category: String
    let status: String
    let desc: String
    let demoSay: String?
    let demoScenario: String?
    let demoCall: Bool?

    enum CodingKeys: String, CodingKey {
        case key, label, category, status, desc
        case demoSay = "demo_say"
        case demoScenario = "demo_scenario"
        case demoCall = "demo_call"
    }
}

struct SkillsResponse: Codable, Sendable { let skills: [SkillDescriptor] }

struct Nudge: Codable, Sendable {
    let icon: String
    let title: String
    let text: String
    let action: String
    let actionLabel: String
    let actionText: String?
    let skill: String

    enum CodingKeys: String, CodingKey {
        case icon, title, text, action, skill
        case actionLabel = "action_label"
        case actionText = "action_text"
    }
}
