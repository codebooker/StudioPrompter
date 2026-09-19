import SwiftUI
import PrompterSpeech

struct VoicePromptControls: View {
    @ObservedObject var state: AppState
    @ObservedObject var voice: VoiceController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Voice prompting", isOn: Binding(get: { voice.enabled }, set: {
                state.pausePlayback()
                voice.enabled = $0
            })).font(.system(size: 12, weight: .medium)).toggleStyle(.switch)
            if voice.enabled {
                VoiceModelSetup(voice: voice)
                Picker("Voice mode", selection: $voice.mode) {
                    Text("Follow script").tag(VoiceMode.follow)
                    Text("Adaptive pace").tag(VoiceMode.pace)
                }.labelsHidden().accessibilityLabel("Voice mode")
                Text(voice.mode == .follow ? "Keeps your spoken words near the reading guide." : "Adapts to your cadence and corrects script drift.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                VStack(alignment: .leading, spacing: 8) {
                    Text("MICROPHONE").font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(Palette.muted)
                    Picker("Microphone", selection: $voice.selectedMicrophone) {
                        Text("System default").tag(UInt32(0))
                        ForEach(voice.microphones) { mic in Text(mic.name).tag(mic.id) }
                    }.labelsHidden().accessibilityLabel("Microphone")
                    Picker("Input channel", selection: $voice.selectedChannel) {
                        Text("Choose input channel").tag(0)
                        ForEach(voice.channels) { channel in Text(channel.name).tag(channel.id) }
                    }.labelsHidden().accessibilityLabel("Input channel")
                }.disabled(voice.isListening || voice.isStarting)
                Button("Advanced voice settings…", action: state.openVoiceLab).font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.accent)
                Text("Play starts listening. Pause stops the mic.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }.padding(15).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct VoicePlaybackStatus: View {
    @ObservedObject var voice: VoiceController
    var body: some View {
        if voice.enabled || voice.error != nil {
            HStack(spacing: 7) {
                Image(systemName: voice.isListening ? "mic.fill" : "mic.slash")
                    .foregroundStyle(voice.isListening ? Palette.green : Palette.muted)
                Text(message).font(.system(size: 11)).foregroundStyle(voice.error == nil ? Palette.muted : Color.red)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if voice.isListening {
                    ProgressView(value: min(1, max(0, (voice.decibels + 65) / 65)))
                        .frame(width: 65).tint(voice.speaking ? Palette.green : Palette.muted)
                        .accessibilityLabel("Selected microphone channel level")
                }
            }
        }
    }
    private var message: String {
        if let error = voice.error { return error }
        if voice.isStarting { return voice.isPreparing ? "Preparing voice recognition… Play again to cancel." : "Starting microphone…" }
        if voice.isPreparing { return voice.status }
        if !voice.isDownloaded { return "Download a speech model to enable voice prompting" }
        if voice.isListening {
            if voice.waitingForRetake { return "Mic on · Ready for retake — read from here" }
            return "Listening · \(voice.mode.rawValue) · \(voice.inputSummary)"
        }
        return "Mic off · \(voice.mode.rawValue) ready"
    }
}

struct VoiceModelSetup: View {
    @ObservedObject var voice: VoiceController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if voice.isPreparing {
                if voice.downloadProgress < 1 {
                    ProgressView(value: voice.downloadProgress)
                    Text("Downloading model · \(Int(voice.downloadProgress * 100))%")
                } else {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Preparing on this Mac…") }
                }
                Text("First-time setup may take a few minutes.").foregroundStyle(Palette.muted)
            } else if voice.modelSetupFailed {
                Label("Model setup incomplete", systemImage: "exclamationmark.circle").foregroundStyle(Palette.accent)
                Button("Retry setup") { voice.prepare() }.buttonStyle(.borderedProminent)
            } else if voice.isDownloaded {
                Label(voice.isReady ? "Model ready · works offline" : "Model downloaded · ready for Play", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.green)
            } else {
                Text("Download the speech model once to enable voice prompting.").foregroundStyle(Palette.muted)
                Button { voice.prepare() } label: { Label("Download model", systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderedProminent).accessibilityLabel("Download speech model")
                Text("\(voice.model == "base.en" ? "Base English" : "Small English") · runs on your Mac after setup. No account required.")
                    .foregroundStyle(Palette.muted)
            }
        }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
    }
}

