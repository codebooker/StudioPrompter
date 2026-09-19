import AppKit
import AVFoundation
import SwiftUI
import PrompterCore
import PrompterSpeech
import PrompterLayout

enum VoiceMode: String, CaseIterable, Identifiable {
    case pace = "Adaptive pace", follow = "Follow script"
    var id: String { rawValue }
}
struct VoiceDrive {
    var speaking: Bool
    var wordsPerMinute: Double
    var target: Double?
    var followsScript: Bool
    var lineStep: Double
    var holdReason: String
}

final class VoiceController: ObservableObject {
    @Published var model = "base.en"
    @Published var enabled = false { didSet { if !enabled { stop() } } }
    @Published var selectedMicrophone: UInt32 = 0 { didSet { refreshChannels() } }
    @Published var selectedChannel = 0
    @Published var channels: [MicrophoneChannel] = []
    @Published var microphones = MicrophoneCapture.devices
    @Published var mode: VoiceMode = .pace { didSet { updateDrive() } }
    @Published var isListening = false
    @Published var isStarting = false
    @Published var isPreparing = false
    @Published var isReady = false
    @Published var isDownloaded = WhisperService.isDownloaded(model: "base.en")
    @Published var modelSetupFailed = false
    @Published var downloadProgress = 0.0
    @Published var status = "Local Whisper · English"
    @Published var transcript = ""
    #if EXPERIMENTAL_COMMANDS
    let assistant = CommandAssistant()
    #endif
    private var commandTask: Task<Void, Never>?
    private var commandTimeout: Task<Void, Never>?
    private var commandGeneration = UUID()
    @Published private(set) var handsFreeCommands = false
    @Published var awaitingCommand = false
    @Published var commandNotice: String?
    private var commandNoticeUntil = 0.0
    private var commands = VoiceCommandRouter()
    #if EXPERIMENTAL_COMMANDS
    private let liveTraceEnabled = ProcessInfo.processInfo.arguments.contains("--voice-diagnostics")
    #else
    private let liveTraceEnabled = false
    #endif
    private var lastTracedSpeech = ""
    private func trace(_ event: String, _ details: [String: Any] = [:]) {
        guard liveTraceEnabled else { return }
        var record = details
        record["event"] = event
        record["time"] = ISO8601DateFormatter().string(from: Date())
        record["progress"] = state?.playback.transport.progress ?? 0
        record["playing"] = state?.playback.transport.isPlaying ?? false
        record["fontSize"] = state?.current.settings.fontSize ?? 0
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        print("VOICE_TRACE " + line)
        fflush(stdout)
    }
    #if EXPERIMENTAL_COMMANDS
    private func executeCommand(_ command: VoiceCommand, source: String) {
        trace("action_requested", ["source": source, "command": String(describing: command)])
        let notice = state?.performVoiceCommand(command) ?? "Command unavailable"
        trace("action_result", ["source": source, "command": String(describing: command), "result": notice])
        showCommandNotice(notice)
    }
    #endif
    @Published var decibels = -100.0
    @Published var speaking = false
    @Published var measuredPace: Double?
    @Published var inferenceSeconds = 0.0
    @Published var matchConfidence: Double?
    @Published var waitingForRetake = false
    @Published var noiseFloor = -42.0 { didSet { microphone.setThreshold(noiseFloor) } }
    @Published var pauseDelay = 0.5
    @Published var minimumPace = 60.0
    @Published var maximumPace = 240.0
    @Published var responsiveness = 0.3
    @Published var followLead = 0.0 { didSet { updateDrive() } }
    @Published var error: String?
    private weak var state: AppState?
    private let service = WhisperService()
    private let microphone = MicrophoneCapture()
    private var preparation: Task<Void, Never>?
    private var listening: Task<Void, Never>?
    private var meter: Timer?
    private var generation = UUID()
    private var estimator = PaceEstimator()
    private var lastRecognition = 0.0
    private var recognitionUpdates = RecognitionUpdates()
    private var matchedWord: Int?
    private var matchedAt = 0.0
    private var minimumSpeechTime = 0.0
    private var retake = RetakeGate()
    private var cachedText = ""
    private var scriptWords: [ScriptWord] = []
    private let positions = TextPositionMap()

