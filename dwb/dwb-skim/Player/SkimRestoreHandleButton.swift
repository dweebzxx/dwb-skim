import Cocoa

/// The Skim restore handle: just a `chevron.down` at the top edge of the content area, shown while
/// the settings strip is collapsed. It has no fill or edge, so it never shows two tones where it
/// straddles the letterbox and the video; the chevron keeps its contrast from the brightest text role
/// and a soft black shadow, the design system's treatment for a layer floating over video. The 40 × 24
/// hit area and the 13 pt chevron are the design system's (9.8).
final class SkimRestoreHandleButton: NSButton {
    static let size = NSSize(width: SkimRestoreHandleGeometry.size.width,
                             height: SkimRestoreHandleGeometry.size.height)
    private static let focusRadius = DWBMetrics.radiusControl
    private static let chevronSize: CGFloat = 13

    private var isHovering = false
    private var isFocused = false
    private var tracking: NSTrackingArea?
    private let focusRingLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        focusRingType = .none
        image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Show Skim controls")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Self.chevronSize, weight: .medium))
        wantsLayer = true
        focusRingLayer.fillColor = NSColor.clear.cgColor
        focusRingLayer.isHidden = true
        layer?.addSublayer(focusRingLayer)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(accessibilityOptionsChanged),
                                               name: DWBAccessibility.didChange,
                                               object: nil)
        refreshAppearance()
    }

    convenience init() {
        self.init(frame: NSRect(origin: .zero, size: Self.size))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override var intrinsicContentSize: NSSize { Self.size }

    override var isHighlighted: Bool {
        didSet { refreshAppearance() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        refreshAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        refreshAppearance()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            isFocused = true
            refreshAppearance()
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            isFocused = false
            refreshAppearance()
        }
        return resigned
    }

    override func layout() {
        super.layout()
        updateFocusRing()
    }

    @objc private func accessibilityOptionsChanged() { refreshAppearance() }

    private func refreshAppearance() {
        // Idle `textPrimary`; hover the skim accent (`accentText`); pressed steps back to `textSecondary`.
        contentTintColor = isHighlighted ? DWBAccessibility.textSecondary
            : (isHovering ? theme.accentText : DWBColor.textPrimary)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusRingLayer.isHidden = !isFocused
        updateFocusRing()
        CATransaction.commit()
        needsDisplay = true
    }

    /// A ring around the hit area: 2 pt `focusRing`, or 3 pt `accentText` under Increase Contrast. It sits
    /// inside the bounds so the flush top edge never clips it.
    private func updateFocusRing() {
        let width = DWBAccessibility.focusWidth
        let rect = bounds.insetBy(dx: width / 2, dy: width / 2)
        focusRingLayer.path = CGPath(roundedRect: rect, cornerWidth: Self.focusRadius,
                                     cornerHeight: Self.focusRadius, transform: nil)
        focusRingLayer.strokeColor = DWBAccessibility.focusRing.cgColor
        focusRingLayer.lineWidth = width
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
    }
}
