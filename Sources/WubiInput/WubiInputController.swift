import AppKit
import InputMethodKit
import WubiCore
import WubiUI

/// The InputMethodKit server-side controller. All typing logic lives in
/// InputEngine; this class only turns NSEvents into engine calls and paints the
/// result, which keeps the UI layer thin and the engine unit-testable.
final class WubiInputController: IMKInputController {
    private let engine = InputEngine()
    private let panel = CandidatePanel()
    private let hud = StatusHUD()
    private var punctuation = PunctuationMapper()
    private var chineseMode = true
    private weak var activeClient: IMKTextInput?

    /// A Shift press/release with no other key in between toggles the mode.
    private var shiftPending = false

    /// The controller currently serving keystrokes. A global modifier monitor
    /// cannot go through IMK (it never forwards flagsChanged), so it reports
    /// Shift presses back through this reference.
    static weak var active: WubiInputController?

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        WubiInputController.active = self
        panel.onSelect = { [weak self] offset in
            guard let self, let client = self.activeClient else { return }
            let index = self.engine.page * self.engine.pageSize + offset
            if let text = self.engine.commit(index: index) {
                self.commit(text, client: client)
            }
        }
    }

    // MARK: - Lifecycle

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        activeClient = sender as? IMKTextInput
        WubiSettings.ensureConfigFile()
        engine.settings = WubiSettings.load()
        // The settings window runs in its own process, so listen on the
        // distributed notification centre rather than the local one.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(settingsChanged),
            name: WubiSettings.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: WubiSettings.didChangeNotification,
            object: nil
        )
        engine.reset()
        panel.orderOut(nil)
        hud.hide()
    }

    override func deactivateServer(_ sender: Any!) {
        engine.reset()
        panel.orderOut(nil)
        if let client = sender as? IMKTextInput { clearMarked(client) }
        super.deactivateServer(sender)
    }

    override func inputControllerWillClose() {
        UserLexicon.shared.flush()
        super.inputControllerWillClose()
    }

    /// IMK only forwards the event kinds a controller claims. Modifier-only
    /// presses (plain Shift) arrive as flagsChanged, so ask for them explicitly.
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask(arrayLiteral: .keyDown, .flagsChanged).rawValue)
    }

    // MARK: - Event entry point

    override func handle(_ event: NSEvent, client sender: Any!) -> Bool {
        guard let client = sender as? IMKTextInput else { return false }
        activeClient = client
        switch event.type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event, client: client)
        default:
            return false
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        guard engine.settings.shiftTogglesEnglish else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isShift = flags.contains(.shift)
        let hasOther = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        if isShift && !hasOther {
            shiftPending = true
            return false
        }
        if !isShift && shiftPending {
            shiftPending = false
            toggleModeWithHUD()
        } else {
            shiftPending = false
        }
        return false
    }

    private func handleKeyDown(_ event: NSEvent, client: IMKTextInput) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return false
        }
        if flags.contains(.shift) { shiftPending = false }

        let raw = event.charactersIgnoringModifiers ?? ""

        // Navigation / editing keys first.
        switch event.keyCode {
        case 51: // delete
            guard engine.isActive else { return false }
            engine.backspace()
            refresh(client: client)
            return true
        case 117: // forward delete
            guard engine.isActive else { return false }
            engine.reset()
            refresh(client: client)
            return true
        case 53: // escape
            guard engine.isActive else { return false }
            engine.reset()
            refresh(client: client)
            return true
        case 36, 76: // return / enter: commit the raw code
            guard engine.isActive else { return false }
            commit(engine.buffer, client: client)
            return true
        case 49: // space
            // Shift+Space flips the language mode; a bare Space commits.
            if flags.contains(.shift) {
                guard engine.settings.shiftTogglesEnglish,
                      engine.settings.shiftSpaceTogglesEnglish else { return false }
                toggleModeWithHUD()
                return true
            }
            guard engine.isActive else { return false }
            if let text = engine.commitFirst() {
                commit(text, client: client)
            } else {
                engine.reset()
                refresh(client: client)
            }
            return true
        case 123, 116: // left / page up
            guard engine.isActive, engine.previousPage() else { return false }
            showPanel(client: client)
            return true
        case 124, 121: // right / page down
            guard engine.isActive, engine.nextPage() else { return false }
            showPanel(client: client)
            return true
        default:
            break
        }

        // Paging while composing.
        if engine.isActive, raw == "," || raw == "." || raw == "[" || raw == "]" {
            let forward = raw == "." || raw == "]"
            if forward ? engine.nextPage() : engine.previousPage() {
                showPanel(client: client)
                return true
            }
        }

        // Candidate numbers.
        if engine.isActive, let digit = Int(raw), (1...9).contains(digit) {
            guard let text = engine.commit(pageNumber: digit) else { return false }
            commit(text, client: client)
            return true
        }

        // Latin letters build the code.
        if let character = raw.first, character.isASCII, character.isLetter {
            guard chineseMode else { return false }
            if engine.buffer.count >= WubiCode.maxCodeLength {
                // A fifth key flushes whatever is pending and starts fresh.
                guard let text = engine.commitFirst() else {
                    engine.reset()
                    refresh(client: client)
                    return true
                }
                commit(text, client: client)
            }
            if let committed = engine.append(character) {
                commit(committed, client: client)
                return true
            }
            refresh(client: client)
            return true
        }

        // Shift + punctuation types the ASCII mark even in Chinese mode, which
        // is how you get a literal '.' or ',' inside Chinese text.
        if chineseMode, flags.contains(.shift), engine.settings.englishPunctuationWithShift,
           raw.count == 1, let character = raw.first,
           PunctuationMapper.table[character] != nil || character == "\"" || character == "'" {
            if engine.isActive, let text = engine.commitFirst() {
                commit(text, client: client, additional: raw)
            } else {
                engine.reset()
                panel.orderOut(nil)
                insert(raw, client: client)
            }
            return true
        }

        // Punctuation finishes the pending code, then emits the Chinese form.
        if chineseMode, engine.settings.chinesePunctuation, raw.count == 1, let character = raw.first {
            if let mapped = punctuation.map(character) {
                if engine.isActive, let text = engine.commitFirst() {
                    commit(text, client: client, additional: mapped)
                } else {
                    engine.reset()
                    panel.orderOut(nil)
                    insert(mapped, client: client)
                }
                return true
            }
        }

        return false
    }

    /// Flips Chinese/English, clearing any composition and announcing the new
    /// mode with the badge.
    /// Starts watching a possible bare Shift press.
    func beginShiftObservation() {
        shiftPending = true
    }

    /// Called by the global modifier monitor when Shift is released alone.
    func handleBareShiftRelease() {
        guard engine.settings.shiftTogglesEnglish, shiftPending else { return }
        shiftPending = false
        toggleModeWithHUD()
    }

    /// Any real key cancels the pending toggle, so Shift+letter still types.
    func noteShiftCancelled() {
        shiftPending = false
    }

    /// Flips Chinese/English. Anything already composed is committed first, so
    /// switching languages never silently throws away what the user typed.
    private func toggleModeWithHUD() {
        if engine.isActive, let client = activeClient {
            // Switching language keeps what was typed as typed: the pending code
            // goes on screen as English letters, not as a Chinese candidate.
            let raw = engine.buffer
            engine.reset()
            panel.orderOut(nil)
            clearMarked(client)
            insert(raw, client: client)
        }

        chineseMode.toggle()
        NSLog("WubiInput: mode -> \(chineseMode ? "中文" : "English")")
        engine.reset()
        punctuation.reset()
        if let client = activeClient { clearMarked(client) }
        panel.orderOut(nil)
        showModeHUD()
    }

    /// Badge at the caret; falls back to the top-right corner when the client
    /// cannot report a caret rectangle.
    private func showModeHUD() {
        guard engine.settings.showModeHUD else { return }
        var caret: NSRect?
        if let client = activeClient {
            var rect = NSRect.zero
            _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
            if rect.width > 0 || rect.height > 0 { caret = rect }
        }
        hud.show(chinese: chineseMode, near: caret)
    }

    // MARK: - Text plumbing

    private func refresh(client: IMKTextInput) {
        guard engine.isActive else {
            clearMarked(client)
            panel.orderOut(nil)
            return
        }
        let code = engine.buffer
        client.setMarkedText(
            code,
            selectionRange: NSRange(location: code.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        showPanel(client: client)
    }

    private func showPanel(client: IMKTextInput) {
        let texts = engine.pageCandidates.map { $0.text }
        guard !texts.isEmpty else {
            panel.orderOut(nil)
            return
        }
        var hint = engine.codeHint
        if engine.pageCount > 1 {
            hint += "  " + String(engine.page + 1) + "/" + String(engine.pageCount)
        }
        panel.update(candidates: texts, firstNumber: engine.pageStartNumber, hint: hint)
        panel.orderFront(nil)
        panel.place(near: caretRect(client: client))
    }

    private func caretRect(client: IMKTextInput) -> NSRect {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        if rect.width <= 0 || rect.height <= 0 {
            rect = NSRect(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y, width: 0, height: 18)
        }
        return rect
    }

    private func clearMarked(_ client: IMKTextInput) {
        client.setMarkedText(
            "",
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    private func commit(_ text: String, client: IMKTextInput, additional: String? = nil) {
        engine.reset()
        panel.orderOut(nil)
        if text.isEmpty {
            clearMarked(client)
        } else {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        if let additional {
            client.insertText(additional, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    private func insert(_ text: String, client: IMKTextInput) {
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: - Menu

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "五笔")

        let status = NSMenuItem(title: "五笔 86 · 轻量版", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "切换中/英文", action: #selector(toggleMode), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let prefs = NSMenuItem(title: "偏好设置…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let folder = NSMenuItem(title: "打开配置文件夹", action: #selector(openSettingsFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        let reset = NSMenuItem(title: "清除用户词频", action: #selector(resetLexicon), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        return menu
    }

    /// Picks up edits made in the settings window without restarting the method.
    @objc private func settingsChanged() {
        engine.settings = WubiSettings.load()
    }

    @objc private func toggleMode() {
        chineseMode.toggle()
    }

    /// Launches the bundled settings app.
    @objc private func openPreferences() {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Applications/WubiSettings.app")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            openSettingsFolder()
        }
    }

    @objc private func openSettingsFolder() {
        let url = WubiSettings.supportDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func resetLexicon() {
        UserLexicon.shared.reset()
    }
}