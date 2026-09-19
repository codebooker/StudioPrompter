import SwiftUI
import AppKit

@main
struct PrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()
    var body: some Scene {
        Window("Prompter Studio", id: "workspace") {
            WorkspaceView(state: state)
                .onAppear { delegate.state = state; NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1380, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Script", action: state.newScript).keyboardShortcut("n")
                Button("Import Script…", action: state.importScript).keyboardShortcut("o")
                Divider()
                Button("Save Library", action: state.save).keyboardShortcut("s")
                Menu("Export Script") {
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
                Button("Add Cue Point", action: state.addCue).keyboardShortcut("b", modifiers: .command)
                Button("Previous Cue") { state.jumpCue(forward: false) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Next Cue") { state.jumpCue(forward: true) }.keyboardShortcut(.rightArrow, modifiers: .command)
                Divider()
                Button("Toggle Talent Blackout") { state.playback.isBlackedOut.toggle() }.keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Open Rehearsal Window") { state.present() }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Stop Talent Output", action: state.stopOutput).keyboardShortcut(".", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Prompter Help") {
                    let alert = NSAlert()
                    alert.messageText = "Your producer workspace"
                    alert.informativeText = "Connect a second monitor using an extended desktop, then choose Send to display. The talent sees only the script; you control everything here.\n\nScroll with your mouse or trackpad, drag the preview, or use the position slider to prompt manually. Manual scrolling pauses fixed-speed autoplay. With voice prompting active, the mic stays on and following resumes when you read from the new position.\n\nSpace: Play / pause\n↑ / ↓: Change pace\n← / →: Scroll backward / forward\nR: Reset    B: Black out talent display\n⌘B: Add a cue at the current position\n⌘E: Edit script\n⌘⇧.: Stop talent output\n\nMirror settings apply only to the talent display and rehearsal window. Your library saves automatically on this Mac."
                    alert.runModal()
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular) }
    func applicationWillTerminate(_ notification: Notification) { state?.voice.stop(); state?.save(); state?.stopOutput() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
