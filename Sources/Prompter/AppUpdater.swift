import AppKit
import Combine
import Sparkle
import SwiftUI

/// Sparkle owns download, signature verification, replacement, and relaunch.
/// Update checks are explicitly requested by the producer, never during a take.
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    private var controller: SPUStandardUpdaterController!
    weak var state: AppState?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }
    func checkForUpdates() { controller.checkForUpdates(nil) }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if let state, state.playback.transport.isPlaying || state.voice.isListening || state.voice.isStarting {
            throw NSError(domain: "StudioPrompter.Updates", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Pause prompting and stop the microphone before checking for updates."])
        }
    }
    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        guard let state else { return false }
        if state.playback.transport.isPlaying || state.voice.isListening || state.voice.isStarting {
            state.errorMessage = "Pause prompting and stop the microphone, then check for updates again to finish installing."
            return false
        }
        state.save()
        // A full disk or recovery-mode library must not turn an update into lost work.
        return state.saveStatus == "Saved on this Mac"
    }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        // Installation is user-confirmed. Preserve any edits made during download.
        state?.pausePlayback(stopListening: true)
        state?.save()
    }
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) { state?.save() }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updater: AppUpdater
    @ObservedObject var playback: Playback
    @ObservedObject var voice: VoiceController
    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!updater.canCheckForUpdates || playback.transport.isPlaying || voice.isListening || voice.isStarting)
            .help("Check published StudioPrompter releases on GitHub. Pause prompting first.")
    }
}
