import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PrompterCore

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
    let playback = Playback()
    lazy var voice = VoiceController(state: self)
    let storeURL: URL
    private var pendingSave: DispatchWorkItem?
    private var canSave = true
    private var keyMonitor: Any?
    private var presentationWindows: [NSWindow] = []
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
            if keepListening { self.voice.beginRetake() }
            else { self.voice.stop(); self.voice.resetAnchor() }
        }
        playback.onPlaybackEnded = { [weak self] in self?.voice.stop() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.screens = NSScreen.screens
            if let id = self.outputScreenID {
                if let screen = self.screens.first(where: { Self.screenID($0) == id }) {
                    self.outputWindow?.setFrame(screen.frame, display: true)
                } else { self.stopOutput(); self.pausePlayback() }
            }
        }
    }

    var current: Script { library.scripts.first(where: { $0.id == library.selectedID }) ?? library.scripts[0] }
    func togglePlayback() {
        if playback.transport.isPlaying || voice.isStarting { pausePlayback(); return }
        if voice.enabled {
            if voice.isListening { playback.toggle() }
            else { voice.start(playWhenReady: true) }
        } else { playback.toggle() }
    }
    func pausePlayback() { voice.stop(); playback.transport.pause() }
    var filteredScripts: [Script] {
        library.scripts.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }
    }
    func select(_ id: UUID) {
        guard id != library.selectedID else { return }
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
    func configurePlayback() { playback.duration = current.duration; playback.countdown = current.settings.countdown; playback.wordCount = current.wordCount }
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
        library.scripts.removeAll { $0.id == library.selectedID }
        if library.scripts.isEmpty { library.scripts.append(Script(title: "Untitled script", text: "")) }
        library.selectedID = library.scripts[0].id
        playback.reset()
        configurePlayback()
        scheduleSave()
    }
    func toggleEditing() {
        pausePlayback()
        isEditing.toggle()
        if !isEditing { NSApp.keyWindow?.makeFirstResponder(nil) }
    }
    func addCue() {
        let progress = playback.transport.progress
        let words = current.text.split(whereSeparator: { $0.isWhitespace })
        let index = min(max(0, Int(Double(words.count) * progress)), max(0, words.count - 1))
        let title = words.isEmpty ? "New cue" : words.dropFirst(index).prefix(5).joined(separator: " ")
        update { $0.cues.append(Cue(title: title, progress: progress)); $0.cues.sort { $0.progress < $1.progress } }
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
                let text: String
                if ["rtf", "rtfd", "doc", "docx"].contains(url.pathExtension.lowercased()) {
                    text = try NSAttributedString(url: url, options: [:], documentAttributes: nil).string
                } else {
                    var encoding = String.Encoding.utf8
                    text = try String(contentsOf: url, usedEncoding: &encoding)
                }
                let script = Script(title: url.deletingPathExtension().lastPathComponent, text: text)
                library.scripts.insert(script, at: 0)
                select(script.id)
            } catch { errorMessage = "Could not import \(url.lastPathComponent): \(error.localizedDescription)" }
        }
        search = ""
        isEditing = false
        scheduleSave()
    }
    func exportScript(rtf: Bool = false) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = rtf ? [.rtf] : [.plainText]
        panel.nameFieldStringValue = current.title + (rtf ? ".rtf" : ".txt")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if rtf {
                let attributed = NSAttributedString(string: current.text, attributes: [.font: NSFont.systemFont(ofSize: 18)])
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
    var outputName: String? { screens.first(where: { Self.screenID($0) == outputScreenID })?.localizedName }
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
    func stopOutput() { outputWindow?.close(); outputWindow = nil; outputScreenID = nil }
    func present(on screen: NSScreen? = nil) {
        presentationWindows.removeAll { !$0.isVisible }
        let target = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let rect = NSRect(x: target.visibleFrame.minX + 80, y: target.visibleFrame.minY + 80, width: min(1100, target.visibleFrame.width - 160), height: min(760, target.visibleFrame.height - 160))
        let window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Prompter — Presentation"
        window.identifier = NSUserInterfaceItemIdentifier("presentation")
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PresentationView(state: self).preferredColorScheme(.dark))
        window.collectionBehavior = [.fullScreenPrimary]
        window.makeKeyAndOrderFront(nil)
        presentationWindows.append(window)
        if screen != nil { window.toggleFullScreen(nil) }
    }
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option),
              !(NSApp.keyWindow is NSPanel), NSApp.modalWindow == nil else { return event }
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable { return event }
        switch event.keyCode {
        case 49: if !isEditing || NSApp.keyWindow?.identifier?.rawValue == "presentation" { togglePlayback(); return nil }
        case 126: update { $0.settings.wordsPerMinute = min(300, $0.settings.wordsPerMinute + 5) }; return nil
        case 125: update { $0.settings.wordsPerMinute = max(30, $0.settings.wordsPerMinute - 5) }; return nil
        case 123: playback.scrub(playback.transport.progress - 0.025); return nil
        case 124: playback.scrub(playback.transport.progress + 0.025); return nil
        case 53: pausePlayback(); return event
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
