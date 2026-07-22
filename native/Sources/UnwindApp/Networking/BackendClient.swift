import Foundation

enum BackendError: LocalizedError {
    case invalidResponse
    case http(Int, String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "后端返回了无法识别的数据"
        case .http(let code, let body): "后端请求失败（HTTP \(code)）：\(body.prefix(160))"
        case .timedOut: "后端响应超时"
        }
    }
}

protocol BackendClientProtocol: Sendable {
    func health() async throws -> HealthResponse
    func chat(_ text: String, currentAssetID: String?) async throws -> ChatDecision
    func recommendations(limit: Int) async throws -> [Recommendation]
    func generationJob(id: String) async throws -> GenerationJob
    func remixJob(id: String) async throws -> RemixJob
    func skills() async throws -> [SkillDescriptor]
    func nudge(scenario: String) async throws -> Nudge
}

struct BackendClient: BackendClientProtocol, Sendable {
    static let shared = BackendClient()
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func health() async throws -> HealthResponse {
        try await get("health", timeout: 4)
    }

    func chat(_ text: String, currentAssetID: String?) async throws -> ChatDecision {
        struct Body: Encodable {
            let requestText: String
            let currentAssetID: String?
            enum CodingKeys: String, CodingKey { case requestText = "request_text"; case currentAssetID = "current_asset_id" }
        }
        return try await post("showcase/chat", body: Body(requestText: text, currentAssetID: currentAssetID), timeout: 15)
    }

    func recommendations(limit: Int = 3) async throws -> [Recommendation] {
        try await get("users/showcase_user/recommendations?limit=\(limit)", timeout: 8)
    }

    func generationJob(id: String) async throws -> GenerationJob {
        try await get("generation-jobs/\(id)", timeout: 8)
    }

    func remixJob(id: String) async throws -> RemixJob {
        try await get("remix-jobs/\(id)", timeout: 8)
    }

    func skills() async throws -> [SkillDescriptor] {
        let response: SkillsResponse = try await get("showcase/skills", timeout: 8)
        return response.skills
    }

    func nudge(scenario: String) async throws -> Nudge {
        let encoded = scenario.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scenario
        return try await get("showcase/nudge?scenario=\(encoded)", timeout: 8)
    }

    func absoluteURL(_ value: String) -> URL? {
        if let url = URL(string: value), url.scheme != nil { return url }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private func get<T: Decodable>(_ path: String, timeout: TimeInterval) async throws -> T {
        var request = URLRequest(url: endpoint(path))
        request.timeoutInterval = timeout
        return try await execute(request)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body, timeout: TimeInterval) async throws -> T {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await execute(request)
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw BackendError.http(http.statusCode, String(decoding: data, as: UTF8.self))
            }
            do { return try JSONDecoder.unwind.decode(T.self, from: data) }
            catch { throw BackendError.invalidResponse }
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .timedOut { throw BackendError.timedOut }
    }

    private func endpoint(_ path: String) -> URL {
        let parts = path.split(separator: "?", maxSplits: 1).map(String.init)
        var components = URLComponents(url: baseURL.appendingPathComponent(parts[0]), resolvingAgainstBaseURL: false)!
        if parts.count == 2 { components.percentEncodedQuery = parts[1] }
        return components.url!
    }
}
