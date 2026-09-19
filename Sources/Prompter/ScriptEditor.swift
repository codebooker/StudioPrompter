import AppKit
import SwiftUI
import PrompterCore
import PrompterLayout

/// Native text editing with document snapshots so undo restores emphasis and cues together.
final class ScriptEditorSession: NSObject, ObservableObject, NSTextViewDelegate {
    @Published var bold = false
    @Published var underline = false
    @Published var selectionLength = 0
    @Published var focusedCueID: UUID?
    weak var textView: EmphasisTextView?
    weak var state: AppState?
    private var pendingCues: [Cue]?
    private struct Snapshot {
        let text: NSAttributedString
        let cues: [Cue]
        let selection: NSRange
    }
    private func snapshot() -> Snapshot? {
        guard let view = textView, let state, let storage = view.textStorage else { return nil }
        return Snapshot(text: NSAttributedString(attributedString: storage), cues: state.current.cues, selection: view.selectedRange())
    }
    private func registerUndo() {
        guard let previous = snapshot() else { return }
        textView?.undoManager?.registerUndo(withTarget: self) { $0.restore(previous) }
    }
    private func restore(_ saved: Snapshot) {
        guard let view = textView, let state else { return }
        registerUndo()
        pendingCues = nil
        view.textStorage?.setAttributedString(saved.text)
        view.setSelectedRange(saved.selection)
        view.scrollRangeToVisible(saved.selection)
        state.update {
            $0.text = saved.text.string
            $0.emphasis = ScriptTypography.emphasis(in: saved.text)
            $0.cues = saved.cues
        }
        refreshSelection()
    }