struct VoiceLabView: View {
    @ObservedObject var state: AppState
    @ObservedObject var voice: VoiceController
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform").font(.system(size: 25)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Voice settings").font(.system(size: 23, weight: .semibold))
                    Text("LOCAL SPEECH RECOGNITION").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("Back to script", action: state.closeVoiceLab).buttonStyle(QuietButton())
            }.padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    Text("Listen locally, measure your cadence, and let the script follow along. No cloud transcription or saved audio.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(title: "WHISPER MODEL")
                            Picker("Whisper model", selection: Binding(get: { voice.model }, set: { voice.changeModel($0) })) {
                                Text("Base English · smaller").tag("base.en")
                                Text("Small English · larger").tag("small.en")
                            }.labelsHidden().disabled(voice.isListening || voice.isPreparing || voice.isStarting)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(title: "MICROPHONE")
                            HStack {
                                Picker("Microphone", selection: $voice.selectedMicrophone) {
                                    Text("System default").tag(UInt32(0))
                                    ForEach(voice.microphones) { mic in Text(mic.name).tag(mic.id) }
                                }.labelsHidden().disabled(voice.isListening || voice.isStarting)
                                Button(action: voice.refreshMicrophones) { Image(systemName: "arrow.clockwise") }
                                    .buttonStyle(.plain).help("Refresh microphones").disabled(voice.isListening || voice.isStarting)
                            }
                        }
                    }
                    Picker("Input channel", selection: $voice.selectedChannel) {
                        Text("Choose input channel").tag(0)
                        ForEach(voice.channels) { channel in Text(channel.name).tag(channel.id) }
                    }.disabled(voice.isListening || voice.isStarting).accessibilityLabel("Input channel")
                    Text("Select only the presenter's microphone channel. The meter and recognition use this channel, not the full mix. For a mixer, enable multitrack USB output and verify the channel while the presenter and guest speak separately.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    VoiceModelSetup(voice: voice)
                    HStack {
                        Circle().fill(voice.isListening ? Palette.green : Palette.muted).frame(width: 7, height: 7)
                        Text(voice.status).font(.system(size: 11))
                        Spacer()
                        Button(voice.isListening ? "Stop microphone" : "Start listening") {
                            if voice.isListening { voice.stop() } else { voice.start() }
                        }.buttonStyle(.borderedProminent).disabled(voice.isStarting || voice.isPreparing || voice.selectedChannel == 0 || !voice.isDownloaded)
                    }
                    if let error = voice.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: voice.speaking ? "mic.fill" : "mic").foregroundStyle(voice.speaking ? Palette.green : Palette.muted)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(voice.speaking ? Palette.green : Palette.muted).frame(width: geometry.size.width * min(1, max(0, (voice.decibels + 65) / 65)))
                            }
                        }.frame(height: 6)
                        Text(voice.isListening ? "\(Int(voice.decibels)) dB" : "MIC OFF").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).frame(width: 58)
                    }
                    Divider()
                    Picker("Voice mode", selection: $voice.mode) {
                        ForEach(VoiceMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Text(modeDescription).font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    if voice.mode == .follow {
                        knob("Reading lead", value: "\(Int(voice.followLead)) words", binding: $voice.followLead, range: -10...10, step: 1)
                        Text("Zero follows recognized words. Negative values keep text lower; positive values bring upcoming text up sooner.")
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                    HStack {
                        metric("HEARD PACE", value: voice.measuredPace.map { "\(Int($0)) wpm" } ?? "—")
                        Spacer()
                        metric("APPLIED PACE", value: voice.controlling ? "\(Int(voice.effectivePace)) wpm" : "Manual")
                        Spacer()
                        metric("INFERENCE", value: voice.inferenceSeconds > 0 ? String(format: "%.2f sec", voice.inferenceSeconds) : "—")
                        Spacer()
                        metric("SCRIPT MATCH", value: voice.matchConfidence.map { "\(Int($0 * 100))%" } ?? "—")
                    }.padding(16).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                    VoiceTransport(state: state, playback: state.playback, voice: voice)
                    VStack(alignment: .leading, spacing: 9) {
                        SectionLabel(title: "RECENT SPEECH", trailing: "Rolling 8-second window")
                        Text(voice.transcript.isEmpty ? "Your live transcript will appear here after you start listening and speak." : voice.transcript)
                            .font(.system(size: 16)).lineSpacing(5).foregroundStyle(voice.transcript.isEmpty ? Palette.muted : .white.opacity(0.9))
                            .textSelection(.enabled).frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    }.padding(16).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                    DisclosureGroup("Tuning") {
                        VStack(spacing: 16) {
                            knob("Microphone threshold", value: "\(Int(voice.noiseFloor)) dB", binding: $voice.noiseFloor, range: -65 ... -20, step: 1)
                            Text("Sets silence detection for Adaptive pace. Follow script still recognizes quieter speech and moves only to matched words.").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            knob("Pause after silence", value: String(format: "%.1f sec", voice.pauseDelay), binding: $voice.pauseDelay, range: 0.3...2, step: 0.1)
                            knob("Minimum pace", value: "\(Int(voice.minimumPace)) wpm", binding: Binding(get: { voice.minimumPace }, set: { voice.minimumPace = min($0, voice.maximumPace) }), range: 40...180, step: 5)
                            knob("Maximum pace", value: "\(Int(voice.maximumPace)) wpm", binding: Binding(get: { voice.maximumPace }, set: { voice.maximumPace = max($0, voice.minimumPace) }), range: 100...300, step: 5)
                            knob("Speed responsiveness", value: voice.responsiveness < 0.35 ? "Smooth" : "Quick", binding: $voice.responsiveness, range: 0.1...0.7, step: 0.05)
                        }.padding(.top, 16)
                    }.font(.system(size: 12))
                    Text("Play starts listening and prompting together; Pause stops both. While prompting, scroll back for a retake and read from the new position—the mic stays on. Microphone testing here leaves playback paused. Closing settings leaves an active microphone test running until you stop it.")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                }.padding(22)
            }
        }.frame(minWidth: 610, minHeight: 580).background(Palette.background).foregroundStyle(.white.opacity(0.9)).tint(Palette.accent)

    }
    private var modeDescription: String {
        switch voice.mode {
        case .pace: return "Press Play to adapt to your speaking pace. Speed builds gradually and slows more quickly. Matched phrases gently correct drift to keep your words near the guide. Silence holds the script; without a match, scrolling follows cadence alone."
        case .follow: return "Tracks nearby phrases and catches up smoothly, allowing missed words. Reading lead offsets recognition delay. It holds when speech or a reliable match is missing; scroll manually to reread an earlier passage."
        }
    }
    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }
    private func knob(_ title: String, value: String, binding: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(spacing: 5) {
            HStack { Text(title); Spacer(); Text(value).foregroundStyle(Palette.muted) }.font(.system(size: 11))
            Slider(value: binding, in: range, step: step).accessibilityLabel(title)
        }
    }
}

private struct VoiceTransport: View {
    @ObservedObject var state: AppState
    @ObservedObject var playback: Playback
    @ObservedObject var voice: VoiceController
    var body: some View {
        HStack {
            Button { state.togglePlayback() } label: {
                Label(playback.transport.isPlaying ? "Pause script" : "Play script", systemImage: playback.transport.isPlaying ? "pause.fill" : "play.fill")
            }.buttonStyle(QuietButton()).disabled(state.current.wordCount == 0)
            Button("Reset", action: playback.reset).buttonStyle(QuietButton())
            Spacer()
            Text(playback.transport.isPlaying ? (voice.controlling && playback.voiceDrive?.speaking == false ? playback.voiceDrive?.holdReason ?? "Waiting for speech" : "Prompting") : "Script paused")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }
}
