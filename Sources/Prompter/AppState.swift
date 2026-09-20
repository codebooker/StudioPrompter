import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PrompterCore
import PrompterLayout

final class Playback: ObservableObject {
    @Published var transport = Transport()
    @Published var isBlackedOut = false
    var duration: Double = 0
    var countdown = 3
    var wordCount = 0
    @Published var voiceDrive: VoiceDrive?
    var onManualPosition: ((Bool) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime

    init() {
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let delta = now - self.lastTick
            self.lastTick = now
            if self.transport.isPlaying {
                // Pause across sleep or a stalled run loop instead of skipping the script.
                if delta > 1 { self.transport.pause() }
                else if let voice = self.voiceDrive {
                    if voice.followsScript {
                        self.transport.follow(seconds: delta, target: voice.speaking ? voice.target : nil, lineStep: voice.lineStep)
                    } else {
                        self.transport.adapt(seconds: delta, duration: Double(self.wordCount) / max(1, voice.wordsPerMinute) * 60, speaking: voice.speaking, target: voice.target, lineStep: voice.lineStep)
                    }
                } else { self.transport.tick(seconds: delta, duration: self.duration) }
                if !self.transport.isPlaying { self.onPlaybackEnded?() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func toggle() {
        if transport.isPlaying { transport.pause() }
        else { lastTick = ProcessInfo.processInfo.systemUptime; transport.play(countdown: transport.progress == 0 ? countdown : 0, hasContent: duration > 0) }
    }
    func reset() { transport.reset(); isBlackedOut = false; onManualPosition?(false) }
    func seek(_ progress: Double) { scrub(progress) }
    func scrub(_ progress: Double) {
        let keepListening = transport.isPlaying && voiceDrive != nil
        transport.reposition(to: progress, preservingPlayback: keepListening)
        onManualPosition?(keepListening && transport.isPlaying)
    }
    var remaining: Double { max(0, (1 - transport.progress) * (voiceDrive.map { Double(wordCount) / max(1, $0.wordsPerMinute) * 60 } ?? duration)) }
}

final class AppState: ObservableObject {
    @Published var library: Library
    @Published var isEditing = false
    @Published var search = ""
    @Published var errorMessage: String?
    @Published var saveStatus = "Saved on this Mac"
    @Published var screens: [NSScreen] = NSScreen.screens
    @Published var outputScreenID: String?
    @Published private(set) var webcamLayoutActive = false
    @Published var cameraGuidePosition = 0.095
    @Published var cameraViewSize = CGSize(width: 580, height: 240)
    private var cameraWindow: CameraPromptWindow?
    private var cameraSizePanel: NSPanel?
    let playback = Playback()
    lazy var voice = VoiceController(state: self)
    let storeURL: URL
    weak var activeEditor: ScriptEditorSession?
    private var pendingSave: DispatchWorkItem?
    private var canSave = true
    private var keyMonitor: Any?
    private var outputWindow: NSWindow?
    private var voiceWindow: NSWindow?
    private var screenObserver: NSObjectProtocol?

    init(storeURL: URL? = nil) {
        self.storeURL = storeURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Prompter/library.json")
        if FileManager.default.fileExists(atPath: self.storeURL.path) {
            do { library = try LibraryStore.load(from: self.storeURL) }
            catch {
                library = Library(scripts: Samples.scripts)
                canSave = false
                errorMessage = "Your library could not be opened. The original file has been preserved at \(self.storeURL.path). Export any new work before quitting. \(error.localizedDescription)"
            }
        } else { library = Library(scripts: Samples.scripts) }
        if library.scripts.isEmpty { library = Library(scripts: [Script(title: "Untitled script", text: "")]) }
        if !library.scripts.contains(where: { $0.id == library.selectedID }) { library.selectedID = library.scripts.first?.id }
        configurePlayback()
        playback.onManualPosition = { [weak self] keepListening in
            guard let self else { return }
            if keepListening || (self.voice.handsFreeCommands && self.voice.isListening) { self.voice.beginRetake() }
            else { self.voice.stop(); self.voice.resetAnchor() }
        }
        playback.onPlaybackEnded = { [weak self] in self?.pausePlayback() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.screens = NSScreen.screens
            if self.cameraWindow?.isVisible == true { self.centerCameraView() }
            if let id = self.outputScreenID {
                if let screen = self.screens.first(where: { Self.screenID($0) == id }) {
                    self.outputWindow?.setFrame(screen.frame, display: true)
                } else { self.stopOutput(); self.pausePlayback(stopListening: true) }
            }
        }
    }

    var current: Script { library.scripts.first(where: { $0.id == library.selectedID }) ?? library.scripts[0] }
    func togglePlayback() {
        if playback.transport.isPlaying || voice.isStarting { pausePlayback(); return }
        if voice.enabled {
            if voice.isListening {
                if voice.handsFreeCommands { voice.beginRetake() }
                playback.toggle()
            }
            else { voice.start(playWhenReady: true) }
        } else { playback.toggle() }
    }
    func pausePlayback(stopListening: Bool = false) {
        if !stopListening && voice.handsFreeCommands && voice.isListening { voice.pauseForCommands() }
        else { voice.stop(); playback.transport.pause() }
    }
    #if EXPERIMENTAL_COMMANDS
    func performVoiceCommand(_ command: VoiceCommand) -> String {
        guard (!isEditing && NSApp.modalWindow == nil) || command == .pause || command == .stopListening else { return "Close the editor or dialog to use voice commands" }
        let position = playback.transport.progress
        switch command {
        case .pause:
            voice.pauseForCommands(); return "Paused · say Hey Teleprompter, resume"
        case .resume:
            playback.transport.play(countdown: 0, hasContent: current.wordCount > 0)
            voice.beginRetake(); return "Ready · start reading"
        case .cancel: return "Command cancelled"
        case .stopListening:
            voice.stop(); return "Microphone off · use Play to listen again"
        case .followScript, .adaptivePace, .toggleVoiceMode:
            voice.mode = command == .toggleVoiceMode ? (voice.mode == .follow ? .pace : .follow) : (command == .followScript ? .follow : .pace)
            voice.beginRetake()
            return voice.mode.rawValue
        case .guidePosition(let direction) where cameraWindow?.isVisible == true:
            cameraGuidePosition = min(1, max(0, cameraGuidePosition + Double(direction.signum()) * 0.03))
            return "Webcam reading guide moved \(direction < 0 ? "up" : "down")"
        case .font, .fontSize, .typeface, .lineSpacing, .margins, .guideVisible, .guidePosition, .guideHeight, .guideLines, .focusLine:
            let offset = ScriptCueLayout(current).offset(at: position)
            let playing = playback.transport.isPlaying
            var notice = "Appearance updated"
            update { notice = command.applyAppearance(to: &$0.settings) ?? notice }
            playback.transport.reposition(to: ScriptCueLayout(current).progress(at: offset), preservingPlayback: playing)
            voice.beginRetake()
            return notice
        default:
            guard let destination = VoiceNavigation.destination(for: command, script: current, progress: position) else { return "That paragraph or bookmark isn’t in this script" }
            playback.transport.reposition(to: min(destination, 0.999999), preservingPlayback: false)
            playback.transport.play(countdown: 0, hasContent: current.wordCount > 0)
            voice.beginRetake()
            switch command {
            case .lines(let count): return "Moved \(abs(count)) \(abs(count) == 1 ? "line" : "lines") \(count < 0 ? "back" : "forward")"
            case .paragraph(let delta): return delta == 0 ? "Restarted paragraph" : "Moved \(abs(delta)) \(abs(delta) == 1 ? "paragraph" : "paragraphs") \(delta < 0 ? "back" : "forward")"
            case .paragraphNumber(let number): return "Paragraph \(number)"
            case .lastParagraph: return "Last paragraph"
            case .cueNumber(let number): return "Bookmark \(number)"
            case .top: return "Back to the beginning"
            default: return "\(command == .cue(-1) ? "Previous" : "Next") bookmark"
            }
        }
    }
    #endif
    var filteredScripts: [Script] {
        library.scripts.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }
    }
    func select(_ id: UUID) {
        guard id != library.selectedID else { return }
        voice.stop()
        playback.reset()
        library.selectedID = id
        configurePlayback()
        scheduleSave()
    }
    func update(_ change: (inout Script) -> Void) {
        guard let index = library.scripts.firstIndex(where: { $0.id == library.selectedID }) else { return }
        change(&library.scripts[index])
        library.scripts[index].modified = Date()
        configurePlayback()
        scheduleSave()
    }
    func setting<T>(_ path: WritableKeyPath<PromptSettings, T>) -> Binding<T> {
        Binding(get: { self.current.settings[keyPath: path] }, set: { value in self.update { $0.settings[keyPath: path] = value } })
    }
    func configurePlayback() {
        if let index = library.scripts.firstIndex(where: { $0.id == library.selectedID }), current.cues.contains(where: { $0.characterOffset != nil }) {
            let script = current
            let layout = ScriptCueLayout(script)
            var cues = script.cues
            for cueIndex in cues.indices {
                if let offset = cues[cueIndex].characterOffset { cues[cueIndex].progress = layout.progress(at: offset) }
            }
            cues.sort { $0.progress < $1.progress }
            if cues != script.cues { library.scripts[index].cues = cues }
        }
        playback.duration = current.duration
        playback.countdown = current.settings.countdown
        playback.wordCount = current.wordCount
    }
    func scheduleSave() {
        pendingSave?.cancel()
        saveStatus = canSave ? "Saving…" : "Library recovery mode"
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func save() {
        pendingSave?.cancel()
        guard canSave else { return }
        do { try LibraryStore.save(library, to: storeURL); saveStatus = "Saved on this Mac" }
        catch { saveStatus = "Could not save"; errorMessage = "Could not save your library: \(error.localizedDescription)" }
    }
    func newScript() {
        voice.stop()
        playback.reset()
        let script = Script(title: "Untitled script", text: "")
        library.scripts.insert(script, at: 0)
        library.selectedID = script.id
        search = ""
        isEditing = true
        configurePlayback()
        scheduleSave()
    }
    func duplicate() {
        var script = current
        script.id = UUID()
        script.title += " copy"
        library.scripts.insert(script, at: 0)
        select(script.id)
    }
    func deleteCurrent() {
        let alert = NSAlert()
        alert.messageText = "Delete “\(current.title)”?"
        alert.informativeText = "This removes the script from your local library."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        pausePlayback(stopListening: true)
        library.scripts.removeAll { $0.id == library.selectedID }
        if library.scripts.isEmpty { library.scripts.append(Script(title: "Untitled script", text: "")) }
        library.selectedID = library.scripts[0].id
        playback.reset()
        configurePlayback()
        scheduleSave()
    }
    func toggleEditing() {
        pausePlayback(stopListening: true)
        isEditing.toggle()
        if !isEditing { NSApp.keyWindow?.makeFirstResponder(nil) }
    }
    func anchorCues() {
        guard current.cues.contains(where: { $0.characterOffset == nil }) else { return }
        let layout = ScriptCueLayout(current)
        update { script in
            for index in script.cues.indices where script.cues[index].characterOffset == nil {
                script.cues[index].characterOffset = layout.offset(at: script.cues[index].progress)
            }
        }
    }
    func addCue() {
        if isEditing, let activeEditor { activeEditor.addCue(); return }
        let progress = playback.transport.progress
        let words = current.text.split(whereSeparator: { $0.isWhitespace })
        let index = min(max(0, Int(Double(words.count) * progress)), max(0, words.count - 1))
        let title = words.isEmpty ? "New bookmark" : words.dropFirst(index).prefix(5).joined(separator: " ")
        let offset = ScriptCueLayout(current).offset(at: progress)
        update { $0.cues.append(Cue(title: title, progress: progress, characterOffset: offset)); $0.cues.sort { $0.progress < $1.progress } }
    }
    func jumpCue(forward: Bool) {
        let p = playback.transport.progress
        let cues = current.cues.sorted { $0.progress < $1.progress }
        let cue = forward ? cues.first { $0.progress > p + 0.005 } : cues.last { $0.progress < p - 0.005 }
        playback.seek(cue?.progress ?? (forward ? 1 : 0))
    }
    func importScript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .rtf, .rtfd, UTType(filenameExtension: "docx")!, UTType(filenameExtension: "doc")!]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do {
                let title = url.deletingPathExtension().lastPathComponent
                var script: Script
                if ["rtf", "rtfd", "doc", "docx"].contains(url.pathExtension.lowercased()) {
                    let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
                    script = Script(title: title, text: attributed.string)
                    script.emphasis = ScriptTypography.emphasis(in: attributed)
                } else {
                    var encoding = String.Encoding.utf8
                    let text = try String(contentsOf: url, usedEncoding: &encoding)
                    script = ["md", "markdown"].contains(url.pathExtension.lowercased())
                        ? ScriptMarkdown.decode(text, title: title) : Script(title: title, text: text)
                }
                library.scripts.insert(script, at: 0)
                select(script.id)
            } catch { errorMessage = "Could not import \(url.lastPathComponent): \(error.localizedDescription)" }
        }
        search = ""
        isEditing = false
        scheduleSave()
    }
    func exportScript(rtf: Bool = false, markdown: Bool = false) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = markdown ? [UTType(filenameExtension: "md") ?? .plainText] : (rtf ? [.rtf] : [.plainText])
        panel.nameFieldStringValue = current.title + (markdown ? ".md" : (rtf ? ".rtf" : ".txt"))
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if markdown {
                try ScriptMarkdown.encode(current).write(to: url, atomically: true, encoding: .utf8)
            } else if rtf {
                let attributed = ScriptTypography.editorText(current)
                let data = try attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                try data.write(to: url, options: .atomic)
            } else { try current.text.write(to: url, atomically: true, encoding: .utf8) }
        } catch { errorMessage = "Could not export script: \(error.localizedDescription)" }
    }
    static func screenID(_ screen: NSScreen) -> String { String(describing: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? screen.localizedName) }
    func toggleFullScreen() {
        let window = NSApp.windows.first { $0.identifier?.rawValue == "workspace" }
        window?.toggleFullScreen(nil)
    }
    func openVoiceLab() {
        if let voiceWindow { voiceWindow.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 760, height: min(820, (NSScreen.main?.visibleFrame.height ?? 900) - 80)), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "StudioPrompter — Voice settings"
        window.identifier = NSUserInterfaceItemIdentifier("voice-lab")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: VoiceLabView(state: self, voice: voice).preferredColorScheme(.dark))
        window.center()
        window.makeKeyAndOrderFront(nil)
        voiceWindow = window
    }
    func closeVoiceLab() { voiceWindow?.close() }
    var outputName: String? { webcamLayoutActive ? "Webcam Layout" : screens.first(where: { Self.screenID($0) == outputScreenID })?.localizedName }
    var secondaryScreens: [NSScreen] { screens.filter { Self.screenID($0) != screens.first.map(Self.screenID) } }
    func startOutput(on screen: NSScreen) {
        stopOutput()
        // A borderless window fills just this display, without entering a macOS Space
        // or hiding the producer's controls on the other monitor.
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("talent-output")
        window.title = "Prompter — Talent Output"
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: TalentOutputView(state: self).preferredColorScheme(.dark))
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        outputWindow = window
        outputScreenID = Self.screenID(screen)
    }
    func stopOutput() {
        outputWindow?.close(); outputWindow = nil; outputScreenID = nil
        closeCameraView()
    }
    private var cameraScreen: NSScreen? {
        screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        } ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "workspace" })?.screen ?? NSScreen.main
    }
    func openCameraView() {
        guard let screen = cameraScreen else { return }
        if isEditing { toggleEditing() }
        if outputScreenID != nil { stopOutput() }
        webcamLayoutActive = true
        if let cameraWindow { cameraWindow.makeKeyAndOrderFront(nil); return }
        cameraGuidePosition = current.settings.guidePosition * 0.25
        let rect = CameraViewGeometry.frame(screen: screen.frame, visible: screen.visibleFrame, safeTop: screen.safeAreaInsets.top)
        let window = CameraPromptWindow(contentRect: rect, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.title = "StudioPrompter — Webcam Layout"
        window.identifier = NSUserInterfaceItemIdentifier("camera-view")
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 360, height: 180)
        window.maxSize = NSSize(width: 1000, height: 600)
        window.contentView = NSHostingView(rootView: CameraPromptView(state: self, playback: playback, voice: voice).preferredColorScheme(.dark))
        window.delegate = window
        window.onResize = { [weak self] size in self?.cameraViewSize = size }
        window.onClose = { [weak self] in
            self?.cameraSizePanel?.close()
            self?.webcamLayoutActive = false
        }
        cameraWindow = window; cameraViewSize = rect.size
        window.setFrame(rect, display: true)
        window.makeKeyAndOrderFront(nil)
    }
    func openCameraSizeControls() {
        guard let cameraWindow else { return }
        if let cameraSizePanel, cameraSizePanel.isVisible {
            cameraSizePanel.makeKeyAndOrderFront(nil)
            return
        }
        let panel = cameraSizePanel ?? NSPanel(contentRect: NSRect(x: 0, y: 0, width: 316, height: 212),
                                              styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Webcam Layout size"
        panel.identifier = NSUserInterfaceItemIdentifier("camera-size")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CameraSizeControls(state: self))
        // Position once when opened. Do not attach as a child window or track the
        // camera frame: the controls must remain stationary throughout resizing.
        if let screen = cameraWindow.screen ?? cameraScreen {
            let visible = screen.visibleFrame
            let x = min(max(visible.minX, cameraWindow.frame.midX - panel.frame.width / 2), visible.maxX - panel.frame.width)
            let y = min(max(visible.minY, cameraWindow.frame.minY - panel.frame.height - 12), visible.maxY - panel.frame.height)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        cameraSizePanel = panel
        panel.makeKeyAndOrderFront(nil)
    }
    func closeCameraSizeControls() {
        cameraSizePanel?.close()
        if cameraWindow?.isVisible == true { cameraWindow?.makeKeyAndOrderFront(nil) }
    }
    func centerCameraView() {
        guard let window = cameraWindow, let screen = window.screen ?? cameraScreen else { return }
        window.setFrame(CameraViewGeometry.frame(screen: screen.frame, visible: screen.visibleFrame, safeTop: screen.safeAreaInsets.top, size: window.frame.size), display: true)
    }
    func resizeCameraView(width: CGFloat? = nil, height: CGFloat? = nil) {
        guard let window = cameraWindow, let screen = window.screen ?? cameraScreen else { return }
        let available = screen.visibleFrame
        let size = CGSize(width: min(max(360, width ?? window.frame.width), available.width - 16),
                          height: min(max(180, height ?? window.frame.height), available.height - 16))
        // Resize around the horizontal center while keeping the upper reading edge by the camera.
        let x = min(max(available.minX, window.frame.midX - size.width / 2), available.maxX - size.width)
        let top = min(window.frame.maxY, screen.frame.maxY - screen.safeAreaInsets.top, available.maxY)
        window.setFrame(CGRect(x: x, y: max(available.minY, top - size.height), width: size.width, height: size.height), display: true)
    }
    func closeCameraView() {
        cameraSizePanel?.close(); cameraWindow?.close()
        webcamLayoutActive = false
    }
    func showProducerWorkspace() {
        NSApp.windows.first(where: { $0.identifier?.rawValue == "workspace" })?.makeKeyAndOrderFront(nil)
    }
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option),
              !(NSApp.keyWindow is NSPanel), NSApp.modalWindow == nil else { return event }
        // Esc still stops the mic when the script-search field has focus.
        if event.keyCode == 53 { pausePlayback(stopListening: true); return event }
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable { return event }
        switch event.keyCode {
        case 49: if !isEditing { togglePlayback(); return nil }
        case 126: update { $0.settings.wordsPerMinute = min(300, $0.settings.wordsPerMinute + 5) }; return nil
        case 125: update { $0.settings.wordsPerMinute = max(30, $0.settings.wordsPerMinute - 5) }; return nil
        case 123: playback.scrub(playback.transport.progress - 0.025); return nil
        case 124: playback.scrub(playback.transport.progress + 0.025); return nil
        default:
            if event.charactersIgnoringModifiers?.lowercased() == "r" { playback.reset(); return nil }
            if event.charactersIgnoringModifiers?.lowercased() == "b" { playback.isBlackedOut.toggle(); return nil }
        }
        return event
    }
}

func timestamp(_ seconds: Double) -> String {
    let value = max(0, Int(ceil(seconds)))
    return String(format: "%02d:%02d", value / 60, value % 60)
}
