import SwiftUI
import PrompterSpeech

struct VoicePromptControls: View {
    @ObservedObject var state: AppState
    @ObservedObject var voice: VoiceController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Voice prompting", isOn: Binding(get: { voice.enabled }, set: {
                state.pausePlayback(stopListening: true)
                voice.enabled = $0
            })).font(.system(size: 12, weight: .medium)).toggleStyle(.switch)
            if voice.enabled {
                if !voice.isDownloaded || voice.isPreparing || voice.modelSetupFailed {
                    VoiceModelSetup(voice: voice)
                }
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
                #if EXPERIMENTAL_COMMANDS
                Divider().overlay(Palette.border)
                Toggle("Hands-free commands", isOn: Binding(get: { voice.handsFreeCommands }, set: voice.setHandsFreeCommands))
                    .font(.system(size: 11, weight: .medium)).toggleStyle(.switch)
                if voice.handsFreeCommands {
                    Label(voice.isStarting ? "Starting microphone…" : "Listening for “Hey Teleprompter”", systemImage: "mic.fill")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.green)
                    Text("Say “Hey Teleprompter, let’s go” to begin.")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                #endif
                Button("Advanced voice settings…", action: state.openVoiceLab).font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.accent)
                Text(voice.handsFreeCommands ? "Pause keeps listening. Esc turns the mic off." : "Play starts listening. Pause stops the mic.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }.padding(15).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct VoicePlaybackStatus: View {
    @ObservedObject var voice: VoiceController
    @ObservedObject var playback: Playback
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
        if let notice = voice.commandNotice { return notice }
        if voice.isStarting { return voice.isPreparing ? "Preparing voice recognition… Play again to cancel." : "Starting microphone…" }
        if voice.isPreparing { return voice.status }
        if !voice.isDownloaded { return "Download a speech model to enable voice prompting" }
        if voice.isListening {
            if voice.handsFreeCommands {
                return playback.transport.isPlaying ? "Mic on · Hey Teleprompter ready · \(voice.mode.rawValue)" : "Script paused · mic on · Say Hey Teleprompter, resume"
            }
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

    private var inputLocked: Bool { voice.isListening || voice.isStarting }
    private var microphoneName: String {
        voice.microphones.first { $0.id == voice.selectedMicrophone }?.name ?? "System default"
    }
    private var channelName: String {
        voice.channels.first { $0.id == voice.selectedChannel }?.name ?? "Choose a channel"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inputCard
                    promptingCard
                    #if EXPERIMENTAL_COMMANDS
                    commandsCard
                    #endif
                    modelCard
                    tuningCard
                    diagnosticsCard
                }.padding(24)
            }
            Rectangle().fill(Palette.border).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                VoiceTransport(state: state, playback: state.playback, voice: voice)
                Label("Speech stays on this Mac. Audio and transcripts aren’t saved.", systemImage: "lock.shield")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(minWidth: 660, minHeight: 580)
        .background(Palette.background).foregroundStyle(.white.opacity(0.92)).tint(Palette.accent)
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "waveform")
                .font(.system(size: 23, weight: .medium)).foregroundStyle(Palette.accent)
                .frame(width: 46, height: 46)
                .background(Palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice settings").font(.system(size: 24, weight: .semibold)).tracking(-0.5)
                Text("A natural pace. A little fine-tuning.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 16)
            Button(action: state.closeVoiceLab) {
                Label("Back to script", systemImage: "arrow.left")
            }.buttonStyle(QuietButton())
        }.padding(.horizontal, 24).padding(.vertical, 20)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                cardHeading("Audio input", subtitle: "Choose the voice that moves the script.", icon: "mic")
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(voice.isListening ? Palette.green : Palette.muted).frame(width: 5, height: 5)
                    Text(voice.isListening ? "MIC ON" : "MIC OFF")
                        .font(.system(size: 9, weight: .semibold)).tracking(0.7)
                }.foregroundStyle(voice.isListening ? Palette.green : Palette.muted)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Color.white.opacity(0.035), in: Capsule())
            }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    fieldLabel("Microphone")
                    HStack(spacing: 7) {
                        SettingsMenu(title: "Microphone", value: microphoneName, selection: $voice.selectedMicrophone) {
                            Text("System default").tag(UInt32(0))
                            ForEach(voice.microphones) { mic in Text(mic.name).tag(mic.id) }
                        }
                        Button(action: voice.refreshMicrophones) { Image(systemName: "arrow.clockwise").frame(width: 16, height: 18) }
                            .buttonStyle(QuietButton()).help("Refresh microphones").accessibilityLabel("Refresh microphones")
                    }
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 7) {
                    fieldLabel("Input channel")
                    SettingsMenu(title: "Input channel", value: channelName, selection: $voice.selectedChannel) {
                        Text("Choose a channel").tag(0)
                        ForEach(voice.channels) { channel in Text(channel.name).tag(channel.id) }
                    }
                }.frame(width: 190)
            }.disabled(inputLocked)
            Text("For interviews, choose the presenter’s isolated channel so the guest’s track won’t move the script.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            inputMeter
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(voice.isStarting ? "Starting microphone…" : voice.isListening ? "Listening to your selected channel" : "Check your microphone")
                        .font(.system(size: 12, weight: .medium))
                    Text(voice.isListening ? "Closing settings leaves the microphone on." : "Test your input without starting the script.")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    if voice.isListening { voice.stop() } else { voice.start() }
                } label: {
                    Label(voice.isListening ? "Stop microphone" : "Test microphone", systemImage: voice.isListening ? "stop.fill" : "mic.fill")
                }.buttonStyle(QuietButton())
                    .disabled(voice.isStarting || voice.isPreparing || voice.selectedChannel == 0 || !voice.isDownloaded)
            }
            if let error = voice.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(Color(red: 1, green: 0.6, blue: 0.5))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }.voiceCard()
    }

    private var inputMeter: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(0..<36) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(voice.isListening && Double(index) / 36 < min(1, max(0, (voice.decibels + 65) / 65))
                              ? (index > 30 ? Palette.accent : Palette.green) : Color.white.opacity(0.07))
                        .frame(height: 8)
                }
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("Selected microphone channel level")
                .accessibilityValue(voice.isListening ? "\(Int(voice.decibels)) decibels" : "Microphone off")
            Text(voice.isListening ? "\(Int(voice.decibels)) dB" : "— dB")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                .frame(width: 46, alignment: .trailing)
        }
    }

    private var promptingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeading("Prompting style", subtitle: "Find the feel that suits your delivery.", icon: "text.alignleft")
            HStack(spacing: 10) {
                modeOption(.follow, icon: "text.quote", detail: "Follow the words you say.")
                modeOption(.pace, icon: "waveform.path", detail: "Move with your speaking rhythm.")
            }
            if voice.mode == .follow {
                knob("Reading lead", value: "\(Int(voice.followLead)) words", binding: $voice.followLead, range: -10...10, step: 1)
                Text("Keep it at zero to follow recognized words. Increase it to bring text up sooner, or decrease it to keep text lower.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Builds speed gradually, slows with you, and holds during silence. Nearby phrase matches help keep your place.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.voiceCard()
    }

    #if EXPERIMENTAL_COMMANDS
    private var commandsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeading("Hands-free commands", subtitle: "Say “Hey Teleprompter,” then give one command and briefly pause.", icon: "waveform.bubble")
            NaturalCommandsSettings(assistant: voice.assistant, setEnabled: voice.setNaturalCommands)
            DisclosureGroup("Command examples") {
                Text("Start / resume / let’s go\nGo back two lines\nStart this paragraph over\nStart from the top of the document\nMove to the next paragraph\nGo back to the last cue point\nIncrease / decrease the font size\nPause / cancel / stop listening")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 8)
            }.font(.system(size: 12))
            Text("Turn on Hands-free commands in the script sidebar to start listening immediately. Pause keeps the microphone available for commands; Esc or “stop listening” turns it off. Only your selected microphone channel is used.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }.voiceCard()
    }

    #endif
    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                cardHeading("Speech model", subtitle: "Local Whisper · English", icon: "cpu")
                Spacer(minLength: 0)
                SettingsMenu(title: "Whisper model", value: voice.model == "base.en" ? "Base English" : "Small English",
                                  selection: Binding(get: { voice.model }, set: { voice.changeModel($0) })) {
                    Text("Base English · Recommended").tag("base.en")
                    Text("Small English").tag("small.en")
                }.frame(width: 220).disabled(inputLocked || voice.isPreparing)
            }
            VoiceModelSetup(voice: voice)
            Text("Base is recommended for live prompting. Small may take longer to respond.")
                .font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }.voiceCard()
    }

    private var tuningCard: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 18) {
                knob("Microphone threshold", value: "\(Int(voice.noiseFloor)) dB", binding: $voice.noiseFloor, range: -65 ... -20, step: 1)
                Text("Controls silence detection in Adaptive pace. Follow script can still recognize quieter speech.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                knob("Pause after silence", value: String(format: "%.1f sec", voice.pauseDelay), binding: $voice.pauseDelay, range: 0.3...2, step: 0.1)
                knob("Minimum pace", value: "\(Int(voice.minimumPace)) wpm", binding: Binding(get: { voice.minimumPace }, set: { voice.minimumPace = min($0, voice.maximumPace) }), range: 40...180, step: 5)
                knob("Maximum pace", value: "\(Int(voice.maximumPace)) wpm", binding: Binding(get: { voice.maximumPace }, set: { voice.maximumPace = max($0, voice.minimumPace) }), range: 100...300, step: 5)
                knob("Speed responsiveness", value: voice.responsiveness < 0.35 ? "Smooth" : "Quick", binding: $voice.responsiveness, range: 0.1...0.7, step: 0.05)
            }.padding(.top, 18)
        } label: {
            Label("Fine-tuning", systemImage: "slider.horizontal.3").font(.system(size: 13, weight: .medium))
        }.voiceCard()
    }

    private var diagnosticsCard: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    metric("Heard pace", value: voice.measuredPace.map { "\(Int($0)) wpm" } ?? "—")
                    metric("Applied pace", value: voice.controlling ? "\(Int(voice.effectivePace)) wpm" : "—")
                    metric("Recognition", value: voice.inferenceSeconds > 0 ? String(format: "%.2f s", voice.inferenceSeconds) : "—")
                    metric("Script match", value: voice.matchConfidence.map { "\(Int($0 * 100))%" } ?? "—")
                }
                Divider().overlay(Palette.border)
                HStack {
                    fieldLabel("Recent speech")
                    Spacer()
                    Text("Last 8 seconds").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Text(voice.transcript.isEmpty ? "Start a mic test and speak to see your words here." : voice.transcript)
                    .font(.system(size: 14)).lineSpacing(5)
                    .foregroundStyle(voice.transcript.isEmpty ? Palette.muted : .white.opacity(0.9))
                    .textSelection(.enabled).frame(maxWidth: .infinity, minHeight: 55, alignment: .topLeading)
                Text(voice.status).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.padding(.top, 18)
        } label: {
            Label("Live diagnostics", systemImage: "chart.bar.xaxis").font(.system(size: 13, weight: .medium))
        }.voiceCard()
    }

    private func cardHeading(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.accent)
                .frame(width: 19).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
    }
    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
    }
    private func modeOption(_ mode: VoiceMode, icon: String, detail: String) -> some View {
        let selected = voice.mode == mode
        return Button { voice.mode = mode } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: icon).font(.system(size: 16)).foregroundStyle(selected ? Palette.accent : Palette.muted)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14)).foregroundStyle(selected ? Palette.accent : Palette.muted.opacity(0.5))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.rawValue).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(selected ? Palette.accent.opacity(0.07) : Color.white.opacity(0.015), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Palette.accent.opacity(0.7) : Palette.border, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel(mode.rawValue).accessibilityValue(selected ? "Selected" : "Not selected")
    }
    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 10)).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 18, weight: .medium)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func knob(_ title: String, value: String, binding: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(value).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Palette.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            }
            Slider(value: binding, in: range, step: step).accessibilityLabel(title)
        }
    }
}

private extension View {
    func voiceCard() -> some View {
        self.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.border, lineWidth: 1))
    }
}

private struct VoiceTransport: View {
    @ObservedObject var state: AppState
    @ObservedObject var playback: Playback
    @ObservedObject var voice: VoiceController
    var body: some View {
        HStack(spacing: 10) {
            Button {
                if !playback.transport.isPlaying && !voice.isStarting { voice.enabled = true }
                state.togglePlayback()
            } label: {
                Label(voice.isStarting ? "Cancel startup" : playback.transport.isPlaying ? "Pause script" : "Play script",
                      systemImage: voice.isStarting ? "stop.fill" : playback.transport.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 11)
                    .foregroundStyle(Palette.background)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).disabled(state.current.wordCount == 0)
            Button("Reset", action: playback.reset).buttonStyle(QuietButton())
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text(playback.transport.isPlaying ? (voice.controlling && playback.voiceDrive?.speaking == false ? playback.voiceDrive?.holdReason ?? "Waiting for speech" : "Prompting") : "Script paused")
                    .font(.system(size: 11, weight: .medium))
                Text(voice.handsFreeCommands ? "Pause keeps listening for commands." : "Play starts listening. Pause stops both.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }
    }
}
