import AppKit
import WubiCore
import WubiUI

/// A tiny host application that exercises the real engine and the real
/// candidate panel outside of InputMethodKit. Handy for development, demos and
/// UI checks on machines where the input method is not enabled yet.

final class PreviewTextView: NSTextView {
    var engine: InputEngine?
    var panel: CandidatePanel?
    var onUpdate: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        guard let engine, panel != nil else { return super.keyDown(with: event) }
        guard event.type == .keyDown else { return super.keyDown(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return super.keyDown(with: event)
        }

        let raw = event.charactersIgnoringModifiers ?? ""

        switch event.keyCode {
        case 51:
            guard engine.isActive else { return super.keyDown(with: event) }
            engine.backspace()
            onUpdate?()
            return
        case 53:
            guard engine.isActive else { return super.keyDown(with: event) }
            engine.reset()
            onUpdate?()
            return
        case 36:
            guard engine.isActive else { return super.keyDown(with: event) }
            let text = engine.buffer
            engine.reset()
            insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            onUpdate?()
            return
        case 49:
            guard engine.isActive else { return super.keyDown(with: event) }
            if let text = engine.commitFirst() {
                insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            onUpdate?()
            return
        case 123:
            guard engine.isActive, engine.previousPage() else { return super.keyDown(with: event) }
            onUpdate?()
            return
        case 124:
            guard engine.isActive, engine.nextPage() else { return super.keyDown(with: event) }
            onUpdate?()
            return
        default:
            break
        }

        if engine.isActive, let digit = Int(raw), (1...9).contains(digit) {
            if let text = engine.commit(pageNumber: digit) {
                insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
                onUpdate?()
                return
            }
        }

        let separator = raw == "'" && !flags.contains(.shift) && engine.isActive && engine.settings.inputScheme != .wubi
        if let character = raw.first, (character.isASCII && character.isLetter) || separator {
            if engine.settings.inputScheme == .wubi && engine.buffer.count >= WubiCode.maxCodeLength {
                if let text = engine.commitFirst() {
                    insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
                }
            }
            if let committed = engine.append(character) {
                insertText(committed, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            onUpdate?()
            return
        }

        super.keyDown(with: event)
    }
}

final class PreviewWindowController: NSWindowController, NSTextViewDelegate {
    let engine = InputEngine()
    let panel = CandidatePanel()
    let textView = PreviewTextView()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "五笔输入法 · 预览"
        // Centre on the display holding the pointer; window.center() can land on
        // an inactive display in multi-monitor setups.
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen = pointerScreen {
            let size = window.frame.size
            let origin = NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2
            )
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let window, let content = window.contentView else { return }

        let scroll = NSScrollView(frame: content.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true

        textView.minSize = NSSize(width: 0, height: content.bounds.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 18)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.string = "当前方案：\(engine.settings.inputScheme.displayName)。输入示例：五笔 wqiy（你），全拼 nihao（你好）。"
        textView.engine = engine
        textView.panel = panel
        textView.onUpdate = { [weak self] in self?.refreshPanel() }

        scroll.documentView = textView
        content.addSubview(scroll)

        panel.onSelect = { [weak self] offset in
            guard let self else { return }
            guard let text = self.engine.commit(index: self.engine.page * self.engine.pageSize + offset) else { return }
            self.textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            self.refreshPanel()
        }

        window.makeFirstResponder(textView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshPanel() {
        guard engine.isActive else {
            panel.orderOut(nil)
            return
        }
        let texts = engine.pageCandidates.map { $0.text }
        guard !texts.isEmpty else {
            panel.orderOut(nil)
            return
        }
        var hint = engine.codeHint
        if engine.pageCount > 1 { hint += "  " + String(engine.page + 1) + "/" + String(engine.pageCount) }
        panel.update(candidates: texts, firstNumber: engine.pageStartNumber, hint: hint)

        var caret = NSRect.zero
        if let layout = textView.layoutManager, let container = textView.textContainer {
            let location = textView.selectedRange().location
            let glyphRange = layout.glyphRange(forCharacterRange: NSRange(location: location, length: 0), actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
            let origin = textView.textContainerOrigin
            let inWindow = NSRect(x: rect.minX + origin.x, y: rect.minY + origin.y, width: 2, height: rect.height)
            let inScreen = textView.window?.convertToScreen(textView.convert(inWindow, to: nil)) ?? .zero
            caret = inScreen
        }
        panel.orderFront(nil)
        panel.place(near: caret)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let controller = PreviewWindowController()
let delegate = AppDelegate()
app.delegate = delegate
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