    init(state: AppState) { self.state = state; refreshChannels() }
    func refreshChannels() {
        channels = MicrophoneCapture.channels(deviceID: selectedMicrophone == 0 ? nil : selectedMicrophone)
        selectedChannel = channels.count == 1 ? channels[0].id : 0
    }
    func refreshMicrophones() {
        microphones = MicrophoneCapture.devices
        refreshChannels()
    }
    var inputSummary: String {
        let device = microphones.first { $0.id == selectedMicrophone }?.name ?? "System default"
        return selectedChannel > 0 ? "\(device) · Channel \(selectedChannel)" : "Choose an input channel"
    }
    var controlling: Bool { isListening }
    #if EXPERIMENTAL_COMMANDS
    func setHandsFreeCommands(_ enabled: Bool) {
        cancelInterpretation()
        if !enabled { assistant.setEnabled(false) }
        handsFreeCommands = enabled
        commands = VoiceCommandRouter(after: microphone.snapshot().end)
        awaitingCommand = false; commandNotice = nil
        if isListening {
            if !enabled && state?.playback.transport.isPlaying != true { stop() }
            else { beginRetake() }
        } else if enabled {
            start()
        } else if isStarting {
            stop()
        }
    }
    #endif
    func pauseForCommands() {
        state?.playback.transport.pause()
        beginRetake()
        status = "Script paused · listening for Hey Teleprompter"
    }
    #if EXPERIMENTAL_COMMANDS
    func setNaturalCommands(_ enabled: Bool) {
        beginRetake()
        assistant.setEnabled(enabled)
    }
    #endif
    private func cancelInterpretation() {
        if commandTask != nil { trace("llm_cancelled") }
        commandGeneration = UUID()
        commandTask?.cancel(); commandTask = nil
        commandTimeout?.cancel(); commandTimeout = nil
        awaitingCommand = false
    }
    #if EXPERIMENTAL_COMMANDS
    private func interpretCommand(_ request: String) {
        beginRetake()
        let run = UUID(); commandGeneration = run
        let scriptID = state?.current.id
        awaitingCommand = true; commandNotice = "Understanding your command…"
        trace("llm_request", ["request": request])
        updateDrive()
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var result: VoiceCommand?
            let started = ProcessInfo.processInfo.systemUptime
            do {
                let output = try await assistant.model.classify(request)
                result = CommandIntent.interpret(output, request: request)
                trace("llm_response", ["request": request, "raw": output,
                    "validated": result.map { String(describing: $0) } ?? "declined",
                    "seconds": ProcessInfo.processInfo.systemUptime - started])
            } catch { result = nil; trace("llm_error", ["error": String(describing: error)]) }
            guard !Task.isCancelled, commandGeneration == run, isListening, handsFreeCommands,
                  assistant.enabled, state?.current.id == scriptID else { return }
            commandTask = nil
            commandTimeout?.cancel(); commandTimeout = nil
            awaitingCommand = false
            commands = VoiceCommandRouter(after: microphone.snapshot().end)
            beginRetake()
            if let result { executeCommand(result, source: "LLM") }
            else { showCommandNotice("Please name a line count, paragraph, cue, or text-size change") }
            updateDrive()
        }
        commandTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
            guard let self, commandGeneration == run else { return }
            cancelInterpretation()
            commands = VoiceCommandRouter(after: microphone.snapshot().end)
            beginRetake()
            showCommandNotice("That took too long · please try a shorter command")
            updateDrive()
        }
    }
    #endif
    private func showCommandNotice(_ text: String) {
        commandNotice = text
        commandNoticeUntil = ProcessInfo.processInfo.systemUptime + 4
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, !self.awaitingCommand, ProcessInfo.processInfo.systemUptime >= self.commandNoticeUntil else { return }
            self.commandNotice = nil
        }
    }
    var effectivePace: Double {
        let heard = measuredPace ?? state?.current.settings.wordsPerMinute ?? 140
        return min(maximumPace, max(minimumPace, heard))
    }

    func prepare(allowDownload: Bool = true) {
        guard !isPreparing else { return }
        error = nil; modelSetupFailed = false; isPreparing = true; isReady = false; downloadProgress = isDownloaded ? 1 : 0
        status = isDownloaded ? "Preparing speech model…" : "Downloading speech model…"
        let model = model
        preparation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await service.prepare(model: model, allowDownload: allowDownload) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                        if progress >= 1 { self?.status = "Preparing speech model on this Mac…" }
                    }
                }
                isPreparing = false; isReady = true; isDownloaded = true; status = "Speech model ready · works offline"
            } catch {
                isPreparing = false; modelSetupFailed = true
                isDownloaded = WhisperService.isDownloaded(model: model)
                self.error = "Speech model setup failed. Check your internet connection and free disk space, then choose Retry setup."
                status = "Model setup needs another try"
            }
        }
    }
    func changeModel(_ name: String) {
        stop()
        model = name; isReady = false
        isDownloaded = WhisperService.isDownloaded(model: name)
        modelSetupFailed = false; error = nil; downloadProgress = 0
        status = isDownloaded ? "Speech model downloaded" : "Download a speech model to get started"
    }
    func start(playWhenReady: Bool = false) {
        guard !isListening, !isStarting else { return }
        guard state?.isEditing != true else { handsFreeCommands = false; error = "Finish editing before starting voice prompting."; return }
        guard isDownloaded || isReady else { handsFreeCommands = false; error = "Download the speech model first, then press Play."; return }
        guard selectedChannel > 0 else { handsFreeCommands = false; error = "Choose the interviewer's input channel before starting."; return }
        enabled = true
        isStarting = true
        state?.playback.transport.pause()
        let run = UUID(); generation = run
        error = nil
        listening = Task { @MainActor [weak self] in
            guard let self else { return }
            if !isReady {
                prepare(allowDownload: false)
                await preparation?.value
                guard generation == run, !Task.isCancelled else { return }
                guard isReady else { isStarting = false; handsFreeCommands = false; return }
            }
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .audio)
            default: allowed = false
            }
            guard generation == run, !Task.isCancelled else { return }
            isStarting = false
            guard allowed else {
                handsFreeCommands = false
                error = "Allow Prompter microphone access in System Settings → Privacy & Security → Microphone."
                return
            }
            do {
                microphone.setThreshold(noiseFloor)
                try microphone.start(deviceID: selectedMicrophone == 0 ? nil : selectedMicrophone, channel: selectedChannel)
                isListening = true
                lastTracedSpeech = ""
                #if EXPERIMENTAL_COMMANDS
                trace("microphone_started", ["input": inputSummary, "handsFree": handsFreeCommands,
                    "naturalCommands": assistant.enabled, "modelReady": assistant.ready])
                #endif
                transcript = ""; estimator = PaceEstimator(); measuredPace = nil
                commands = VoiceCommandRouter(); awaitingCommand = false; commandNotice = nil
                lastRecognition = 0; recognitionUpdates = RecognitionUpdates(); matchedWord = nil; matchConfidence = nil; minimumSpeechTime = 0
                retake = RetakeGate(); waitingForRetake = false
                status = "Listening — start speaking"
                startMeter()
                // Install the voice hold before Play; the first meter tick is
                // asynchronous and must not leave a fixed-speed frame in between.
                updateDrive()
                if playWhenReady { state?.playback.toggle() }
                var processedEnd = 0.0
                while !Task.isCancelled, generation == run {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    guard commandTask == nil else { continue }
                    let snapshot = microphone.snapshot()
                    // Keep decoding quiet speech. RMS is a meter/pace hint, not
                    // permission to recognize the next words of the script.
                    guard snapshot.end - processedEnd >= 0.3, snapshot.samples.count >= 16000 else { continue }
                    processedEnd = snapshot.end
                    let started = ProcessInfo.processInfo.systemUptime
                    let result = try await service.transcribe(snapshot.samples)
                    guard generation == run, !Task.isCancelled else { return }
                    inferenceSeconds = ProcessInfo.processInfo.systemUptime - started
                    consume(result, snapshot: snapshot)
                }
            } catch is CancellationError {} catch {
                guard generation == run else { return }
                stop(); self.error = error.localizedDescription; status = "Microphone or transcription stopped"
            }
        }
    }
    private func startMeter() {
        meter?.invalidate()
        meter = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.isListening else { return }
            let snapshot = self.microphone.snapshot()
            let now = ProcessInfo.processInfo.systemUptime
            self.decibels = snapshot.decibels
            self.speaking = now - snapshot.lastVoice < self.pauseDelay
            if !self.awaitingCommand && now > self.commandNoticeUntil { self.commandNotice = nil }
            if now - snapshot.lastBuffer > 3 {
                self.stop(); self.error = "Microphone input stopped. Check the connection and start listening again."
                return
            }
            self.updateDrive()
        }
        if let meter { RunLoop.main.add(meter, forMode: .common) }
    }
    private func consume(_ speech: HeardSpeech, snapshot: AudioSnapshot) {
        if liveTraceEnabled && speech.text != lastTracedSpeech {
            lastTracedSpeech = speech.text
            trace("whisper", ["text": speech.text, "audioStart": snapshot.start, "audioEnd": snapshot.end,
                "inferenceSeconds": inferenceSeconds])
        }
        guard commandTask == nil else { return }
        #if EXPERIMENTAL_COMMANDS
        if handsFreeCommands {
            let words = speech.words.map { CommandWord($0.text, start: snapshot.start + $0.start, end: snapshot.start + $0.end) }
            let event = commands.consume(words, audioEnd: snapshot.end,
                quiet: ProcessInfo.processInfo.systemUptime - snapshot.lastVoice >= 0.65,
                interpretUnknown: assistant.enabled && assistant.ready)
            switch event {
            case .reading: break
            case .listening:
                if !awaitingCommand { trace("wake_detected"); beginRetake() }
                awaitingCommand = true
                commandNotice = "Listening for your command…"
                updateDrive(); return
            case .execute(let command):
                awaitingCommand = false
                beginRetake()
                executeCommand(command, source: "fast parser")
                updateDrive(); return
            case .interpret(let request):
                interpretCommand(request)
                return
            case .unrecognized:
                trace("command_unrecognized", ["naturalCommands": assistant.enabled, "modelReady": assistant.ready])
                awaitingCommand = false
                beginRetake()
                showCommandNotice("Command not recognized · try again")
                updateDrive(); return
            }
        }
        #endif
        let cutoff = max(minimumSpeechTime, handsFreeCommands ? commands.consumedThrough : 0)
        let words = speech.words.filter { snapshot.start + $0.start >= cutoff }
        guard let last = words.last else { return }
        let phrase = words.map(\.text).joined(separator: " ")
        let end = snapshot.start + last.end
        guard recognitionUpdates.accept(text: phrase, wordEnd: end, audioEnd: snapshot.end) else { return }
        transcript = phrase
        let recent = words.filter { snapshot.start + $0.start >= max(snapshot.start, snapshot.end - 5) }
        if let first = recent.first {
            // Include the gap after the last word so brief hesitations lower
            // the estimate instead of retaining the preceding burst's speed.
            measuredPace = estimator.observe(wordCount: recent.reduce(0) { $0 + Script.countWords($1.text) }, span: snapshot.end - snapshot.start - first.start, audioEnd: snapshot.end, smoothing: responsiveness)
        }
        lastRecognition = ProcessInfo.processInfo.systemUptime - max(0, snapshot.end - end)
        status = "Listening · local Whisper"
        if let state {
            let script = state.current
            if cachedText != script.text {
                cachedText = script.text; scriptWords = ScriptMatcher.words(in: script.text)
                matchedWord = nil
            }
            positions.configure(script)
            let anchor = matchedWord ?? positions.wordIndex(at: state.playback.transport.progress, words: scriptWords)
            // A manual seek starts a new reading location; buffered words must not pull it back.
            if let match = ScriptMatcher.match(phrase, script: scriptWords, near: anchor),
               retake.accept(target: positions.progress(atWord: Double(match.wordIndex), words: scriptWords),
                             lineStep: positions.lineStep, now: ProcessInfo.processInfo.systemUptime) {
                waitingForRetake = false
                if matchedWord == nil || match.wordIndex > matchedWord! {
                    matchedAt = ProcessInfo.processInfo.systemUptime
                }
                matchedWord = max(matchedWord ?? match.wordIndex, match.wordIndex)
                matchConfidence = match.confidence
            } else { matchConfidence = nil }
        }
        updateDrive()
    }
    private func updateDrive() {
        guard let state else { return }
        if controlling {
            let now = ProcessInfo.processInfo.systemUptime
            let fresh = now - lastRecognition < 4
            var target: Double?
            if let matchedWord, now - matchedAt < 2 {
                positions.configure(state.current)
                // Zero means the recognized location, without hidden forward prediction.
                target = positions.progress(atWord: Double(matchedWord) + followLead, words: scriptWords)
                if matchedWord < scriptWords.count - 1 { target = min(target ?? 0, 0.999) }
                else { target = 1 }
            }
            let advancing = !awaitingCommand && !retake.isWaiting && (mode == .follow ? target != nil : speaking && fresh && measuredPace != nil)
            let reason = retake.isWaiting ? "Ready for retake — read from here" : (mode == .follow && (speaking || fresh) ? "Finding your place" : "Waiting for speech")
            state.playback.voiceDrive = VoiceDrive(speaking: advancing, wordsPerMinute: effectivePace, target: target, followsScript: mode == .follow, lineStep: positions.lineStep, holdReason: reason)
        } else { state.playback.voiceDrive = nil }
    }
    func resetAnchor() {
        matchedWord = nil; matchConfidence = nil
        minimumSpeechTime = microphone.snapshot().end
        recognitionUpdates = RecognitionUpdates()
        updateDrive()
    }
    func beginRetake() {
        cancelInterpretation()
        guard let state, isListening else { return }
        retake.begin(now: ProcessInfo.processInfo.systemUptime, audioEnd: microphone.snapshot().end,
                     progress: state.playback.transport.progress)
        resetAnchor()
        minimumSpeechTime = retake.minimumSpeechTime
        matchedAt = 0; lastRecognition = 0
        estimator = PaceEstimator(); measuredPace = nil; transcript = ""
        waitingForRetake = true
        updateDrive()
    }
    func stop() {
        if isListening || isStarting { trace("microphone_stopped") }
        cancelInterpretation()
        generation = UUID()
        listening?.cancel(); listening = nil
        meter?.invalidate(); meter = nil
        microphone.stop()
        retake = RetakeGate(); waitingForRetake = false
        isListening = false; isStarting = false; handsFreeCommands = false; speaking = false; decibels = -100
        awaitingCommand = false; commandNotice = nil; commands = VoiceCommandRouter()
        state?.playback.voiceDrive = nil
        state?.playback.transport.pause()
        status = isReady ? "Whisper ready · microphone off" : "Local Whisper · English"
    }
}

