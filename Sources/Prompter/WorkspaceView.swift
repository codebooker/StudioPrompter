import SwiftUI
import AppKit
import PrompterCore

enum Palette {
    static let background = Color(red: 0.075, green: 0.08, blue: 0.095)
    static let sidebar = Color(red: 0.095, green: 0.102, blue: 0.117)
    static let panel = Color(red: 0.118, green: 0.126, blue: 0.144)
    static let accent = Color(red: 1, green: 0.49, blue: 0.29)
    static let muted = Color(red: 0.52, green: 0.56, blue: 0.62)
    static let border = Color.white.opacity(0.075)
    static let green = Color(red: 0.48, green: 0.81, blue: 0.65)
}

struct WorkspaceView: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack(spacing: 0) {
                LibrarySidebar(state: state).frame(width: 224)
                Rectangle().fill(Palette.border).frame(width: 1)
                VStack(spacing: 0) {
                    scriptHeader
                    if state.isEditing { editor }
                    else { PreviewPanel(state: state, playback: state.playback).padding(.horizontal, 24) }
                    TransportBar(state: state, playback: state.playback, voice: state.voice).padding(24)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Palette.border).frame(width: 1)
                Inspector(state: state, voice: state.voice).frame(width: 256)
            }
            Rectangle().fill(Palette.border).frame(height: 1)
            footer
        }
        .background(Palette.background)
        .foregroundStyle(Color.white.opacity(0.9))
        .tint(Palette.accent)
        .frame(minWidth: 1120, minHeight: 730)
        .preferredColorScheme(.dark)
        .alert("Prompter", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK") { state.errorMessage = nil }
        } message: { Text(state.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "text.alignleft").font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.accent).frame(width: 34, height: 34)
                    .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                (Text("Studio").font(.system(size: 23, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.76))
                 + Text("Prompter").font(.system(size: 23, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.95)))
                    .tracking(-0.6)
                    .fixedSize()
            }
            Spacer()
            Button(action: state.importScript) { Label("Import", systemImage: "square.and.arrow.down") }.buttonStyle(QuietButton())
            OutputMenu(state: state, prominent: true)
            Button(action: state.toggleFullScreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 13)).frame(width: 18, height: 16)
            }.buttonStyle(QuietButton()).help("Enter / exit full screen (⌃⌘F)").accessibilityLabel("Toggle full screen")
        }.padding(.horizontal, 24).frame(height: 66)
    }

    private var scriptHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(state.current.title).font(.system(size: 23, weight: .semibold)).lineLimit(1)
                HStack(spacing: 9) {
                    Text("\(state.current.wordCount) words")
                    Circle().frame(width: 3, height: 3)
                    Text("≈ \(timestamp(state.current.duration)) at current pace")
                }.font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 10)
            Button(action: state.toggleEditing) {
                Label(state.isEditing ? "Done editing" : "Edit script", systemImage: state.isEditing ? "checkmark" : "square.and.pencil")
            }.buttonStyle(QuietButton()).help("Edit the script (⌘E)")
        }.padding(24)
    }

    private var editor: some View {
        ScriptEditorView(state: state).id(state.current.id).padding(.horizontal, 24)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(state.saveStatus == "Saved on this Mac" ? Palette.green : Palette.accent).frame(width: 5, height: 5)
            Text(state.saveStatus)
            Spacer()
            keyHint("SPACE", "Play / pause")
            keyHint("↑ ↓", "Pace")
            keyHint("← →", "Scroll")
            keyHint("R", "Reset")
            keyHint("B", "Blackout")
        }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.horizontal, 24).frame(height: 34)
    }
    private func keyHint(_ key: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.system(size: 9, weight: .medium, design: .monospaced)).padding(.horizontal, 5).padding(.vertical, 3)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 3))
            Text(title)
        }.padding(.leading, 13)
    }
}

