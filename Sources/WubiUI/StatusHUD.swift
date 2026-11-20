import AppKit
import WubiCore

/// A short-lived badge that shows which mode the user just switched to:
/// a single glyph icon, 中 for Chinese and A for English. It sits at the caret
/// when the client reports one and falls back to the top-right corner of the
/// active screen so it is never lost.
public final class StatusHUD {
    private let panel: NSPanel
    private let imageView = NSImageView()
    private let schemeLabel = NSTextField(labelWithString: "")
    private var hideWorkItem: DispatchWorkItem?
    private var imageCache: [String: NSImage] = [:]

    /// Roughly the size of the system's own input mode indicator.
    private let iconSize: CGFloat = 30

    public init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: iconSize, height: iconSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        // The artwork already has its own rounded shape; no extra clipping needed.
        imageView.layer?.cornerRadius = 0
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: content.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        schemeLabel.alignment = .center
        schemeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        schemeLabel.textColor = .white
        schemeLabel.drawsBackground = false
        schemeLabel.isHidden = true
        content.addSubview(schemeLabel)
        panel.contentView = content
        panel.alphaValue = 0
    }

    /// Shows the badge for the given mode near the caret.
    public func show(chinese: Bool, near caret: NSRect?) {
        schemeLabel.isHidden = true
        imageView.isHidden = false
        panel.backgroundColor = .clear
        imageView.image = image(for: chinese)
        panel.setContentSize(NSSize(width: iconSize, height: iconSize))
        present(near: caret)
    }

    /// Unlike the language badge, a scheme switch identifies the exact scheme.
    public func show(scheme: InputScheme, near caret: NSRect?) {
        imageView.isHidden = true
        schemeLabel.stringValue = scheme.displayName
        schemeLabel.sizeToFit()
        let width = ceil(schemeLabel.frame.width) + 20
        panel.setContentSize(NSSize(width: width, height: iconSize))
        schemeLabel.frame = NSRect(x: 0, y: (iconSize - schemeLabel.frame.height) / 2,
                                   width: width, height: schemeLabel.frame.height)
        schemeLabel.isHidden = false
        panel.backgroundColor = NSColor(white: 0.15, alpha: 0.92)
        present(near: caret)
    }

    private func present(near caret: NSRect?) {
        position(near: caret)
        panel.alphaValue = 1
        // The input method runs as a background agent: orderFront alone can be
        // ignored, orderFrontRegardless puts the badge on screen anyway.
        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: item)
    }

    public func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    private func position(near caret: NSRect?) {
        let size = panel.frame.size
        let screenForCaret = caret.flatMap { rect in
            NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.minX, y: rect.minY)) }
        }
        let screen = screenForCaret ?? NSScreen.main

        var origin: NSPoint
        if let caret, caret.width > 0 || caret.height > 0 {
            origin = NSPoint(x: caret.minX, y: caret.minY - size.height - 6)
        } else if let visible = screen?.visibleFrame {
            origin = NSPoint(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 16)
        } else {
            origin = NSPoint(x: 20, y: 20)
        }

        if let visible = screen?.visibleFrame {
            if origin.y < visible.minY + 4 { origin.y = (caret?.maxY ?? visible.maxY) + 6 }
            if origin.x + size.width > visible.maxX - 4 { origin.x = visible.maxX - size.width - 4 }
            origin.x = max(origin.x, visible.minX + 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        }
        panel.setFrameOrigin(origin)
    }

    private func image(for chinese: Bool) -> NSImage? {
        let key = chinese ? "zh" : "en"
        if let cached = imageCache[key] { return cached }
        let name = chinese ? "hud-zh" : "hud-en"
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        imageCache[key] = image
        return image
    }
}