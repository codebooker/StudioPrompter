#if EXPERIMENTAL_COMMANDS
import Foundation
import SwiftUI
import PrompterCore
import PrompterCommands

/// Optional natural-language fallback. Ordinary prompting never needs this model.
final class CommandAssistant: ObservableObject {
    @Published var enabled = false
    @Published private(set) var ready = false
    @Published private(set) var preparing = false
    @Published private(set) var progress = 0.0
    @Published private(set) var downloaded = CommandModelStore.isDownloaded
    @Published private(set) var error: String?
    let model = CommandModel()
    private let store = CommandModelStore()
    private var preparation: Task<Void, Never>?
    private var generation = UUID()

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if enabled {
            if downloaded && !ready { prepare(download: false) }
        } else {
            cancelSetup()
            ready = false
            Task { await model.unload() }
        }
    }
    func cancelSetup() {
        generation = UUID()
        preparation?.cancel(); preparation = nil
        preparing = false
        if !ready { Task { await model.unload() } }
    }
    func prepare(download: Bool = true) {
        guard !preparing else { return }
        let run = UUID(); generation = run
        preparing = true; ready = false; error = nil; progress = downloaded ? 1 : 0
        preparation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let file = try await store.prepare(allowDownload: download) { [weak self] progress in
                    Task { @MainActor in
                        guard self?.generation == run else { return }
                        self?.progress = progress
                    }
                }
                try Task.checkCancellation()
                try await model.load(path: file.path)
                try Task.checkCancellation()
                guard generation == run else { return }
                downloaded = true; ready = true; preparing = false
            } catch {
                guard generation == run else { return }
                preparing = false; downloaded = CommandModelStore.isDownloaded
                if !(error is CancellationError) {
                    self.error = "Setup didn’t finish. Check your connection and free disk space, then retry."
                }
            }
        }
    }
}

struct NaturalCommandsSettings: View {
    @ObservedObject var assistant: CommandAssistant
    let setEnabled: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle("Natural commands · Beta", isOn: Binding(get: { assistant.enabled }, set: setEnabled))
                .toggleStyle(.switch).font(.system(size: 11, weight: .medium))
            if assistant.enabled {
                Text("Use your own phrasing after “Hey Teleprompter.” Runs privately on this Mac.")
                    .foregroundStyle(Palette.muted)
                if assistant.preparing {
                    ProgressView(value: assistant.progress)
                    Text(assistant.progress < 1 ? "Downloading · \(Int(assistant.progress * 100))%" : "Preparing command model…")
                    Button("Cancel setup", action: assistant.cancelSetup).buttonStyle(.plain)
                } else if assistant.ready {
                    Label("Command AI ready · offline", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.green)
                } else {
                    if let error = assistant.error { Text(error).foregroundStyle(Palette.accent) }
                    Button(assistant.error != nil ? "Retry command setup" : assistant.downloaded ? "Prepare command AI" : "Download command AI") {
                        assistant.prepare()
                    }.buttonStyle(QuietButton())
                }
                Text("Qwen2.5 · 1.5B · 1.12 GB download").foregroundStyle(Palette.muted)
            }
        }.font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
    }
}

#endif
