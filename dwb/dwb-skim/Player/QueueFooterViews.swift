import Cocoa

// The queue footer's marker chip group (design system "File markers").
//
// The group is 28 pt tall, radius 12, `surfaceElevated` with a 1 pt `border`. It holds
// the primary and secondary prefix chips and ends with the Undo button. The `N`, `M` and
// `⌘Z` hints are not drawn; they stay in the tooltips and accessibility labels. The chips keep the one-click
// behavior of the prefix buttons; this file only draws them.

final class QueueMarkerChipGroupView: NSView {

    static let height: CGFloat = 28

    var onChipTapped: ((QueueMarkerChip.Kind) -> Void)?
    var onUndoTapped: (() -> Void)?

    var isUndoEnabled = false {
        didSet { undoButton.isEnabled = isUndoEnabled }
    }

    /// Undo shows only its glyph. The footer sets this from `QueueFooterPresentation.markerGroupPlan`.
    var isUndoCompact = false {
        didSet {
            guard isUndoCompact != oldValue else { return }
            undoButton.isCompact = isUndoCompact
            needsLayout = true
            invalidateIntrinsicContentSize()
        }
    }

    private var chips: [QueueMarkerChip] = []
    private var chipButtons: [QueueMarkerChipButton] = []
    private let divider = DWBRuleView(kind: .border, vertical: true)
    private let undoButton = QueueUndoButton()

    private let sidePadding: CGFloat = 3
    private let chipGap: CGFloat = 2
    private let dividerInset: CGFloat = 3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(divider)
        undoButton.target = self
        undoButton.action = #selector(undoTapped)
        undoButton.isEnabled = false
        addSubview(undoButton)
        setAccessibilityRole(.group)
        setAccessibilityLabel("File markers")
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(chips: [QueueMarkerChip]) {
        self.chips = chips
        rebuildChips()
    }

    private func rebuildChips() {
        chipButtons.forEach { $0.removeFromSuperview() }
        chipButtons = []
        for chip in chips {
            let button = QueueMarkerChipButton(chip: chip)
            button.target = self
            button.action = #selector(chipTapped(_:))
            addSubview(button)
            chipButtons.append(button)
        }
        divider.isHidden = chipButtons.isEmpty
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    /// The width the group needs with Undo spelled out (`compactUndo` false) or glyph-only.
    func width(compactUndo: Bool) -> CGFloat {
        var width = sidePadding * 2
        for button in chipButtons {
            width += button.intrinsicContentSize.width + chipGap
        }
        if !chipButtons.isEmpty {
            // The last chip gap is replaced by the divider block.
            width += -chipGap + dividerInset * 2 + 1
        }
        width += QueueUndoButton.width(compact: compactUndo)
        return ceil(width)
    }

    override func layout() {
        super.layout()
        let chipHeight: CGFloat = 22
        let y = floor((bounds.height - chipHeight) / 2)
        var x = sidePadding
        for button in chipButtons {
            let size = button.intrinsicContentSize
            button.frame = NSRect(x: x, y: y, width: size.width, height: chipHeight)
            x += size.width + chipGap
        }
        if !chipButtons.isEmpty {
            x += -chipGap + dividerInset
            divider.frame = NSRect(x: x, y: floor((bounds.height - 14) / 2), width: 1, height: 14)
            x += 1 + dividerInset
        }
        let undoSize = undoButton.intrinsicContentSize
        undoButton.frame = NSRect(x: x, y: y, width: undoSize.width, height: chipHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: QueueFooterPresentation.markerGroupCornerRadius,
                                yRadius: QueueFooterPresentation.markerGroupCornerRadius)
        DWBColor.surfaceElevated.setFill()
        path.fill()
        DWBAccessibility.border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    @objc private func chipTapped(_ sender: QueueMarkerChipButton) {
        onChipTapped?(sender.chip.kind)
    }

    @objc private func undoTapped() {
        onUndoTapped?()
    }
}

// MARK: - Chip

/// A prefix chip (`N` primary, `M` secondary): 22 pt tall, `radiusPill` like the group outline, the trimmed prefix in
/// monospaced 11 pt semibold, with no key tag drawn. Applied chips take the marker fill at 18% with a 1 pt
/// marker-fill edge. A blank prefix shows "—" in `textDisabled` and is disabled.
private final class QueueMarkerChipButton: NSButton {

    let chip: QueueMarkerChip
    private var isHovering = false
    private var trackingAreaReference: NSTrackingArea?

    init(chip: QueueMarkerChip) {
        self.chip = chip
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        isEnabled = chip.isEnabled
        title = chip.label
        setAccessibilityLabel(chip.accessibilityLabel)
        setAccessibilityValue(chip.accessibilityValue)
        toolTip = chip.tooltip
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError() }

    private let horizontalPadding: CGFloat = 8

    private var labelFont: NSFont { .monospacedSystemFont(ofSize: 11, weight: .semibold) }

    private func width(of string: String, font: NSFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: horizontalPadding * 2 + width(of: chip.label, font: labelFont), height: 22)
    }

    private var markerColor: NSColor {
        chip.kind == .primary ? theme.markerPrimary : theme.markerSecondary
    }

    private var markerFill: NSColor {
        chip.kind == .primary ? theme.markerPrimaryFill : theme.markerSecondaryFill
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: QueueFooterPresentation.markerGroupCornerRadius,
                                yRadius: QueueFooterPresentation.markerGroupCornerRadius)
        if chip.isApplied {
            markerFill.withAlphaComponent(0.18).setFill()
            path.fill()
            markerFill.setStroke()
            path.lineWidth = 1
            path.stroke()
        } else if isHovering, chip.isEnabled {
            DWBColor.overlayHover.setFill()
            path.fill()
        }

        let prefixColor = chip.isEnabled ? markerColor : DWBColor.textDisabled
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: prefixColor]
        let labelSize = (chip.label as NSString).size(withAttributes: labelAttributes)
        (chip.label as NSString).draw(at: NSPoint(x: floor((bounds.width - labelSize.width) / 2),
                                                  y: floor((bounds.height - labelSize.height) / 2)),
                                      withAttributes: labelAttributes)
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingAreaReference = area
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

// MARK: - Undo

/// The group's Undo button: `arrow.uturn.backward` and "Undo", 22 pt tall, `radiusPill` like the group outline, with no
/// `⌘Z` hint drawn. At narrow widths it shows only the glyph.
private final class QueueUndoButton: NSButton {

