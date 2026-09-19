import AppKit
import SwiftUI
import PrompterCore
import PrompterLayout

struct PromptCanvas: NSViewRepresentable {
    let script: Script
    let progress: Double
    var mirrored = false
    var onScroll: ((Double) -> Void)?
    var onGuideChange: ((Double) -> Void)?
    func makeNSView(context: Context) -> ScriptCanvas { ScriptCanvas() }
    func updateNSView(_ view: ScriptCanvas, context: Context) {
        view.configure(text: script.text, settings: script.settings)
        view.progress = progress
        view.mirrored = mirrored
        view.onScroll = onScroll
        view.onGuideChange = onGuideChange
        view.needsDisplay = true
    }
}

final class ScriptCanvas: NSView {
    private let storage = NSTextStorage()
    private let layout = NSLayoutManager()
    private let container = NSTextContainer(size: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
    private var settings = PromptSettings()
    private var lastText: String?
    private var textHeight: CGFloat = 0
    private var lineHeight: CGFloat = 80
    private var dragPoint: NSPoint?
    private var draggingGuide = false
    var progress: Double = 0
    var mirrored = false
    var onScroll: ((Double) -> Void)?
    var onGuideChange: ((Double) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        setAccessibilityElement(true)
        setAccessibilityLabel("Teleprompter script preview")
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, settings: PromptSettings) {
        guard text != lastText || settings.fontSize != self.settings.fontSize || settings.margin != self.settings.margin || settings.lineSpacing != self.settings.lineSpacing || settings.typeface != self.settings.typeface else {
            self.settings = settings
            return
        }
        lastText = text
        self.settings = settings
        container.containerSize = NSSize(width: 1000 - settings.margin * 2, height: CGFloat.greatestFiniteMagnitude)
        storage.setAttributedString(ScriptTypography.text(text, settings: settings))
        layout.ensureLayout(for: container)
        textHeight = layout.usedRect(for: container).height
        lineHeight = layout.defaultLineHeight(for: ScriptTypography.font(settings)) + settings.fontSize * (settings.lineSpacing - 1)
        setAccessibilityValue(text)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.055, green: 0.06, blue: 0.069, alpha: 1).setFill()
        bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext, bounds.width > 0 else { return }
        let scale = bounds.width / 1000
        let logicalHeight = bounds.height / scale
        let guideY = logicalHeight * settings.guidePosition
        let guideHeight = lineHeight * settings.guideLines + 12
        let travel = max(0, textHeight - settings.fontSize * 1.2)
        let origin = NSPoint(x: settings.margin, y: guideY - settings.fontSize * 0.2 - progress * travel)
        let visible = NSRect(x: 0, y: -origin.y - lineHeight, width: 1000, height: logicalHeight + lineHeight * 2)
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        var textLines: [CGRect] = []
        layout.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, range, _ in
            let characters = self.layout.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            guard !(self.storage.string as NSString).substring(with: characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            textLines.append(used.offsetBy(dx: origin.x, dy: origin.y))
        }
        let focusBand = FocusGeometry.band(nominal: CGRect(x: 0, y: guideY - 8, width: 1000, height: guideHeight), textLines: textLines)
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        if mirrored {
            context.translateBy(x: settings.mirrorHorizontal ? 1000 : 0, y: settings.mirrorVertical ? logicalHeight : 0)
            context.scaleBy(x: settings.mirrorHorizontal ? -1 : 1, y: settings.mirrorVertical ? -1 : 1)
        }
        if settings.showGuide {
            NSColor(calibratedRed: 0.98, green: 0.49, blue: 0.28, alpha: 0.045).setFill()
            focusBand.fill()
            NSColor(calibratedRed: 1, green: 0.49, blue: 0.28, alpha: 1).setFill()
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: 30, y: guideY + 10))
            arrow.line(to: NSPoint(x: 44, y: guideY + 23))
            arrow.line(to: NSPoint(x: 30, y: guideY + 36))
            arrow.close()
            arrow.fill()
        }
        context.setAlpha(settings.focusMode ? 0.36 : 1)
        layout.drawGlyphs(forGlyphRange: glyphs, at: origin)
        if settings.focusMode {
            context.setAlpha(1)
            context.clip(to: focusBand)
            layout.drawGlyphs(forGlyphRange: glyphs, at: origin)
        }
        context.restoreGState()
    }
    override func resetCursorRects() { if onScroll != nil { addCursorRect(bounds, cursor: .openHand) } }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragPoint = convert(event.locationInWindow, from: nil)
        if let point = dragPoint {
            let scale = bounds.width / 1000
            draggingGuide = settings.showGuide && onGuideChange != nil && point.x < 65 * scale && abs(point.y - (bounds.height * settings.guidePosition + 23 * scale)) < 35 * scale
        }
        if onScroll != nil { NSCursor.closedHand.push() }
    }
    override func mouseUp(with event: NSEvent) { dragPoint = nil; draggingGuide = false; if onScroll != nil { NSCursor.pop() } }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer { dragPoint = point }
        guard let previous = dragPoint else { return }
        if draggingGuide {
            onGuideChange?(min(0.65, max(0.15, (point.y - 23 * bounds.width / 1000) / max(1, bounds.height))))
            return
        }
        let travel = max(1, textHeight - settings.fontSize * 1.2)
        onScroll?(-(point.y - previous.y) / max(0.1, bounds.width / 1000) / travel)
    }
    override func scrollWheel(with event: NSEvent) {
        let travel = max(1, textHeight - settings.fontSize * 1.2)
        onScroll?(-event.scrollingDeltaY / travel * (event.hasPreciseScrollingDeltas ? 1.8 : 12))
    }
}

struct TalentOutputView: View {
    @ObservedObject var state: AppState
    var body: some View { TalentCanvas(state: state, playback: state.playback) }
}

private struct TalentCanvas: View {
    @ObservedObject var state: AppState
    @ObservedObject var playback: Playback
    var body: some View {
        ZStack {
            PromptCanvas(script: state.current, progress: playback.transport.progress, mirrored: true)
            if playback.transport.countdownRemaining > 0 {
                Color.black.opacity(0.8)
                Text("\(Int(ceil(playback.transport.countdownRemaining)))")
                    .font(.system(size: 140, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            }
            if playback.isBlackedOut { Color.black }
        }.ignoresSafeArea()
    }
}

struct PresentationView: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(spacing: 0) {
            TalentOutputView(state: state)
            TransportBar(state: state, playback: state.playback, voice: state.voice, compact: true)
        }.frame(minWidth: 600, minHeight: 400).background(Palette.background)
    }
}
