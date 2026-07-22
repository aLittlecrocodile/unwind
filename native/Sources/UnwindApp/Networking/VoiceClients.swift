import AVFoundation
import Foundation

struct VoiceEvent: Sendable {
    let type: String
    let text: String?
    let isFinal: Bool
    let payload: [String: JSONValue]
}

@MainActor
final class PushToTalkClient {
    var onUserText: ((String, Bool) -> Void)?
    var onAssistantText: ((String) -> Void)?
    var onAsset: ((URL, String) -> Void)?
    var onState: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private let microphone = MicrophoneCapture()
    private var replyData = Data()

    func connect() {
        guard socket == nil else { return }
        let url = URL(string: "ws://127.0.0.1:8000/voice/ws?user_id=showcase_user")!
        let socket = URLSession.shared.webSocketTask(with: url)
        self.socket = socket
        socket.resume()
        onState?("语音已连接")
        receiveTask = Task { [weak self] in await self?.receiveLoop(socket) }
    }

    func startRecording() throws {
        connect()
        replyData.removeAll(keepingCapacity: true)
        try microphone.start { [weak self] data in
            Task { @MainActor in self?.socket?.send(.data(data)) { _ in } }
        }
        onState?("我在听……")
    }

    func endRecording() {
        microphone.stop()
        socket?.send(.string("{\"type\":\"utterance_end\"}")) { [weak self] error in
            if let error { Task { @MainActor in self?.onError?(error.localizedDescription) } }
        }
        onState?("让我想想……")
    }

    func close() {
        microphone.stop(flush: false)
        receiveTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                switch message {
                case .data(let data): replyData.append(data)
                case .string(let text): handle(text)
                @unknown default: break
                }
            } catch {
                if !Task.isCancelled { onError?(error.localizedDescription) }
                self.socket = nil
                break
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return }
        switch type {
        case "user_text": onUserText?(object["text"] as? String ?? "", object["is_final"] as? Bool ?? false)
        case "assistant_text": onAssistantText?(object["text"] as? String ?? "")
        case "audio_asset":
            if let raw = object["url"] as? String, let url = URL(string: raw) {
                onAsset?(url, object["text"] as? String ?? "专属音频")
            }
        case "turn_end":
            let audio = replyData
            replyData.removeAll(keepingCapacity: true)
            if !audio.isEmpty { AudioCoordinator.shared.playReply(data: audio) }
            onState?("回复完成")
        case "error": onError?(object["text"] as? String ?? "语音链路出错")
        default: break
        }
    }
}

@MainActor
final class RealtimeVoiceClient {
    var onEvent: ((VoiceEvent) -> Void)?
    var onError: ((String) -> Void)?

    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private let microphone = MicrophoneCapture()
    private var pcmPlayer: RealtimePCMPlayer?
    private(set) var muted = false

    func start() throws {
        guard socket == nil else { return }
        pcmPlayer = try RealtimePCMPlayer()
        let url = URL(string: "ws://127.0.0.1:8000/voice/realtime?user_id=showcase_user")!
        let socket = URLSession.shared.webSocketTask(with: url)
        self.socket = socket
        socket.resume()
        try microphone.start { [weak self] data in
            Task { @MainActor in
                guard let self, !self.muted else { return }
                self.socket?.send(.data(data)) { _ in }
            }
        }
        receiveTask = Task { [weak self] in await self?.receiveLoop(socket) }
    }

    func setMuted(_ muted: Bool) { self.muted = muted }

    func stop() {
        socket?.send(.string("{\"type\":\"stop\"}")) { _ in }
        microphone.stop(flush: false)
        receiveTask?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        pcmPlayer?.close()
        pcmPlayer = nil
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                switch try await socket.receive() {
                case .data(let data): pcmPlayer?.enqueue(data)
                case .string(let text): handle(text)
                @unknown default: break
                }
            } catch {
                if !Task.isCancelled { onError?(error.localizedDescription) }
                break
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: JSONValue].self, from: data),
              let type = raw["type"]?.stringValue else { return }
        if type == "asr_info" { pcmPlayer?.stopCurrent() }
        onEvent?(.init(
            type: type,
            text: raw["text"]?.stringValue ?? raw["message"]?.stringValue,
            isFinal: !(raw["interim"] == .bool(true)),
            payload: raw
        ))
    }
}
