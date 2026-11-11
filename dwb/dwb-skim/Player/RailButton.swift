import Cocoa

/// A circular rail control with the design system's single state treatment (D9):
/// idle, hover, pressed, toggled, disabled, and focus, with Increase Contrast variants.
final class RailButton: NSButton {
    enum Style {
        case normal
        case emphasized
        case utility
        case skimActive
        case skimInactive
        case prefixPrimary
        case prefixSecondary
        case bookmark
        case warning
    }

    var railStyle: Style = .normal {
        didSet { updateAppearance() }
    }

    var isToggled: Bool = false {
        didSet { updateAppearance() }
    }

    private var isHovering = false
    private var isFocused = false
    private var tracking: NSTrackingArea?
    private let focusRingLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("programmatic only")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    override var title: String {
        didSet { updateAppearance() }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            isFocused = true
            updateAppearance()
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            isFocused = false
            updateAppearance()
        }
        return resigned
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        updateFocusRingFrame()
    }

    /// Sets the symbol at the rail's optical size for its role (D16, weight medium).
    func configureSymbol(_ symbolName: String,
                         accessibilityLabel: String,
                         help: String,
                         fallbackNames: [String] = []) {
        let pointSize = DWBRailIcon.size(for: symbolName, primary: railStyle == .emphasized)
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        for candidate in [symbolName] + fallbackNames {
            if let image = NSImage(systemSymbolName: candidate,
                                   accessibilityDescription: accessibilityLabel) {
                self.image = image.withSymbolConfiguration(cfg) ?? image
                break
            }
        }
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityHelp(help)
        toolTip = help
    }

    private func configure() {
        isBordered = false
        bezelStyle = .regularSquare
        imageScaling = .scaleProportionallyDown
        focusRingType = .none
        wantsLayer = true
        layer?.borderWidth = 1

        focusRingLayer.isHidden = true
        focusRingLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(focusRingLayer)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(accessibilityOptionsChanged),
                                               name: DWBAccessibility.didChange,
                                               object: nil)
        updateAppearance()
    }

    @objc private func accessibilityOptionsChanged() { updateAppearance() }

    private var glyphColor: NSColor {
        switch railStyle {
        case .normal, .emphasized, .utility:
            return isToggled ? theme.accentText : DWBColor.textPrimary
        case .skimActive, .bookmark:
            return theme.accentText
        case .skimInactive:
            return DWBAccessibility.textSecondary
        case .prefixPrimary:
            return theme.markerPrimary
        case .prefixSecondary:
            return theme.markerSecondary
        case .warning:
            return DWBColor.cautionText
        }
    }

    private func updateAppearance() {
        alphaValue = isEnabled ? 1.0 : DWBMetrics.disabledAlpha

        let interactive = isEnabled
        let pressed = interactive && isHighlighted
        let hovered = interactive && isHovering
        let hasRestFill = isToggled || railStyle == .emphasized

        var fill = NSColor.clear
        if isToggled {
            fill = theme.accentTintStrong
        } else if railStyle == .emphasized {
            fill = DWBColor.overlaySelected
        }
        if pressed || (hovered && hasRestFill) {
            fill = DWBColor.overlayPressed
        } else if hovered {
            fill = DWBColor.overlayHover
        }

        let ring: NSColor
        if isToggled {
            ring = theme.accentFill
        } else if DWBAccessibility.increaseContrast {
            ring = DWBColor.borderStrong
        } else {
            ring = .clear
        }

        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = ring.cgColor

        let tint = glyphColor
        contentTintColor = tint
        applyTitleTint(tint)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusRingLayer.isHidden = !(isFocused && isEnabled)
        focusRingLayer.borderColor = DWBAccessibility.focusRing.cgColor
        focusRingLayer.borderWidth = DWBAccessibility.focusWidth
        updateFocusRingFrame()
        CATransaction.commit()
    }

    /// A ring of the focus width, offset 2 pt outside the circle.
    private func updateFocusRingFrame() {
        let width = DWBAccessibility.focusWidth
        let outset = 2 + width
        focusRingLayer.frame = bounds.insetBy(dx: -outset, dy: -outset)
        focusRingLayer.cornerRadius = min(bounds.width, bounds.height) / 2 + outset
    }

    private func applyTitleTint(_ tint: NSColor) {
        guard image == nil else { return }
        let currentTitle = title
        guard !currentTitle.isEmpty else {
            attributedTitle = NSAttributedString(string: "")
            return
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: tint
        ]
        attributedTitle = NSAttributedString(string: currentTitle, attributes: attributes)
    }
}
