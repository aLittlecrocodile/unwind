import AVFoundation
import Foundation

final class MainActorRelay<Value: Sendable>: @unchecked Sendable {
    private let handler: @MainActor @Sendable (Value) -> Void

    init(_ handler: @escaping @MainActor @Sendable (Value) -> Void) {
        self.handler = handler
    }

    nonisolated func send(_ value: Value) {
        Task { @MainActor in handler(value) }
    }
}

enum PCMCodec {
    static let targetRate = 16_000.0

    static func resampleTo16k(_ samples: [Float], fromRate: Double) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard fromRate != targetRate else { return samples }
        let ratio = fromRate / targetRate
        let count = Int(Double(samples.count) / ratio)
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let source = Double(index) * ratio
            let low = Int(source)
            let high = min(low + 1, samples.count - 1)
            let fraction = Float(source - Double(low))
            return samples[low] + (samples[high] - samples[low]) * fraction
        }
    }

    static func int16LittleEndianData(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let scaled = clamped < 0 ? clamped * 32_768 : clamped * 32_767
            var value = Int16(scaled).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func floatsFromInt16LittleEndian(_ data: Data) -> [Float] {
        data.withUnsafeBytes { raw in
            let count = raw.count / 2
            return (0..<count).map { index in
                let low = UInt16(raw[index * 2])
                let high = UInt16(raw[index * 2 + 1]) << 8
                return Float(Int16(bitPattern: low | high)) / 32_768
            }
        }
    }
}

final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var buffered: [Float] = []
    private let frameSamples = 3_200
    private var handler: (@Sendable (Data) -> Void)?
    private(set) var running = false

    func start(handler: @escaping @Sendable (Data) -> Void) throws {
        guard !running else { return }
        self.handler = handler
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw AudioError.microphoneUnavailable }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.consume(buffer, sampleRate: format.sampleRate)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    func stop(flush: Bool = true) {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        lock.lock()
        let tail = flush ? buffered : []
        buffered.removeAll(keepingCapacity: true)
        lock.unlock()
        if !tail.isEmpty { handler?(PCMCodec.int16LittleEndianData(tail)) }
        handler = nil
    }

    private func consume(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let input = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let converted = PCMCodec.resampleTo16k(input, fromRate: sampleRate)
        lock.lock()
        buffered.append(contentsOf: converted)
        var frames: [Data] = []
        while buffered.count >= frameSamples {
            frames.append(PCMCodec.int16LittleEndianData(Array(buffered.prefix(frameSamples))))
            buffered.removeFirst(frameSamples)
        }
        lock.unlock()
        for frame in frames { handler?(frame) }
    }
}

final class MicrophoneLevelMonitor: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private(set) var running = false

    func start(relay: MainActorRelay<Float>) throws {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw AudioError.microphoneUnavailable }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += channel[index] * channel[index] }
            relay.send(min(1, sqrt(sum / Float(buffer.frameLength)) * 14))
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}

enum AudioError: LocalizedError {
    case microphoneUnavailable
    case invalidAudio

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable: "无法使用麦克风，请检查系统权限"
        case .invalidAudio: "音频文件无法播放"
        }
    }
}
