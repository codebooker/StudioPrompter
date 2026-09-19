import AppKit
import PrompterCore

public enum ScriptTypography {
    public static func font(_ settings: PromptSettings) -> NSFont {
        settings.serifFont ? NSFont(name: "Georgia", size: settings.fontSize) ?? NSFont.systemFont(ofSize: settings.fontSize) : NSFont.systemFont(ofSize: settings.fontSize, weight: .medium)
    }

    public static func text(_ text: String, settings: PromptSettings) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = settings.fontSize * (settings.lineSpacing - 1)
        paragraph.paragraphSpacing = settings.fontSize * 0.25
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font(settings), .foregroundColor: NSColor(white: 0.96, alpha: 1), .paragraphStyle: paragraph
        ])
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
