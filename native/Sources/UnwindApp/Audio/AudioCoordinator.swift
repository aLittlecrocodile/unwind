import AppKit
import AVFoundation
import Foundation

@MainActor
final class AudioCoordinator: NSObject {
    static let shared = AudioCoordinator()

    private var core: AudioEngineCore?
    private var replyPlayer: AVAudioPlayer?
    private var currentFile: AVAudioFile?
    private var timer: Timer?
    private var sleepTimerEnd: Date?
    private var fadeWindow: TimeInterval = 0
    private var baseVolume: Float = 1
    private(set) var currentAssetID: String?
    private(set) var currentTitle: String?
    private(set) var isPlaying = false

    private var playbackObservers: [UUID: (Bool, String?) -> Void] = [:]
    private var levelObservers: [UUID: ([Float]) -> Void] = [:]
    private var sleepTimerObservers: [UUID: (Int?) -> Void] = [:]

    override init() {
        super.init()
    }

    @discardableResult
    func observePlayback(_ observer: @escaping (Bool, String?) -> Void) -> UUID {
        let id = UUID()
        playbackObservers[id] = observer
        observer(isPlaying, currentTitle)
        return id
    }

    @discardableResult
    func observeLevels(_ observer: @escaping ([Float]) -> Void) -> UUID {
        let id = UUID()
        levelObservers[id] = observer
        return id
    }

    @discardableResult
    func observeSleepTimer(_ observer: @escaping (Int?) -> Void) -> UUID {
        let id = UUID()
        sleepTimerObservers[id] = observer
        let remaining = sleepTimerEnd.map { max(0, Int($0.timeIntervalSinceNow.rounded(.up))) }
        observer(remaining)
        return id
    }

    func removeObserver(_ id: UUID) {
        playbackObservers[id] = nil
        levelObservers[id] = nil
        sleepTimerObservers[id] = nil
    }

    func play(url: URL, title: String, assetID: String?) async throws {
        stop()
        let localURL = try await cachedAudio(from: url)
        let file = try AVAudioFile(forReading: localURL)
        currentFile = file
        currentTitle = title
        currentAssetID = assetID
        let core = ensureCore()
        try core.startIfNeeded()
        let completion = MainActorRelay<Void> { [weak self] _ in self?.finished() }
        core.play(file: file, completion: completion)
        core.volume = 1
        isPlaying = true
        notifyPlaybackObservers()
    }

    func toggle() {
        guard let core else { return }
        if core.isPlaying {
            core.pause()
            isPlaying = false
        } else if currentFile != nil {
            core.resume()
            isPlaying = true
        }
        notifyPlaybackObservers()
    }

    func stop() {
        core?.stop()
        replyPlayer?.stop()
        replyPlayer = nil
        clearSleepTimer(restoreVolume: true)
        isPlaying = false
        currentAssetID = nil
        currentTitle = nil
        currentFile = nil
        notifyPlaybackObservers()
    }

    func playReply(data: Data, completion: (() -> Void)? = nil) {
        do {
            let player = try AVAudioPlayer(data: data)
            replyPlayer = player
            player.play()
            let duration = player.duration
            Task { @MainActor [weak self, weak player] in
                try? await Task.sleep(for: .seconds(duration))
                guard let self, self.replyPlayer === player else { return }
                completion?()
                self.replyPlayer = nil
            }
        } catch { completion?() }
    }

    func playReply(url: URL) async {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        playReply(data: data)
    }

    func armSleepTimer(seconds: Int, fade: Bool) {
        clearSleepTimer(restoreVolume: true)
        sleepTimerEnd = .now.addingTimeInterval(TimeInterval(seconds))
        fadeWindow = fade ? min(30, Double(seconds) / 3) : 0
        baseVolume = core?.volume ?? 1
        timer = .scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sleepTick() }
        }
        notifySleepTimerObservers(seconds)
    }

    func clearSleepTimer(restoreVolume: Bool) {
        timer?.invalidate()
        timer = nil
        sleepTimerEnd = nil
        if restoreVolume { core?.volume = baseVolume }
        notifySleepTimerObservers(nil)
    }

    private func sleepTick() {
        guard let end = sleepTimerEnd else { return }
        let remaining = end.timeIntervalSinceNow
        guard remaining > 0 else { stop(); return }
        if fadeWindow > 0 && remaining <= fadeWindow {
            core?.volume = max(0.02, baseVolume * Float(remaining / fadeWindow))
        }
        notifySleepTimerObservers(Int(remaining.rounded(.up)))
    }

    private func finished() {
        isPlaying = false
        notifyPlaybackObservers()
    }

    private func ensureCore() -> AudioEngineCore {
        if let core { return core }
        let relay = MainActorRelay<[Float]> { [weak self] levels in
            guard let self else { return }
            for observer in self.levelObservers.values { observer(levels) }
        }
        let value = AudioEngineCore(levelRelay: relay)
        core = value
        return value
    }

    private func notifyPlaybackObservers() {
        for observer in playbackObservers.values { observer(isPlaying, currentTitle) }
    }

    private func notifySleepTimerObservers(_ remaining: Int?) {
        for observer in sleepTimerObservers.values { observer(remaining) }
    }

    private func cachedAudio(from url: URL) async throws -> URL {
        if url.isFileURL { return url }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UnwindAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let key = Data(url.absoluteString.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        let target = cache.appendingPathComponent(String(key.prefix(80))).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: target.path) { return target }
        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
            throw AudioError.invalidAudio
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
        return target
    }
}

final class AudioEngineCore: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()

    var isPlaying: Bool { node.isPlaying }
    var volume: Float {
        get { node.volume }
        set { node.volume = newValue }
    }

    init(levelRelay: MainActorRelay<[Float]>) {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let count = Int(buffer.frameLength)
            let stride = max(1, count / 3)
            let levels = (0..<3).map { band -> Float in
                let start = min(count, band * stride)
                let end = min(count, start + stride)
                guard start < end else { return 0 }
                var sum: Float = 0
                for index in start..<end { sum += channel[index] * channel[index] }
                return min(1, sqrt(sum / Float(end - start)) * 5)
            }
            levelRelay.send(levels)
        }
        engine.prepare()
    }

    func startIfNeeded() throws {
        if !engine.isRunning { try engine.start() }
    }

    func play(file: AVAudioFile, completion: MainActorRelay<Void>) {
        node.scheduleFile(file, at: nil) { completion.send(()) }
        node.play()
    }

    func pause() { node.pause() }
    func resume() { node.play() }
    func stop() { node.stop() }
}

final class RealtimePCMPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!

    init() throws {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        node.play()
    }

    func enqueue(_ data: Data) {
        let samples = PCMCodec.floatsFromInt16LittleEndian(data)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        channel.update(from: samples, count: samples.count)
        node.scheduleBuffer(buffer)
    }

    func stopCurrent() {
        node.stop()
        node.play()
    }

    func close() {
        node.stop()
        engine.stop()
    }
}
