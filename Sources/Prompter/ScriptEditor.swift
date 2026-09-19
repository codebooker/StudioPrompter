import AppKit
import SwiftUI
import PrompterCore
import PrompterLayout

/// Native text editing with document snapshots so undo restores emphasis and cues together.
final class ScriptEditorSession: NSObject, ObservableObject, NSTextViewDelegate {
    @Published var bold = false
    @Published var underline = false
    @Published var selectionLength = 0
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
        state.update { $0.cues.append(Cue(title: title.isEmpty ? "New cue" : title, progress: 0, characterOffset: offset)) }
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
    }
    func removeCue(_ id: UUID) {
        guard let state else { return }
        registerUndo()
        state.update { $0.cues.removeAll { $0.id == id } }
        textView?.undoManager?.setActionName("Remove cue")
    }
    func revealCue(_ cue: Cue) {
        guard let view = textView else { return }
        let range = NSRange(location: min((view.string as NSString).length, max(0, cue.characterOffset ?? 0)), length: 0)
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(range); view.scrollRangeToVisible(range)
        view.showFindIndicator(for: (view.string as NSString).lineRange(for: range))
    }
}

final class EmphasisTextView: NSTextView {
    weak var session: ScriptEditorSession?
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
        view.textContainerInset = NSSize(width: 8, height: 14)
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel("Script text")
        scroll.documentView = view
        session.attach(view, state: state)
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {}
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
            NativeScriptEditor(state: state, session: session).frame(minHeight: 140)
            Divider().overlay(Palette.border)
            cueEditor
            Text("Emphasis appears on both displays. Cues stay with their passage as you edit.")
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
                                Button { session.revealCue(cue) } label: { Image(systemName: "bookmark.fill").foregroundStyle(Palette.accent) }
                                    .buttonStyle(.plain).help("Find this cue in the script").accessibilityLabel("Find cue \(cue.title)")
                                TextField("Cue name", text: Binding(get: { state.current.cues.first(where: { $0.id == cue.id })?.title ?? "" }, set: { session.renameCue(cue.id, title: $0) }))
                                    .textFieldStyle(.plain).font(.system(size: 11)).accessibilityLabel("Cue name")
                                Button("Move here") { session.moveCue(cue.id) }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                                    .help("Move this cue to the script cursor")
                                Button { session.removeCue(cue.id) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain).foregroundStyle(Palette.muted).help("Remove cue").accessibilityLabel("Remove cue \(cue.title)")
                            }.font(.system(size: 10)).padding(8).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }.frame(height: min(104, CGFloat(state.current.cues.count) * 37))
            }
        }
    }
}
