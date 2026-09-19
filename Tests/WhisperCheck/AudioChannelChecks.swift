import AVFoundation
import PrompterSpeech

func runAudioChannelChecks() throws {
    func convertedRMS(activeChannel: Int, selectedChannel: Int, channels: Int, interleaved: Bool) throws -> Double {
        let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels))!
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, interleaved: interleaved, channelLayout: layout)
        let converter = try InputChannelConverter.make(from: format, channel: selectedChannel)
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        input.frameLength = 4800
        for channel in 0..<channels {
            for frame in 0..<4800 {
                let value: Float = channel == activeChannel - 1 ? Float(sin(Double(frame) * 2 * .pi * 440 / 48000) * 0.5) : 0
                input.floatChannelData![interleaved ? 0 : channel][interleaved ? frame * channels + channel : frame] = value
            }
        }
        let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: 1664)!
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true; status.pointee = .haveData; return input
        }
        if let error { throw error }
        guard output.frameLength > 1000 else { throw NSError(domain: "ChannelCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "No converted audio: \(output.frameLength) frames"]) }
        let samples = UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength))
        return sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count))
    }
    for interleaved in [false, true] {
        // Loud guest/main-mix audio must never leak into a silent host track.
        let guestOnly = try convertedRMS(activeChannel: 1, selectedChannel: 3, channels: 20, interleaved: interleaved)
        guard guestOnly < 0.000001 else { throw NSError(domain: "ChannelCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "Guest leaked: \(guestOnly), interleaved \(interleaved)"]) }
        let hostOnly = try convertedRMS(activeChannel: 3, selectedChannel: 3, channels: 20, interleaved: interleaved)
        guard hostOnly > 0.3 else { throw NSError(domain: "ChannelCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: "Host missing: \(hostOnly), interleaved \(interleaved)"]) }
        let finalChannel = try convertedRMS(activeChannel: 20, selectedChannel: 20, channels: 20, interleaved: interleaved)
        guard finalChannel > 0.3 else { throw NSError(domain: "ChannelCheck", code: 4, userInfo: [NSLocalizedDescriptionKey: "Last channel missing: \(finalChannel), interleaved \(interleaved)"]) }
    }
    let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
    do { _ = try InputChannelConverter.make(from: mono, channel: 2); fatalError("Missing channel must fail instead of falling back to a mix") }
    catch { }
    print("PASS: selected-channel isolation and resampling for planar/interleaved 20-channel input; invalid channel rejected")
    print("Available channels on the current default input: \(MicrophoneCapture.channels(deviceID: nil).count)")
}