    func attach(_ view: EmphasisTextView, state: AppState) {
        textView = view; self.state = state
        view.session = self
        view.textStorage?.setAttributedString(ScriptTypography.editorText(state.current))
        view.typingAttributes = defaultAttributes
        view.delegate = self
    }
    private var defaultAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 7
        return [.font: NSFont.systemFont(ofSize: 19), .foregroundColor: NSColor(white: 0.92, alpha: 1), .paragraphStyle: paragraph]
    }
    func textViewDidChangeSelection(_ notification: Notification) { refreshSelection() }
    func refreshSelection() {
        guard let view = textView else { return }
        let range = view.selectedRange()
        selectionLength = range.length
        if range.length == 0 {
            bold = isBold(view.typingAttributes)
            underline = isUnderlined(view.typingAttributes)
        } else {
            var allBold = true, allUnderline = true
            view.textStorage?.enumerateAttributes(in: range) { attributes, _, _ in
                allBold = allBold && self.isBold(attributes)
                allUnderline = allUnderline && self.isUnderlined(attributes)
            }
            bold = allBold; underline = allUnderline
        }
    }
    private func isBold(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        (attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false
    }
    private func isUnderlined(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        ((attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0) != 0
    }
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let state, let replacementString else { return true }
        guard textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true else { return true }
        registerUndo()
        textView.undoManager?.setActionName("Edit script")
        pendingCues = CueAnchors.replacing(state.current.cues, range: affectedCharRange, replacementLength: (replacementString as NSString).length)
        return true
    }
    func textView(_ textView: NSTextView, shouldChangeTextInRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        guard let state, let replacements = replacementStrings, !replacements.isEmpty, !affectedRanges.isEmpty else { return true }
        guard textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true else { return true }
        registerUndo()
        textView.undoManager?.setActionName("Edit script")
        var cues = state.current.cues
        // Apply edits from the end so all ranges still refer to the old text.
        for index in affectedRanges.indices.sorted(by: { affectedRanges[$0].rangeValue.location > affectedRanges[$1].rangeValue.location }) {
            let replacement = replacements.count == 1 ? replacements[0] : replacements[min(index, replacements.count - 1)]
            cues = CueAnchors.replacing(cues, range: affectedRanges[index].rangeValue, replacementLength: (replacement as NSString).length)
        }
        pendingCues = cues
        return true
    }
    func textDidChange(_ notification: Notification) {
        guard let state, let view = textView, let storage = view.textStorage else { return }
        let cues = pendingCues; pendingCues = nil
        state.update {
            $0.text = storage.string
            $0.emphasis = ScriptTypography.emphasis(in: storage)
            if let cues { $0.cues = cues }
        }
        refreshSelection()
    }
    func format(_ action: String) {
        guard let view = textView, let storage = view.textStorage else { return }
        view.window?.makeFirstResponder(view)
        let range = view.selectedRange()
        let enable = action == "bold" ? !bold : !underline
        func changed(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
            var result = attributes
            if action == "bold" || action == "clear" {
                result[.font] = NSFont.systemFont(ofSize: 19, weight: action == "bold" && enable ? .bold : .regular)
            }
            if action == "underline" || action == "clear" {
                result[.underlineStyle] = action == "underline" && enable ? NSUnderlineStyle.single.rawValue : 0
            }
            return result
        }
        guard range.length > 0 else {
            view.typingAttributes = changed(view.typingAttributes); refreshSelection(); return
        }
        view.breakUndoCoalescing()
        let before = storage.attributedSubstring(from: range)
        let replacement = NSMutableAttributedString(attributedString: before)
        before.enumerateAttributes(in: NSRange(location: 0, length: before.length)) { attributes, subrange, _ in
            replacement.setAttributes(changed(attributes), range: subrange)
        }
        replaceAttributes(range: range, with: replacement)
        view.undoManager?.setActionName(action == "clear" ? "Clear emphasis" : (action == "bold" ? "Bold" : "Underline"))
    }
    private func replaceAttributes(range: NSRange, with replacement: NSAttributedString) {
        guard let view = textView, let storage = view.textStorage else { return }
        registerUndo()
        storage.replaceCharacters(in: range, with: replacement)
        view.setSelectedRange(range)
        textDidChange(Notification(name: NSText.didChangeNotification, object: view))
    }
    func addCue() {
        guard let view = textView, let state else { return }
        view.breakUndoCoalescing()
        let offset = view.selectedRange().location
        let tail = (view.string as NSString).substring(from: min(offset, (view.string as NSString).length))
        let title = tail.split(whereSeparator: { $0.isWhitespace }).prefix(5).joined(separator: " ")
        registerUndo()
        let cue = Cue(title: title.isEmpty ? "New cue" : title, progress: 0, characterOffset: offset)
        state.update { $0.cues.append(cue) }
        revealCue(cue)
        view.undoManager?.setActionName("Add cue")
    }
    func renameCue(_ id: UUID, title: String) {
        guard let state, state.current.cues.first(where: { $0.id == id })?.title != title else { return }
        registerUndo()
        state.update { script in
            if let index = script.cues.firstIndex(where: { $0.id == id }) { script.cues[index].title = title }
        }
        textView?.undoManager?.setActionName("Rename cue")
    }
    func moveCue(_ id: UUID) {
        guard let state, let view = textView else { return }
        registerUndo()
        state.update { script in
            if let index = script.cues.firstIndex(where: { $0.id == id }) { script.cues[index].characterOffset = view.selectedRange().location }
        }
        view.undoManager?.setActionName("Move cue")
        if let cue = state.current.cues.first(where: { $0.id == id }) { revealCue(cue) }
    }
    func removeCue(_ id: UUID) {
        guard let state else { return }
        registerUndo()
        state.update { $0.cues.removeAll { $0.id == id } }
        textView?.undoManager?.setActionName("Remove cue")
    }
    func revealCue(_ cue: Cue) {
        guard let view = textView else { return }
        focusedCueID = cue.id
        let range = NSRange(location: min((view.string as NSString).length, max(0, cue.characterOffset ?? 0)), length: 0)
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(range); view.scrollRangeToVisible(range)
        // Flash the anchored word, rather than the entire paragraph.
        if range.location < (view.string as NSString).length,
           !(view.string as NSString).substring(with: NSRange(location: range.location, length: 1)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            view.showFindIndicator(for: view.selectionRange(forProposedRange: range, granularity: .selectByWord))
        }
    }
}