/// Map recognized UTF-16 offsets to the same text layout used by both displays.
private final class TextPositionMap {
    private let storage = NSTextStorage()
    private let layout = NSLayoutManager()
    private let container = NSTextContainer(size: .zero)
    private var key: Script?
    private var travel = 1.0
    private var continuousPositions: [Double] = []
    private var lineHeight = 80.0
    var lineStep: Double { lineHeight / travel }
    init() { container.lineFragmentPadding = 0; layout.addTextContainer(container); storage.addLayoutManager(layout) }
    func configure(_ script: Script) {
        if let key, key.text == script.text, key.emphasis == script.emphasis, key.settings == script.settings { return }
        key = script
        let settings = script.settings
        container.containerSize = NSSize(width: 1000 - settings.margin * 2, height: CGFloat.greatestFiniteMagnitude)
        storage.setAttributedString(ScriptTypography.text(script.text, settings: settings, emphasis: script.emphasis))
        layout.ensureLayout(for: container)
        travel = max(1, layout.usedRect(for: container).height - settings.fontSize * 1.2)
        lineHeight = layout.defaultLineHeight(for: ScriptTypography.font(settings)) + settings.fontSize * (settings.lineSpacing - 1)
        continuousPositions = ReadingPositions.spread(lineStarts: ScriptMatcher.words(in: script.text).map { progress(for: $0.characterOffset) }, lineStep: lineStep)
    }
    func progress(for offset: Int) -> Double {
        guard storage.length > 0 else { return 0 }
        let glyph = layout.glyphIndexForCharacter(at: min(max(0, offset), storage.length - 1))
        return min(1, max(0, layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY / travel))
    }
    func wordIndex(at progress: Double, words: [ScriptWord]) -> Int {
        words.lastIndex { self.progress(for: $0.characterOffset) <= progress + 0.001 } ?? 0
    }
    func progress(atWord index: Double, words: [ScriptWord]) -> Double {
        guard !words.isEmpty else { return 0 }
        let value = min(Double(words.count - 1), max(0, index))
        let lower = Int(value), upper = min(words.count - 1, lower + 1)
        guard continuousPositions.count == words.count else { return progress(for: words[lower].characterOffset) }
        let start = continuousPositions[lower]
        let end = continuousPositions[upper]
        return start + (end - start) * (value - Double(lower))
    }
}
