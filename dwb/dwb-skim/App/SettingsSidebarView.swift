import AppKit

// The Settings sidebar (design system `SettingsSidebar`): solid `canvas`, 188 pt wide,
// grouped page rows (32 pt, radius 6, text only). The selected row is `accentTintStrong`
// with a 1 pt `accentFill` ring and semibold text.

/// A 10 pt bold, uppercase, +4% tracked label (design system caps labels).
final class DWBCapsLabel: NSTextField {

    enum Tone {
        case tertiary
        case accent
    }

    private let tone: Tone
    private let source: String

    init(_ text: String, tone: Tone) {
        self.tone = tone
        self.source = text
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        lineBreakMode = .byTruncatingTail
        setAccessibilityLabel(text)
        applyStyle()
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private func applyStyle() {
        let color = tone == .accent ? theme.accentText : DWBAccessibility.textTertiary
        attributedStringValue = NSAttributedString(string: source.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: color,
            .kern: 0.4,
        ])
    }

    @objc private func accessibilityDidChange() {
        applyStyle()
    }
}

final class SettingsSidebarView: NSView {

    private(set) var buttons: [SettingsSidebarButton] = []

    init(groups: [SettingsPresentation.SidebarGroup],
         sections: [SettingsWindowController.Section],
         target: AnyObject?,
         action: Selector) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = DWBColor.canvas.cgColor

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 14
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        // 48 pt from the window top: the 28 pt title bar plus the design system's 20 pt.
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            outer.topAnchor.constraint(equalTo: topAnchor, constant: 48),
        ])

        for group in groups {
            let groupStack = NSStackView()
            groupStack.orientation = .vertical
            groupStack.alignment = .leading
            groupStack.spacing = 2
            groupStack.translatesAutoresizingMaskIntoConstraints = false

            let label = DWBCapsLabel(group.label, tone: group.isAccented ? .accent : .tertiary)
            label.translatesAutoresizingMaskIntoConstraints = false
            let labelHolder = NSView()
            labelHolder.translatesAutoresizingMaskIntoConstraints = false
            labelHolder.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: labelHolder.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: labelHolder.trailingAnchor),
                label.topAnchor.constraint(equalTo: labelHolder.topAnchor),
                label.bottomAnchor.constraint(equalTo: labelHolder.bottomAnchor, constant: -4),
            ])
            groupStack.addArrangedSubview(labelHolder)
            labelHolder.widthAnchor.constraint(equalTo: groupStack.widthAnchor).isActive = true

            for identifier in group.paneIdentifiers {
                guard let section = sections.first(where: { $0.identifier == identifier }) else { continue }
                let button = SettingsSidebarButton(title: section.title,
                                                   section: section,
                                                   target: target,
                                                   action: action)
                button.translatesAutoresizingMaskIntoConstraints = false
                groupStack.addArrangedSubview(button)
                button.widthAnchor.constraint(equalTo: groupStack.widthAnchor).isActive = true
                button.heightAnchor.constraint(equalToConstant: SettingsPresentation.sidebarRowHeight).isActive = true
                buttons.append(button)
            }

            outer.addArrangedSubview(groupStack)
            groupStack.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    func select(_ section: SettingsWindowController.Section) {
        buttons.forEach { $0.isSelected = $0.section == section }
    }
}

final class SettingsSidebarButton: NSButton {
    let section: SettingsWindowController.Section
    var isSelected = false {
        didSet {
            setAccessibilityValue(isSelected ? "selected" : "not selected")
            needsDisplay = true
        }
    }
    private var isHovering = false
    private var trackingAreaReference: NSTrackingArea?

    init(title: String,
         section: SettingsWindowController.Section,
         target: AnyObject?,
         action: Selector) {
        self.section = section
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryPushIn)
        setAccessibilityLabel(title)
        setAccessibilityIdentifier(section.identifier)
        setAccessibilityValue("not selected")
        toolTip = title
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusControl, yRadius: DWBMetrics.radiusControl)
        if isSelected {
            theme.accentTintStrong.setFill()
            path.fill()
            theme.accentFill.setStroke()
            path.lineWidth = 1
            path.stroke()
        } else if isHovering {
            DWBColor.overlayHover.setFill()
            path.fill()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular),
            .foregroundColor: DWBColor.textPrimary,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: 13, y: floor((bounds.height - size.height) / 2)),
                                 withAttributes: attributes)

        if let window, window.isKeyWindow, window.firstResponder === self {
            let width = DWBAccessibility.focusWidth
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2),
                                    xRadius: DWBMetrics.radiusControl, yRadius: DWBMetrics.radiusControl)
            ring.lineWidth = width
            DWBAccessibility.focusRing.setStroke()
            ring.stroke()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let tracking = NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self,
                                      userInfo: nil)
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    @objc private func accessibilityDidChange() {
        needsDisplay = true
    }
}