final class EmphasisTextView: NSTextView {
    weak var session: ScriptEditorSession?
    var cues: [Cue] = [] { didSet { needsDisplay = true } }
    var focusedCueID: UUID? { didSet { if oldValue != focusedCueID { needsDisplay = true } } }
    private let cueColor = NSColor(srgbRed: 1, green: 0.49, blue: 0.29, alpha: 1)
    private struct CueMark {
        let cue: Cue
        let number: Int
        let point: NSPoint
        let line: NSRect
    }
    // Decorations live outside text storage: copying, formatting, undo and
    // Markdown export never acquire marker characters or highlight attributes.
    private func cueMarks() -> [CueMark] {
        guard let manager = layoutManager, let container = textContainer else { return [] }
        manager.ensureLayout(for: container)
        let origin = textContainerOrigin
        let length = (string as NSString).length
        return cues.enumerated().map { index, cue in
            let offset = min(length, max(0, cue.characterOffset ?? 0))
            var line: NSRect
            var point: NSPoint
            if offset == length, manager.extraLineFragmentTextContainer != nil {
                line = manager.extraLineFragmentRect
                point = NSPoint(x: container.lineFragmentPadding, y: line.minY)
            } else if manager.numberOfGlyphs > 0 {
                let glyph = manager.glyphIndexForCharacter(at: min(offset, max(0, length - 1)))
                line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                point = manager.location(forGlyphAt: glyph)
                point.x += line.minX
                point.y = line.minY
                if offset == length {
                    point.x = manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).maxX
                }
            } else {
                line = NSRect(x: 0, y: 0, width: container.size.width, height: 30)
                point = NSPoint(x: container.lineFragmentPadding, y: 0)
            }
            line.origin.x += origin.x; line.origin.y += origin.y
            point.x += origin.x; point.y += origin.y
            return CueMark(cue: cue, number: index + 1, point: point, line: line)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        let marks = cueMarks()
        for mark in marks where mark.line.intersects(dirtyRect) {
            cueColor.withAlphaComponent(mark.cue.id == focusedCueID ? 0.12 : 0.045).setFill()
            NSBezierPath(roundedRect: NSRect(x: textContainerOrigin.x, y: mark.line.minY,
                width: max(0, bounds.width - textContainerOrigin.x - 8), height: mark.line.height), xRadius: 4, yRadius: 4).fill()
        }
        NSGraphicsContext.saveGraphicsState()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
        // Group cues on the same visual line so their gutter badges never overlap.
        let groups = Dictionary(grouping: marks, by: { Int($0.line.minY.rounded()) })
        for group in groups.values {
            guard let first = group.first, first.line.intersects(dirtyRect) else { continue }
            let selected = group.contains { $0.cue.id == focusedCueID }
            let label = group.count == 1 ? "\(first.number)" : "\(first.number)+\(group.count - 1)"
            let badge = NSRect(x: 3, y: first.line.minY + 2, width: 36, height: 22)
            cueColor.withAlphaComponent(selected ? 1 : 0.18).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
                .foregroundColor: selected ? NSColor.black : cueColor]
            let size = (label as NSString).size(withAttributes: attributes)
            (label as NSString).draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), withAttributes: attributes)
            for mark in group {
                cueColor.setFill()
                NSRect(x: mark.point.x - 2, y: mark.line.minY + 2, width: 2, height: max(16, mark.line.height - 4)).fill()
                let flag = NSBezierPath()
                flag.move(to: NSPoint(x: mark.point.x - 2, y: mark.line.minY + 1))
                flag.line(to: NSPoint(x: mark.point.x + 5, y: mark.line.minY + 1))
                flag.line(to: NSPoint(x: mark.point.x - 2, y: mark.line.minY + 7))
                flag.close(); flag.fill()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.x < textContainerOrigin.x {
            let group = cueMarks().filter { point.y >= $0.line.minY && point.y < $0.line.maxY }
            if !group.isEmpty {
                let next = group.firstIndex(where: { $0.cue.id == focusedCueID }).map { ($0 + 1) % group.count } ?? 0
                session?.revealCue(group[next].cue)
                return
            }
        }
        super.mouseDown(with: event)
    }
    private let editingUndoManager: UndoManager = {
        let manager = UndoManager()
        manager.levelsOfUndo = 100
        return manager
    }()
    override var undoManager: UndoManager? { editingUndoManager }
    @objc func undo(_ sender: Any?) { if editingUndoManager.canUndo { editingUndoManager.undo() } }
    @objc func redo(_ sender: Any?) { if editingUndoManager.canRedo { editingUndoManager.redo() } }
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undo(_:)) { return editingUndoManager.canUndo }
        if menuItem.action == #selector(redo(_:)) { return editingUndoManager.canRedo }
        return super.validateMenuItem(menuItem)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers?.lowercased() == "z", modifiers == .command || modifiers == [.command, .shift] {
            if modifiers.contains(.shift) { redo(nil) } else { undo(nil) }
            return true
        }
        if modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "b": session?.format("bold"); return true
            case "u": session?.format("underline"); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    // Paste words into the script's typography; foreign colors/sizes cannot leak
    // onto the prompter. Supported bold/underline survive rich-text paste.
    override func paste(_ sender: Any?) {
        if let data = NSPasteboard.general.data(forType: .rtf),
           let rich = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            var script = Script(title: "", text: rich.string)
            script.emphasis = ScriptTypography.emphasis(in: rich)
            insertText(ScriptTypography.editorText(script), replacementRange: selectedRange())
        } else { pasteAsPlainText(sender) }
    }
}

