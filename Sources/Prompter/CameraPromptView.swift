import AppKit
import SwiftUI
import PrompterCore

/// A normal key-capable window keeps Space/Esc/manual scrolling available in the compact view.
final class CameraPromptWindow: NSWindow, NSWindowDelegate {
    var onResize: ((CGSize) -> Void)?
    func windowDidResize(_ notification: Notification) { onResize?(frame.size) }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct CameraPromptView: View {
    @ObservedObject var state: AppState
    @ObservedObject var playback: Playback
    @ObservedObject var voice: VoiceController

    private var cameraScript: PrompterCore.Script {
        var script = state.current
        // Keep the same text geometry/reading anchor, but place the guide close to the lens.
        script.settings.guidePosition = state.cameraGuidePosition
        return script
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                PromptCanvas(script: cameraScript, progress: playback.transport.progress,
                             guidePositionRange: 0...1, keepsGuideInBounds: true,
                             onScroll: { playback.scrub(playback.transport.progress + $0) },
                             onGuideChange: { state.cameraGuidePosition = $0 })
                Capsule().fill(Palette.accent.opacity(0.8)).frame(width: 20, height: 3).padding(.top, 4)
                    .allowsHitTesting(false).accessibilityHidden(true)
                if playback.transport.countdownRemaining > 0 {
                    Color.black.opacity(0.8)
                    Text("\(Int(ceil(playback.transport.countdownRemaining)))")
                        .font(.system(size: 56, weight: .semibold)).frame(maxHeight: .infinity)
                }
                if playback.isBlackedOut { Color.black }
            }
            VStack(spacing: 7) {
                HStack(spacing: 10) {
                    CameraWindowDragHandle().frame(width: 20, height: 22)
                        .help("Drag to move Camera view. Drag the window edges to resize.")
                    Text("Camera view").font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 4)
                    Button(action: state.openCameraSizeControls) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .help("Adjust width and height").accessibilityLabel("Camera view size")
                    Button(action: state.centerCameraView) { Image(systemName: "viewfinder") }
                        .help("Center below the camera").accessibilityLabel("Center below camera")
                    Button(action: playback.reset) { Image(systemName: "backward.end") }
                        .help("Reset script").accessibilityLabel("Reset script")
                    Button(action: state.togglePlayback) {
                        Label(playback.transport.isPlaying ? "Pause" : "Play", systemImage: playback.transport.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(.black)
                    }.accessibilityLabel(playback.transport.isPlaying ? "Pause prompting" : "Play prompting")
                    Button(action: state.showProducerWorkspace) { Image(systemName: "slider.horizontal.3") }
                        .help("Back to producer controls").accessibilityLabel("Producer controls")
                    Button(action: state.closeCameraView) { Image(systemName: "xmark") }
                        .help("Close Camera view").accessibilityLabel("Close Camera view")
                }.buttonStyle(.plain)
                HStack(spacing: 6) {
                    Image(systemName: voice.isListening ? "mic.fill" : "mic.slash")
                        .foregroundStyle(voice.isListening ? Palette.green : Palette.muted)
                    Text(voice.commandNotice ?? (voice.isListening ? (voice.handsFreeCommands ? "Listening for Hey Teleprompter" : "Listening · \(voice.mode.rawValue)") : "Microphone off"))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    #if EXPERIMENTAL_COMMANDS
                    Toggle("Hands-free", isOn: Binding(get: { voice.handsFreeCommands }, set: voice.setHandsFreeCommands))
                        .toggleStyle(.switch).controlSize(.mini)
                        .help("Start listening for Hey Teleprompter using your selected microphone")
                    #endif
                }.font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 12).padding(.vertical, 9).background(Palette.panel)
        }
        .foregroundStyle(.white).background(Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
    }
}

/// Kept in an independent panel so changing the camera frame cannot move a slider
/// underneath the pointer or cause a popover to flip during a drag.
struct CameraSizeControls: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Width · \(Int(state.cameraViewSize.width))")
            Slider(value: Binding(get: { state.cameraViewSize.width }, set: { state.resizeCameraView(width: $0) }), in: 360...1000, step: 10)
                .accessibilityLabel("Camera view width")
            Text("Height · \(Int(state.cameraViewSize.height))")
            Slider(value: Binding(get: { state.cameraViewSize.height }, set: { state.resizeCameraView(height: $0) }), in: 180...600, step: 10)
                .accessibilityLabel("Camera view height")
            HStack {
                Text("Drag the camera view’s handle to align with your webcam.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: state.closeCameraSizeControls).keyboardShortcut(.cancelAction)
            }
        }.padding(18).frame(width: 280).preferredColorScheme(.dark)
    }
}

private struct CameraWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandle { DragHandle() }
    func updateNSView(_ nsView: DragHandle, context: Context) {}
    final class DragHandle: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            setAccessibilityElement(true)
            setAccessibilityLabel("Move Camera view")
            setAccessibilityRole(.image)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.setFill()
            for y in [7.0, 11.0, 15.0] {
                NSBezierPath(roundedRect: NSRect(x: 4, y: y, width: 12, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            }
        }
    }
}
