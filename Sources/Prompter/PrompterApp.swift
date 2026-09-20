import SwiftUI
import AppKit

@main
struct PrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()
    @StateObject private var updater = AppUpdater()
    var body: some Scene {
        Window("StudioPrompter", id: "workspace") {
            WorkspaceView(state: state)
                .onAppear { delegate.state = state; updater.state = state; NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1380, height: 860)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater, playback: state.playback, voice: state.voice)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Script", action: state.newScript).keyboardShortcut("n")
                Button("Import Script…", action: state.importScript).keyboardShortcut("o")
                Divider()
                Button("Save Library", action: state.save).keyboardShortcut("s")
                Menu("Export Script") {
                    Button("Markdown…") { state.exportScript(markdown: true) }
                    Button("Plain Text…") { state.exportScript() }
                    Button("Rich Text…") { state.exportScript(rtf: true) }
                }
                Button("Duplicate Script", action: state.duplicate).keyboardShortcut("d", modifiers: [.command, .shift])
            }
            CommandMenu("Prompt") {
                Button("Voice Settings…", action: state.openVoiceLab).keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Toggle Full Screen", action: state.toggleFullScreen).keyboardShortcut("f", modifiers: [.control, .command])
                Divider()
                Button("Play / Pause", action: state.togglePlayback).keyboardShortcut(.return, modifiers: .command)
                Button("Reset", action: state.playback.reset).keyboardShortcut("r", modifiers: .command)
                Button("Edit Script", action: state.toggleEditing).keyboardShortcut("e")
                Divider()
                Button("Add Bookmark", action: state.addCue).keyboardShortcut("b", modifiers: [.command, .option])
                Button("Previous Bookmark") { state.jumpCue(forward: false) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Next Bookmark") { state.jumpCue(forward: true) }.keyboardShortcut(.rightArrow, modifiers: .command)
                Divider()
                Button("Toggle Talent Blackout") { state.playback.isBlackedOut.toggle() }.keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Open Webcam Layout", action: state.openCameraView).keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Stop Output", action: state.stopOutput).keyboardShortcut(".", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Prompter Help") {
                    let alert = NSAlert()
                    alert.messageText = "Your producer workspace"
                    alert.informativeText = "Connect a second monitor using an extended desktop, then select it from Prompter Output. For solo recording, choose Webcam Layout from the same menu to read near your webcam. The talent sees only the script; you control everything here.\n\nScroll with your mouse or trackpad, drag the preview, or use the position slider to prompt manually. Manual scrolling pauses fixed-speed autoplay. With voice prompting active, the mic stays on and following resumes when you read from the new position.\n\nSpace: Play / pause\n↑ / ↓: Change pace\n← / →: Scroll backward / forward\nR: Reset    B: Black out talent display\n⌘⌥B: Add a bookmark at the current position\n⌘B / ⌘U: Bold / underline selected script text\n⌘E: Edit script\n⌘⇧.: Stop output\n\nMirror settings apply only to the talent display. Your library saves automatically on this Mac."
                    alert.runModal()
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular) }
    #if EXPERIMENTAL_COMMANDS
    private var terminating = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        guard let state else { return .terminateNow }
        terminating = true
        state.voice.stop(); state.save(); state.stopOutput()
        Task { @MainActor in
            // llama.cpp's global Metal destructor requires every model/context to be freed first.
            await state.voice.assistant.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    #endif
    func applicationWillTerminate(_ notification: Notification) { state?.voice.stop(); state?.save(); state?.stopOutput() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
