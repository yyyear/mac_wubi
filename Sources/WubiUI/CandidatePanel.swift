import AppKit

/// One candidate cell: small index digit + word, highlight when selected.
final class CandidateCell: NSView {
    private let numberLabel = NSTextField(labelWithString: "")
    private let textLabel = NSTextField(labelWithString: "")
    var onSelect: (() -> Void)?

    override var isFlipped: Bool { true }

    init(number: Int, text: String, highlighted: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5

        numberLabel.stringValue = String(number)
        numberLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        numberLabel.textColor = highlighted ? .white : .secondaryLabelColor
        numberLabel.alignment = .center

        textLabel.stringValue = text
        textLabel.font = .systemFont(ofSize: 16, weight: highlighted ? .medium : .regular)
        textLabel.textColor = highlighted ? .white : .labelColor
        textLabel.lineBreakMode = .byClipping

        for label in [numberLabel, textLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            addSubview(label)
        }

        NSLayoutConstraint.activate([
            numberLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            numberLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            numberLabel.widthAnchor.constraint(equalToConstant: 10),
            textLabel.leadingAnchor.constraint(equalTo: numberLabel.trailingAnchor, constant: 3),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        layer?.backgroundColor = highlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            : NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }
}

/// Floating candidate strip. A plain non-activating NSPanel keeps the focus in
/// the host app, so committing a candidate never steals keystrokes.
public final class CandidatePanel: NSPanel {
    private let blur = NSVisualEffectView()
    private let stack = NSStackView()
    private let hintLabel = NSTextField(labelWithString: "")

    public var onSelect: ((Int) -> Void)?

    public init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 120, height: 28),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        ignoresMouseEvents = false

        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 8
        blur.layer?.masksToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(blur)
        content.addSubview(stack)
        content.addSubview(hintLabel)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            blur.topAnchor.constraint(equalTo: content.topAnchor),
            blur.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            hintLabel.leadingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 4),
            hintLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            hintLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        contentView = content
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public func update(candidates: [String], firstNumber: Int, hint: String) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (offset, text) in candidates.enumerated() {
            let cell = CandidateCell(number: firstNumber + offset, text: text, highlighted: offset == 0)
            cell.onSelect = { [weak self] in self?.onSelect?(offset) }
            stack.addArrangedSubview(cell)
        }
        hintLabel.stringValue = hint
        hintLabel.isHidden = hint.isEmpty

        contentView?.layoutSubtreeIfNeeded()
        let fitting = contentView?.fittingSize ?? NSSize(width: 120, height: 28)
        setContentSize(NSSize(width: ceil(fitting.width) + 2, height: ceil(fitting.height)))
    }

    /// Places the strip just under the caret, flipping above it when the caret
    /// sits close to the bottom of the screen.
    public func place(near caret: NSRect) {
        let size = frame.size
        var origin = NSPoint(x: caret.minX, y: caret.minY - size.height - 4)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: caret.minX, y: caret.minY)) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            if origin.y < visible.minY + 2 { origin.y = caret.maxY + 4 }
            if origin.x + size.width > visible.maxX - 4 { origin.x = visible.maxX - size.width - 4 }
            origin.x = max(origin.x, visible.minX + 4)
            origin.y = min(max(origin.y, visible.minY + 2), visible.maxY - size.height - 2)
        }
        setFrameOrigin(origin)
    }
}