    var isCompact = false {
        didSet {
            guard isCompact != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private var isHovering = false
    private var trackingAreaReference: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        title = "Undo"
        toolTip = "Undo the last prefix change (⌘Z)"
        setAccessibilityLabel("Undo last prefix change")
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    private var padding: CGFloat { isCompact ? 6 : 8 }
    private let glyphSize: CGFloat = 12
    private var labelFont: NSFont { .systemFont(ofSize: 11, weight: .semibold) }

    private func width(of string: String, font: NSFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width(compact: isCompact), height: 22)
    }

    /// The button's width with its word ("Undo") or with the glyph only.
    static func width(compact: Bool) -> CGFloat {
        let padding: CGFloat = compact ? 6 : 8
        var width = padding * 2 + 12
        if !compact {
            let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            width += 5 + ceil(("Undo" as NSString).size(withAttributes: [.font: font]).width)
        }
        return ceil(width)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovering, isEnabled {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: QueueFooterPresentation.markerGroupCornerRadius,
                                    yRadius: QueueFooterPresentation.markerGroupCornerRadius)
            DWBColor.overlayHover.setFill()
            path.fill()
        }

        let color = isEnabled ? DWBColor.textPrimary : DWBColor.textDisabled
        var x = padding
        if let glyph = NSImage.dwbSymbol("arrow.uturn.backward", pointSize: glyphSize, color: color) {
            glyph.draw(in: NSRect(x: x, y: floor((bounds.height - glyph.size.height) / 2),
                                  width: glyph.size.width, height: glyph.size.height))
            x += glyphSize
        }
        guard !isCompact else { return }
        x += 5
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: color]
        let labelSize = ("Undo" as NSString).size(withAttributes: labelAttributes)
        ("Undo" as NSString).draw(at: NSPoint(x: x, y: floor((bounds.height - labelSize.height) / 2)),
                                  withAttributes: labelAttributes)
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingAreaReference = area
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