struct LibrarySidebar: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(title: "YOUR SCRIPTS")
                Spacer()
                Button(action: state.newScript) { Image(systemName: "plus").font(.system(size: 13)) }
                    .buttonStyle(.plain).help("New script (⌘N)").accessibilityLabel("New script")
            }.padding(.horizontal, 20).padding(.top, 25).padding(.bottom, 17)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Find a script", text: $state.search).textFieldStyle(.plain).font(.system(size: 12))
            }.padding(9).background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 7)).padding(.horizontal, 14)
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(state.filteredScripts) { script in
                        Button { state.select(script.id) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "doc.text").font(.system(size: 16)).foregroundStyle(script.id == state.library.selectedID ? Palette.accent : Palette.muted).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(script.title).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text("\(script.wordCount) words  ·  \(timestamp(script.duration))").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 0)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(script.id == state.library.selectedID ? Color.white.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(alignment: .leading) { if script.id == state.library.selectedID { RoundedRectangle(cornerRadius: 2).fill(Palette.accent).frame(width: 3, height: 26) } }
                        }.buttonStyle(.plain).contextMenu {
                            Button("Duplicate") { state.select(script.id); state.duplicate() }
                            Button("Export text…") { state.select(script.id); state.exportScript() }
                            Divider()
                            Button("Delete…", role: .destructive) { state.select(script.id); state.deleteCurrent() }
                        }
                    }
                    if state.filteredScripts.isEmpty { Text("No matching scripts").font(.system(size: 12)).foregroundStyle(Palette.muted).padding(20) }
                }.padding(10)
            }
            Divider().overlay(Palette.border).padding(.horizontal, 18)
            HStack {
                SectionLabel(title: "CUE POINTS")
                Spacer()
                Button(action: state.addCue) { Image(systemName: "plus") }.buttonStyle(.plain).help("Bookmark the current position").accessibilityLabel("Add cue point")
            }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 12)
            CueList(state: state, playback: state.playback).frame(height: 166)
            HStack(spacing: 8) {
                Image(systemName: "internaldrive").font(.system(size: 13))
                Text("\(state.library.scripts.count) scripts · Local library").font(.system(size: 10))
            }.foregroundStyle(Palette.muted).padding(20)
        }.background(Palette.sidebar)
    }
}

struct CueList: View {
    @ObservedObject var state: AppState
    @ObservedObject var playback: Playback
    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(state.current.cues.enumerated()), id: \.element.id) { index, cue in
                    Button { playback.scrub(cue.progress) } label: {
                        HStack(spacing: 9) {
                            Text(String(format: "%02d", index + 1)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.accent.opacity(0.8))
                            Text(cue.title).lineLimit(1).font(.system(size: 11))
                            Spacer(minLength: 1)
                            Text(timestamp(cue.progress * state.current.duration)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
                        }.padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Jump to \(cue.title)").contextMenu {
                        Button("Remove cue", role: .destructive) { state.update { $0.cues.removeAll { $0.id == cue.id } } }
                    }
                }
                if state.current.cues.isEmpty { Text("Add a cue to jump back to a\nkey moment in your script.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4).padding(12) }
            }.padding(.horizontal, 10)
        }
    }
}

struct PreviewPanel: View {
    @ObservedObject var state: AppState
    @ObservedObject var playback: Playback
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(playback.transport.isPlaying ? Palette.green : Palette.muted).frame(width: 5, height: 5)
                Text(playback.transport.isPlaying ? (playback.voiceDrive?.speaking == false ? playback.voiceDrive?.holdReason.uppercased() ?? "WAITING FOR SPEECH" : "PROMPTING") : "PRODUCER PREVIEW").tracking(1.3)
                Spacer()
                Image(systemName: "hand.draw")
                Text("Scroll or drag to prompt manually")
            }.font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.muted).padding(.horizontal, 17).frame(height: 39)
            ZStack {
                PromptCanvas(script: state.current, progress: playback.transport.progress, onScroll: { delta in playback.scrub(playback.transport.progress + delta) }, onGuideChange: { position in state.update { $0.settings.guidePosition = position } })
                if state.current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.cursor").font(.system(size: 30)).foregroundStyle(Palette.accent)
                        Text("A blank page. A fresh take.").font(.system(size: 21, weight: .medium))
                        Button("Write your script", action: state.toggleEditing).buttonStyle(QuietButton())
                    }
                }
                if playback.transport.countdownRemaining > 0 {
                    Color.black.opacity(0.65)
                    VStack(spacing: 8) {
                        Text("GET READY").font(.system(size: 10, weight: .semibold)).tracking(3).foregroundStyle(Palette.accent)
                        Text("\(Int(ceil(playback.transport.countdownRemaining)))").font(.system(size: 86, weight: .medium, design: .rounded))
                    }
                }
                if playback.isBlackedOut {
                    VStack { Spacer(); Label("Talent output is blacked out", systemImage: "eye.slash.fill")
                        .font(.system(size: 11, weight: .medium)).padding(10).background(.black.opacity(0.85), in: Capsule()).padding(18) }.allowsHitTesting(false)
                }
            }.clipped()
            HStack {
                Image(systemName: state.outputScreenID == nil ? "display" : "display.2")
                Text(state.outputName.map { "Live on \($0)" } ?? "Talent display not connected")
                Spacer()
                Text("Operator view stays unmirrored")
            }.font(.system(size: 9)).foregroundStyle(Palette.muted).padding(.horizontal, 16).frame(height: 33)
        }
        .background(Color(red: 0.055, green: 0.06, blue: 0.069))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
    }
}

