import AppKit
import PrompterCore

public enum ScriptTypography {
    public static func font(_ settings: PromptSettings) -> NSFont {
        let fallback = NSFont.systemFont(ofSize: settings.fontSize, weight: .medium)
        switch settings.typeface {
        case .system: return fallback
        case .avenirNext: return NSFont(name: "AvenirNext-Medium", size: settings.fontSize) ?? fallback
        case .verdana: return NSFont(name: "Verdana", size: settings.fontSize) ?? fallback
        case .georgia: return NSFont(name: "Georgia", size: settings.fontSize) ?? fallback
        }
    }

    public static func text(_ text: String, settings: PromptSettings, emphasis: [TextEmphasis] = []) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = settings.fontSize * (settings.lineSpacing - 1)
        paragraph.paragraphSpacing = settings.fontSize * 0.25
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font(settings), .foregroundColor: NSColor(white: 0.96, alpha: 1), .paragraphStyle: paragraph
        ])
        apply(emphasis, to: result, baseFont: font(settings))
        // Preserve script offsets, but don't render blank separator paragraphs as
        // full-size empty reading lines. Paragraph spacing already marks the break.
        let blank = NSMutableParagraphStyle()
        blank.minimumLineHeight = 1; blank.maximumLineHeight = 1
        let expression = try! NSRegularExpression(pattern: "(?m)^[\\t ]*(?:\\r\\n|\\n|\\r)")
        for match in expression.matches(in: text, range: NSRange(location: 0, length: result.length)) {
            result.addAttributes([.font: NSFont.systemFont(ofSize: 1), .paragraphStyle: blank], range: match.range)
        }
        return result
    }
    public static func apply(_ emphasis: [TextEmphasis], to text: NSMutableAttributedString, baseFont: NSFont) {
        for mark in emphasis {
            guard let range = mark.range(in: text.string) else { continue }
            if mark.bold {
                let converted = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                let boldFont = NSFontManager.shared.traits(of: converted).contains(.boldFontMask) ? converted : NSFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
                text.addAttribute(.font, value: boldFont, range: range)
            }
            if mark.underline { text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        }
    }

    public static func emphasis(in text: NSAttributedString) -> [TextEmphasis] {
        var result: [TextEmphasis] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            let bold = (attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false
            let underline = (attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0 != 0
            if bold || underline {
                if let last = result.last, last.location + last.length == range.location, last.bold == bold, last.underline == underline {
                    result[result.count - 1].length += range.length
                } else { result.append(TextEmphasis(location: range.location, length: range.length, bold: bold, underline: underline)) }
            }
        }
        return result
    }

    public static func editorText(_ script: Script) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        let font = NSFont.systemFont(ofSize: 19)
        let text = NSMutableAttributedString(string: script.text, attributes: [.font: font, .foregroundColor: NSColor(white: 0.92, alpha: 1), .paragraphStyle: paragraph])
        apply(script.emphasis, to: text, baseFont: font)
        return text
    }

}

public enum FocusGeometry {
    /// Expand the reading band to include whole intersecting text lines. This
    /// avoids slicing letters in half as smoothly scrolling text crosses its edge.
    public static func band(nominal: CGRect, textLines: [CGRect]) -> CGRect {
        var result = nominal
        for line in textLines where line.intersects(nominal) {
            result = result.union(CGRect(x: nominal.minX, y: line.minY - 2, width: nominal.width, height: line.height + 4))
        }
        return result
    }
}

/// Canonical display geometry shared by cue placement and both prompter screens.
public final class ScriptCueLayout {
    private let storage: NSTextStorage
    private let layout = NSLayoutManager()
    private let container: NSTextContainer
    private let travel: Double
    public init(_ script: Script) {
        storage = NSTextStorage(attributedString: ScriptTypography.text(script.text, settings: script.settings, emphasis: script.emphasis))
        container = NSTextContainer(size: NSSize(width: 1000 - script.settings.margin * 2, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container); storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        travel = max(1, layout.usedRect(for: container).height - script.settings.fontSize * 1.2)
    }
    public func progress(at offset: Int) -> Double {
        guard storage.length > 0 else { return 0 }
        let glyph = layout.glyphIndexForCharacter(at: min(max(0, offset), storage.length - 1))
        return min(1, max(0, layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY / travel))
    }
    public func offset(at progress: Double) -> Int {
        guard storage.length > 0 else { return 0 }
        let glyph = layout.glyphIndex(for: NSPoint(x: 0, y: max(0, min(1, progress)) * travel + 1), in: container)
        return layout.characterIndexForGlyph(at: min(glyph, max(0, layout.numberOfGlyphs - 1)))
    }
}

/// Navigation uses the rendered reading lines shared by both displays.
public enum VoiceNavigation {
    public static func destination(for command: VoiceCommand, script: Script, progress: Double) -> Double? {
        let mapping = ScriptCueLayout(script)
        let currentOffset = mapping.offset(at: progress)
        switch command {
        case .top: return 0
        case .lines(let delta):
            let storage = NSTextStorage(attributedString: ScriptTypography.text(script.text, settings: script.settings, emphasis: script.emphasis))
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: NSSize(width: 1000 - script.settings.margin * 2, height: CGFloat.greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container); storage.addLayoutManager(layout)
            layout.ensureLayout(for: container)
            var offsets: [Int] = []
            layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { _, _, _, glyphs, _ in
                let range = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                if !(script.text as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { offsets.append(range.location) }
            }
            guard !offsets.isEmpty else { return 0 }
            let index = offsets.lastIndex(where: { $0 <= currentOffset }) ?? 0
            return mapping.progress(at: offsets[min(offsets.count - 1, max(0, index + delta))])
        case .paragraph(let delta):
            var offsets: [Int] = []
            let text = script.text as NSString
            var cursor = 0
            while cursor < text.length {
                let range = text.paragraphRange(for: NSRange(location: cursor, length: 0))
                let content = text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted, options: [], range: range)
                if content.location != NSNotFound { offsets.append(content.location) }
                cursor = NSMaxRange(range)
            }
            guard !offsets.isEmpty else { return 0 }
            let index = offsets.lastIndex(where: { $0 <= currentOffset }) ?? 0
            return mapping.progress(at: offsets[min(offsets.count - 1, max(0, index + delta))])
        case .cue(let direction):
            let positions = script.cues.map { $0.characterOffset.map(mapping.progress(at:)) ?? $0.progress }.sorted()
            return direction < 0 ? positions.last(where: { $0 < progress - 0.005 }) : positions.first(where: { $0 > progress + 0.005 })
        default: return nil
        }
    }
}