private struct NativeScriptEditor: NSViewRepresentable {
    let state: AppState
    let session: ScriptEditorSession
    let cues: [Cue]
    let focusedCueID: UUID?
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let view = EmphasisTextView(frame: .zero)
        view.isRichText = true; view.importsGraphics = false; view.allowsUndo = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isContinuousSpellCheckingEnabled = true
        view.usesFindBar = true; view.isIncrementalSearchingEnabled = true
        view.drawsBackground = false; view.insertionPointColor = .white
        view.textContainerInset = NSSize(width: 44, height: 14)
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel("Script text")
        scroll.documentView = view
        session.attach(view, state: state)
        view.cues = cues
        view.focusedCueID = focusedCueID
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let editor = view.documentView as? EmphasisTextView else { return }
        let revealAfterLayout = editor.focusedCueID != focusedCueID || editor.cues.count != cues.count
        editor.cues = cues
        editor.focusedCueID = focusedCueID
        if revealAfterLayout, let id = focusedCueID, cues.contains(where: { $0.id == id }) {
            let selection = editor.selectedRange()
            // Adding a cue can enlarge the list and shorten the text viewport.
            // Reveal again after SwiftUI has applied the new frame.
            DispatchQueue.main.async { [weak editor] in
                guard let editor, editor.focusedCueID == id, editor.selectedRange() == selection else { return }
                editor.window?.contentView?.layoutSubtreeIfNeeded()
                editor.scrollRangeToVisible(selection)
            }
        }
    }
}

struct ScriptEditorView: View {
    @ObservedObject var state: AppState
    @StateObject private var session = ScriptEditorSession()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "SCRIPT EDITOR", trailing: "Markdown · Autosaved")
            TextField("Script title", text: Binding(get: { state.current.title }, set: { value in state.update { $0.title = value } }))
                .font(.system(size: 22, weight: .semibold)).textFieldStyle(.plain).accessibilityLabel("Script title")
            HStack(spacing: 6) {
                formatButton("bold", title: "Bold", shortcut: "⌘B", active: session.bold)
                formatButton("underline", title: "Underline", shortcut: "⌘U", active: session.underline)
                Button { session.format("clear") } label: { Image(systemName: "textformat").frame(width: 30, height: 30) }
                    .buttonStyle(.plain).help("Clear emphasis").accessibilityLabel("Clear emphasis")
                Rectangle().fill(Palette.border).frame(width: 1, height: 20).padding(.horizontal, 5)
                Button { session.addCue() } label: { Label("Add cue", systemImage: "bookmark.badge.plus").font(.system(size: 11, weight: .medium)) }
                    .buttonStyle(QuietButton()).help("Add a cue at the text cursor (⌘⌥B)")
                Spacer(minLength: 0)
                Text(session.selectionLength > 0 ? "Emphasize your selection" : "Select words to emphasize")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Divider().overlay(Palette.border)
            NativeScriptEditor(state: state, session: session, cues: state.current.cues, focusedCueID: session.focusedCueID).frame(minHeight: 140)
            Divider().overlay(Palette.border)
            cueEditor
            Text("Numbered markers show cue locations. The orange flag marks the exact position. Click a number to find it.")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(18).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            .onAppear { state.activeEditor = session; state.anchorCues() }
            .onDisappear { if state.activeEditor === session { state.activeEditor = nil } }
    }
    private func formatButton(_ icon: String, title: String, shortcut: String, active: Bool) -> some View {
        Button { session.format(icon) } label: {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).frame(width: 32, height: 30)
                .foregroundStyle(active ? Palette.accent : .white.opacity(0.85))
                .background(active ? Palette.accent.opacity(0.14) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).help("\(title) (\(shortcut))").accessibilityLabel(title).accessibilityValue(active ? "On" : "Off")
    }
    private var cueEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "CUE POINTS", trailing: "\(state.current.cues.count)")
            if state.current.cues.isEmpty {
                Text("Place your cursor at a passage, then choose Add cue.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.vertical, 5)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(state.current.cues) { cue in
                            HStack(spacing: 8) {
                                Button { session.revealCue(cue) } label: {
                                    Text("\((state.current.cues.firstIndex(where: { $0.id == cue.id }) ?? 0) + 1)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .frame(width: 26, height: 24)
                                        .foregroundStyle(session.focusedCueID == cue.id ? Color.black : Palette.accent)
                                        .background(Palette.accent.opacity(session.focusedCueID == cue.id ? 1 : 0.14), in: RoundedRectangle(cornerRadius: 5))
                                }
                                    .buttonStyle(.plain).help("Find this cue in the script").accessibilityLabel("Find cue \(cue.title)")
                                TextField("Cue name", text: Binding(get: { state.current.cues.first(where: { $0.id == cue.id })?.title ?? "" }, set: { session.renameCue(cue.id, title: $0) }))
                                    .textFieldStyle(.plain).font(.system(size: 11)).accessibilityLabel("Cue name")
                                Button("Move here") { session.moveCue(cue.id) }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                                    .help("Move this cue to the script cursor")
                                Button("Find") { session.revealCue(cue) }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                                    .help("Show the exact cue position in the editor").accessibilityLabel("Show cue \(cue.title)")
                                Button { session.removeCue(cue.id) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain).foregroundStyle(Palette.muted).help("Remove cue").accessibilityLabel("Remove cue \(cue.title)")
                            }.font(.system(size: 10)).padding(8).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }.frame(height: min(122, CGFloat(state.current.cues.count) * 46))
            }
        }
    }
}