struct TransportBar: View {
    @ObservedObject var state: AppState
    @ObservedObject var playback: Playback
    @ObservedObject var voice: VoiceController
    var compact = false
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Text(timestamp(playback.transport.progress * playback.duration)).foregroundStyle(Color.white.opacity(0.85))
                Slider(value: Binding(get: { playback.transport.progress }, set: { playback.scrub($0) }), in: 0...1)
                    .tint(Palette.accent).accessibilityLabel("Script position").help("Move the script; active voice prompting waits here for a retake")
                Text("−" + timestamp(playback.remaining)).foregroundStyle(Palette.muted)
            }.font(.system(size: 10, weight: .medium, design: .monospaced))
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ELAPSED").font(.system(size: 8, weight: .semibold)).tracking(1.4).foregroundStyle(Palette.muted)
                    Text(timestamp(playback.transport.elapsed)).font(.system(size: 21, weight: .regular, design: .monospaced))
                }.frame(width: 83, alignment: .leading)
                Spacer(minLength: 0)
                iconButton("backward.end", help: "Reset to beginning (R)", action: playback.reset)
                iconButton("backward.frame", help: "Previous cue") { state.jumpCue(forward: false) }
                Button {
                    if state.isEditing { state.toggleEditing() }
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    state.togglePlayback()
                } label: {
                    Image(systemName: voice.isStarting ? "stop.fill" : (playback.transport.isPlaying ? "pause.fill" : "play.fill"))
                        .font(.system(size: 21, weight: .semibold)).foregroundStyle(Palette.background)
                        .frame(width: 68, height: 48).background(Palette.accent, in: RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain).help("Play / pause (Space)").accessibilityLabel(voice.isStarting ? "Cancel voice startup" : (playback.transport.isPlaying ? "Pause" : "Play"))
                    .disabled(state.current.wordCount == 0)
                iconButton("forward.frame", help: "Next cue") { state.jumpCue(forward: true) }
                iconButton(playback.isBlackedOut ? "eye.slash.fill" : "eye", help: "Toggle talent blackout (B)") { playback.isBlackedOut.toggle() }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("PACE").font(.system(size: 8, weight: .semibold)).tracking(1.4).foregroundStyle(Palette.muted)
                    (Text("\(Int(playback.voiceDrive?.wordsPerMinute ?? state.current.settings.wordsPerMinute))").font(.system(size: 21, weight: .regular, design: .monospaced)) + Text(" wpm").font(.system(size: 10)).foregroundColor(Palette.muted))
                }.frame(width: 83, alignment: .trailing)
            }
            VoicePlaybackStatus(voice: voice)
        }.padding(compact ? 18 : 0).background(Palette.background)
    }
    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 17)).frame(width: 24, height: 34) }
            .buttonStyle(.plain).foregroundStyle(Palette.muted).help(help).accessibilityLabel(help)
    }
}

