import Foundation
import AVFoundation
import CoreAudio
import WhisperKit

public struct Microphone: Identifiable, Hashable {
    public let id: UInt32
    public let name: String
}
public struct MicrophoneChannel: Identifiable, Hashable {
    public let id: Int
    public let name: String
}
public enum InputChannelConverter {
    public static func make(from source: AVAudioFormat, channel: Int) throws -> AVAudioConverter {
        guard source.sampleRate > 0, channel >= 1, channel <= Int(source.channelCount),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else {
            throw NSError(domain: "PrompterMicrophone", code: 1, userInfo: [NSLocalizedDescriptionKey: "The selected input channel is unavailable. Choose an input channel in Voice settings."])
        }
        converter.channelMap = [NSNumber(value: channel - 1)]
        converter.downmix = false
        return converter
    }
}
public struct AudioSnapshot: Sendable {
    public let samples: [Float]
    public let start: Double
    public let end: Double
    public let decibels: Double
    public let lastVoice: Double
    public let lastBuffer: Double
}

/// A bounded audio buffer. No audio is written to disk. The audio callback and
/// inference loop exchange snapshots under a lock instead of sharing mutable arrays.
public final class MicrophoneCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var samples: [Float] = []
    private var total = 0
    private var decibels = -100.0
    private var lastVoice = 0.0
    private var lastBuffer = 0.0
    private var threshold = -42.0
    private var active = false
    public init() {}
    public static var devices: [Microphone] { AudioProcessor.getAudioDevices().map { Microphone(id: $0.id, name: $0.name) } }
    public static func channels(deviceID: UInt32?) -> [MicrophoneChannel] {
        var device = deviceID ?? 0
        if device == 0 {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return [] }
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, memory) == noErr else { return [] }
        let buffers = UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
        let count = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard count > 0 else { return [] }
        return (1...count).map { channel in
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyElementName, mScope: kAudioDevicePropertyScopeInput, mElement: UInt32(channel))
            let result = AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name)
            let rawLabel = result == noErr ? name.map { $0.takeRetainedValue() as String } : nil
            let label = rawLabel.flatMap { $0 == String(channel) || $0 == "Channel \(channel)" || $0.isEmpty ? nil : $0 }
            return MicrophoneChannel(id: channel, name: label.map { "Channel \(channel) · \($0)" } ?? "Channel \(channel)")
        }
    }
    public func setThreshold(_ value: Double) { lock.lock(); threshold = value; lock.unlock() }
    public func snapshot() -> AudioSnapshot {
        lock.lock(); defer { lock.unlock() }
        let buffer = Array(samples.suffix(8 * 16000))
        return AudioSnapshot(samples: buffer, start: Double(total - buffer.count) / 16000, end: Double(total) / 16000, decibels: decibels, lastVoice: lastVoice, lastBuffer: lastBuffer)
    }
    public func start(deviceID: UInt32?, channel: Int) throws {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if var deviceID, let unit = input.audioUnit {
            let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<UInt32>.size))
            guard result == noErr else { throw failure("Could not open the selected microphone (\(result)).") }
        }
        let sourceFormat = input.outputFormat(forBus: 0)
        let converter = try InputChannelConverter.make(from: sourceFormat, channel: channel)
        let target = converter.outputFormat
        lock.lock()
        samples = []; total = 0; lastVoice = 0; lastBuffer = ProcessInfo.processInfo.systemUptime; decibels = -100; active = true
        lock.unlock()
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(sourceFormat.sampleRate / 10), format: sourceFormat) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / sourceFormat.sampleRate)) + 64
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            guard error == nil, converted.frameLength > 0, let data = converted.floatChannelData?[0] else { return }
            self?.append(Array(UnsafeBufferPointer(start: data, count: Int(converted.frameLength))))
        }
        self.engine = engine
        do { engine.prepare(); try engine.start() }
        catch { stop(); throw error }
    }
    private func append(_ buffer: [Float]) {
        let rms = sqrt(buffer.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, buffer.count)))
        let db = max(-100, 20 * log10(max(rms, 0.00001)))
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        samples.append(contentsOf: buffer)
        total += buffer.count
        if samples.count > 12 * 16000 { samples.removeFirst(samples.count - 12 * 16000) }
        decibels = db
        lastBuffer = now
        if db > threshold { lastVoice = now }
    }
    public func stop() {
        lock.lock(); active = false; samples = []; decibels = -100; lock.unlock()
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        engine = nil
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "PrompterMicrophone", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
