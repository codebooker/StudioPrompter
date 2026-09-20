import SwiftUI
import UIKit
import PrompterCore
import PrompterLink

struct RemoteCanvas: UIViewRepresentable {
    @ObservedObject var receiver: RemoteReceiver
    func makeUIView(context: Context) -> RemoteCanvasView { RemoteCanvasView(receiver: receiver) }
    func updateUIView(_ view: RemoteCanvasView, context: Context) { view.refreshDocument(); view.setNeedsDisplay() }
}

final class RemoteCanvasView: UIView {
    private let receiver: RemoteReceiver
    private var clock: CADisplayLink?
    private var revision: UUID?
    private var lineTexts: [NSAttributedString] = []
    init(receiver: RemoteReceiver) { self.receiver = receiver; super.init(frame: .zero); backgroundColor = .black; isOpaque = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow(); clock?.invalidate(); clock = nil
        if window != nil {
            let clock = CADisplayLink(target: self, selector: #selector(tick))
            clock.add(to: .main, forMode: .common); self.clock = clock
        }
    }
    @objc private func tick() { setNeedsDisplay() }
    func refreshDocument() {
        guard let document = receiver.document, document.revision != revision else { return }
        revision = document.revision
        let s = document.script.settings
        let name: String?
        switch s.typeface {
        case .system: name = nil
        case .avenirNext: name = "AvenirNext-Medium"
        case .verdana: name = "Verdana"
        case .georgia: name = "Georgia"
        }
        let font = name.flatMap { UIFont(name: $0, size: s.fontSize) } ?? UIFont.systemFont(ofSize: s.fontSize, weight: .medium)
        let text = NSMutableAttributedString(string: document.script.text, attributes: [.font: font, .foregroundColor: UIColor(white: 0.96, alpha: 1)])
        for mark in document.script.emphasis {
            guard let range = mark.range(in: document.script.text) else { continue }
            if mark.bold {
                let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) ?? UIFont.systemFont(ofSize: s.fontSize, weight: .bold).fontDescriptor
                text.addAttribute(.font, value: UIFont(descriptor: descriptor, size: s.fontSize), range: range)
            }
            if mark.underline { text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        }
        // Use the Mac's line breaks and positions; iPad orientation never reflows the script.
        lineTexts = document.lines.map { line in
            var range = NSRange(location: line.location, length: line.length)
            let string = text.string as NSString
            while range.length > 0, [10, 13].contains(Int(string.character(at: range.location + range.length - 1))) { range.length -= 1 }
            return text.attributedSubstring(from: range)
        }
    }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        UIColor(red: 0.055, green: 0.06, blue: 0.069, alpha: 1).setFill(); context.fill(bounds)
        guard let document = receiver.document, let state = receiver.playback, !state.blackout, bounds.width > 0 else { return }
        let s = document.script.settings
        let scale = bounds.width / 1000, height = bounds.height / scale
        let guideY = height * s.guidePosition
        let progress = receiver.motion.position(at: ProcessInfo.processInfo.systemUptime)
        let originY = guideY - s.fontSize * 0.2 - progress * max(0, document.textHeight - s.fontSize * 1.2)
        let nominal = CGRect(x: 0, y: guideY - 8, width: 1000, height: document.lineHeight * s.guideLines + 12)
        var band = nominal
        var visible: [(Int, CGRect)] = []
        for (index, line) in document.lines.enumerated() {
            let frame = CGRect(x: s.margin, y: line.y + originY, width: 1000 - 2 * s.margin, height: line.height)
            if frame.maxY >= 0 && frame.minY <= height { visible.append((index, frame)) }
            if frame.intersects(nominal) { band = band.union(CGRect(x: 0, y: frame.minY - 2, width: 1000, height: frame.height + 4)) }
        }
        context.saveGState(); context.scaleBy(x: scale, y: scale)
        context.translateBy(x: s.mirrorHorizontal ? 1000 : 0, y: s.mirrorVertical ? height : 0)
        context.scaleBy(x: s.mirrorHorizontal ? -1 : 1, y: s.mirrorVertical ? -1 : 1)
        if s.showGuide {
            UIColor(red: 0.98, green: 0.49, blue: 0.28, alpha: 0.045).setFill(); context.fill(band)
            UIColor.systemOrange.setFill()
            let arrow = UIBezierPath(); arrow.move(to: CGPoint(x: 30, y: guideY + 10))
            arrow.addLine(to: CGPoint(x: 44, y: guideY + 23)); arrow.addLine(to: CGPoint(x: 30, y: guideY + 36)); arrow.close(); arrow.fill()
        }
        func drawLines() { for (index, frame) in visible where index < lineTexts.count { lineTexts[index].draw(at: frame.origin) } }
        context.setAlpha(s.focusMode ? 0.36 : 1); drawLines()
        if s.focusMode { context.saveGState(); context.setAlpha(1); context.clip(to: band); drawLines(); context.restoreGState() }
        context.setAlpha(1)
        let overlay = state.countdown > 0 ? String(state.countdown) : state.notice
        if let overlay {
            let font = UIFont.systemFont(ofSize: state.countdown > 0 ? 140 : 24, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let size = (overlay as NSString).size(withAttributes: attributes)
            let box = CGRect(x: (1000 - size.width) / 2 - 16, y: state.countdown > 0 ? height / 2 - size.height / 2 : height - size.height - 48, width: size.width + 32, height: size.height + 20)
            UIColor.black.withAlphaComponent(0.9).setFill(); context.fill(box)
            (overlay as NSString).draw(at: CGPoint(x: box.minX + 16, y: box.minY + 10), withAttributes: attributes)
        }
        context.restoreGState()
    }
}