struct Inspector: View {
    @ObservedObject var state: AppState
    @ObservedObject var voice: VoiceController
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                SectionLabel(title: "PROMPT SETTINGS")
                VoicePromptControls(state: state, voice: voice)
                if !voice.enabled {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Reading pace", systemImage: "speedometer").font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(state.current.settings.wordsPerMinute))").font(.system(size: 37, weight: .light, design: .rounded)).foregroundStyle(Palette.accent)
                        Text("words / min").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Spacer()
                        Stepper("Reading pace", value: state.setting(\.wordsPerMinute), in: 30...300, step: 5).labelsHidden()
                    }
                    Slider(value: state.setting(\.wordsPerMinute), in: 30...300, step: 5).accessibilityLabel("Reading pace")
                    HStack { Text("RELAXED"); Spacer(); Text("BRISK") }.font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(Palette.muted)
                }.padding(15).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 17) {
                    SectionLabel(title: "APPEARANCE")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Typeface").font(.system(size: 11))
                        SettingsMenuField(title: "Typeface", value: state.current.settings.typeface.name) {
                            ForEach(ScriptTypeface.allCases) { typeface in
                                Button { state.update { $0.settings.typeface = typeface } } label: {
                                    if state.current.settings.typeface == typeface { Label(typeface.name, systemImage: "checkmark") }
                                    else { Text(typeface.name) }
                                }
                            }
                        }.controlSize(.regular)
                    }
                    parameter("Text size", value: String(Int(state.current.settings.fontSize))) {
                        Slider(value: state.setting(\.fontSize), in: 32...90, step: 2).accessibilityLabel("Text size")
                    }
                    parameter("Line spacing", value: String(format: "%.1f×", state.current.settings.lineSpacing)) {
                        Slider(value: state.setting(\.lineSpacing), in: 1.1...2, step: 0.1).accessibilityLabel("Line spacing")
                    }
                    parameter("Side margins", value: "\(Int(state.current.settings.margin / 10))%") {
                        Slider(value: state.setting(\.margin), in: 55...220, step: 5).accessibilityLabel("Side margins")
                    }
                    Toggle("Reading guide", isOn: state.setting(\.showGuide))
                    if state.current.settings.showGuide {
                        parameter("Guide position", value: "\(Int((state.current.settings.guidePosition * 100).rounded()))%") {
                            Slider(value: state.setting(\.guidePosition), in: 0.15...0.65, step: 0.01).accessibilityLabel("Reading guide position")
                        }
                        parameter("Guide height", value: "\(Int(state.current.settings.guideLines)) \(state.current.settings.guideLines == 1 ? "line" : "lines")") {
                            Slider(value: state.setting(\.guideLines), in: 1...3, step: 1).accessibilityLabel("Reading guide height")
                        }
                        Text("Drag the orange arrow to reposition.").font(.system(size: 9)).foregroundStyle(Palette.muted)
                    }
                    Toggle("Focus current line", isOn: state.setting(\.focusMode))
                }.font(.system(size: 11)).toggleStyle(.switch).controlSize(.mini)
                Divider().overlay(Palette.border)
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "TALENT DISPLAY")
                    OutputMenu(state: state)
                    if let name = state.outputName {
                        HStack(spacing: 5) { Circle().fill(Palette.green).frame(width: 5, height: 5); Text(name).lineLimit(1); Spacer(); Button("Stop") { state.stopOutput() }.buttonStyle(.plain).foregroundStyle(Palette.accent) }.font(.system(size: 10))
                    } else {
                        Text(state.secondaryScreens.isEmpty ? "Connect an extended display for your talent, or open a rehearsal window." : "Send the script to a display. Your controls stay here.")
                            .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                    }
                    Toggle("Mirror horizontally", isOn: state.setting(\.mirrorHorizontal))
                    Toggle("Flip vertically", isOn: state.setting(\.mirrorVertical))
                }.font(.system(size: 11)).toggleStyle(.switch).controlSize(.mini)
                Divider().overlay(Palette.border)
                HStack {
                    Text("Start countdown").font(.system(size: 11))
                    Spacer()
                    Picker("Start countdown", selection: state.setting(\.countdown)) {
                        Text("Off").tag(0); Text("3 sec").tag(3); Text("5 sec").tag(5); Text("10 sec").tag(10)
                    }.labelsHidden().frame(width: 76).controlSize(.small)
                }
            }.padding(20)
        }.background(Palette.sidebar.opacity(0.6))
    }
    private func parameter<Content: View>(_ title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text(value).foregroundStyle(Palette.muted).monospacedDigit() }
            content()
        }
    }
}

struct OutputMenu: View {
    @ObservedObject var state: AppState
    var prominent = false
    var body: some View {
        Menu {
            if state.secondaryScreens.isEmpty { Text("No secondary display detected") }
            ForEach(state.secondaryScreens, id: \.self) { screen in
                Button("Send to \(screen.localizedName) (\(Int(screen.frame.width)) × \(Int(screen.frame.height)))") { state.startOutput(on: screen) }
            }
            Divider()
            Button("Open rehearsal window") { state.present() }
            if state.outputScreenID != nil { Button("Stop talent output") { state.stopOutput() } }
        } label: {
            Label(state.outputScreenID == nil ? (prominent ? "Send to display" : "Choose display") : "Output live", systemImage: "display.2")
                .font(.system(size: 11, weight: .medium)).frame(maxWidth: prominent ? nil : .infinity)
        }
        .menuStyle(.borderlessButton).fixedSize(horizontal: prominent, vertical: true)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(prominent ? Palette.accent.opacity(0.14) : Palette.panel, in: RoundedRectangle(cornerRadius: 7))
        .foregroundStyle(prominent ? Palette.accent : Color.white.opacity(0.8))
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.muted)
            if let trailing { Spacer(); Text(trailing).font(.system(size: 9)).foregroundStyle(Palette.muted.opacity(0.7)) }
        }
    }
}

struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color.white.opacity(configuration.isPressed ? 0.1 : 0.045), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border, lineWidth: 1))
    }
}
