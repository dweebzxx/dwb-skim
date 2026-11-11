import AppKit

// Custom-drawn controls for the dwb design system (sections 5, 9.3, 9.5).
//
// Every control resolves its colors at draw time from `DWBColor`, `theme` and
// `DWBAccessibility`, and redraws when `DWBAccessibility.didChange` fires, so
// Increase Contrast applies live. None of them animates.

extension DWBAccessibility {
    /// Registers `observer` to receive `selector` whenever Increase Contrast or
    /// Reduce Motion changes.
    static func observe(_ observer: Any, selector: Selector) {
        NotificationCenter.default.addObserver(observer, selector: selector, name: didChange, object: nil)
    }
}

extension NSImage {
    /// An SF Symbol drawn in one solid color. The symbol's own cut-outs (the "!" of a filled
    /// warning triangle) stay transparent, which a palette color would paint over.
    static func dwbSymbol(_ name: String,
                          pointSize: CGFloat,
                          weight: NSFont.Weight = .medium,
                          color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        let size = base.size
        let tinted = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}

extension NSColor {
    /// The color with its alpha multiplied by `factor` (used for disabled controls).
    func scaledAlpha(_ factor: CGFloat) -> NSColor {
        factor >= 1 ? self : withAlphaComponent(alphaComponent * factor)
    }
}

// MARK: - Label

/// A static text label whose color is a design-system role, so it follows Increase Contrast.
final class DWBLabel: NSTextField {
    enum Tone: Equatable {
        case primary, secondary, tertiary, disabled, accent, error, caution, onFill
    }

    var tone: Tone {
        didSet { applyTone() }
    }

    init(_ text: String = "",
         size: CGFloat = 13,
         weight: NSFont.Weight = .regular,
         tone: Tone = .primary,
         monospaced: Bool = false,
         tabularDigits: Bool = false) {
        self.tone = tone
        super.init(frame: .zero)
        stringValue = text
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        lineBreakMode = .byTruncatingTail
        if monospaced {
            font = .monospacedSystemFont(ofSize: size, weight: weight)
        } else if tabularDigits {
            font = .monospacedDigitSystemFont(ofSize: size, weight: weight)
        } else {
            font = .systemFont(ofSize: size, weight: weight)
        }
        applyTone()
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    /// The color for a tone under the current Increase Contrast setting.
    static func color(for tone: Tone) -> NSColor {
        switch tone {
        case .primary: return DWBColor.textPrimary
        case .secondary: return DWBAccessibility.textSecondary
        case .tertiary: return DWBAccessibility.textTertiary
        case .disabled: return DWBColor.textDisabled
        case .accent: return theme.accentText
        case .error: return DWBColor.errorText
        case .caution: return DWBColor.cautionText
        case .onFill: return DWBColor.textOnFill
        }
    }

    private func applyTone() {
        textColor = Self.color(for: tone)
    }

    @objc private func accessibilityDidChange() {
        applyTone()
    }
}

// MARK: - Rule

/// A 1 pt line in `border` (which strengthens under Increase Contrast) or `gridLine`.
final class DWBRuleView: NSView {
    enum Kind {
        case border
        case gridLine
    }

    private let kind: Kind
    private let isVertical: Bool

    init(kind: Kind = .border, vertical: Bool = false) {
        self.kind = kind
        self.isVertical = vertical
        super.init(frame: .zero)
        wantsLayer = true
        applyColor()
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override var intrinsicContentSize: NSSize {
        isVertical ? NSSize(width: 1, height: NSView.noIntrinsicMetric)
                   : NSSize(width: NSView.noIntrinsicMetric, height: 1)
    }

    private func applyColor() {
        layer?.backgroundColor = (kind == .border ? DWBAccessibility.border : DWBColor.gridLine).cgColor
    }

    @objc private func accessibilityDidChange() {
        applyColor()
    }
}

// MARK: - Button

/// A custom-drawn push button, pill, or link (design system `Button`, queue footer pills,
/// About link pills). Radius, height and colors come from the style; focus is a 2 pt
/// ring (3 pt `accentText` under Increase Contrast) drawn inside the bounds.
final class DWBButton: NSButton {
    enum Style {
        /// Push button: `overlaySelected` fill, `border` edge, `textPrimary` label.
        case neutral
        /// Neutral shape with an `errorText` label (Clear All Bookmarks).
        case neutralDestructive
        /// The one primary action: solid `accentSolid`, `textOnFill` label.
        case primary
        /// A destructive confirmation: solid `errorText`, `textOnFill` label.
        case destructive
        /// No fill or edge, `accentText` label.
        case plain
        /// Queue footer pill (26 pt, radius 12).
        case pill
        /// Queue footer pill with an `errorText` label.
        case pillDestructive
        /// Pill with a `borderStrong` outline and `accentText` label (empty-state action).
        case pillOutline
        /// About link pill: 24 pt, radius 12, trailing `arrow.up.right.square`.
        case link
        /// Borderless `errorText` button with a leading glyph (queue footer Remove).
        case inlineDestructive
    }

    enum Size {
        case regular
        case small
    }

    private let style: Style
    private let size: Size
    private let leadingSymbol: String?
    private let trailingSymbol: String?
    private var isHovering = false
    private var trackingAreaReference: NSTrackingArea?

    init(title: String,
         style: Style = .neutral,
         size: Size = .regular,
         leadingSymbol: String? = nil,
         trailingSymbol: String? = nil,
         target: AnyObject? = nil,
         action: Selector? = nil) {
        self.style = style
        self.size = size
        self.leadingSymbol = leadingSymbol ?? (style == .inlineDestructive ? "minus.circle" : nil)
        self.trailingSymbol = trailingSymbol ?? (style == .link ? "arrow.up.right.square" : nil)
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        setAccessibilityLabel(title)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    // MARK: Metrics

    /// The control height for this style.
    static func height(for style: Style, size: Size) -> CGFloat {
        switch style {
        case .pill, .pillDestructive, .pillOutline, .inlineDestructive: return 26
        case .link: return 24
        case .neutral, .neutralDestructive, .primary, .destructive, .plain:
            return size == .regular ? 28 : 24
        }
    }

    private var controlHeight: CGFloat { Self.height(for: style, size: size) }

    private var cornerRadius: CGFloat {
        switch style {
        case .pill, .pillDestructive, .pillOutline, .link: return DWBMetrics.radiusPill
        default: return DWBMetrics.radiusControl
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .pill, .pillDestructive, .pillOutline: return 12
        case .link: return 10
        case .inlineDestructive: return 8
        default: return size == .regular ? 14 : 10
        }
    }

    private var labelFont: NSFont {
        switch style {
        case .pill, .pillDestructive, .inlineDestructive: return .systemFont(ofSize: 11.5, weight: .regular)
        case .pillOutline: return .systemFont(ofSize: 12, weight: .semibold)
        case .link: return .systemFont(ofSize: 11.5, weight: .semibold)
        case .primary, .destructive:
            return .systemFont(ofSize: size == .regular ? 13 : 11, weight: .semibold)
        default:
            return .systemFont(ofSize: size == .regular ? 13 : 11, weight: .medium)
        }
    }

    private var symbolPointSize: CGFloat {
        switch style {
        case .link: return 10
        case .inlineDestructive: return 13
        default: return size == .regular ? 13 : 11
        }
    }

    private let symbolGap: CGFloat = 6

    // MARK: Appearance

    private struct Look {
        var fill: NSColor?
        var border: NSColor?
        var label: NSColor
    }

    private func look() -> Look {
        let pressed = isHighlighted
        let hover = isHovering || pressed
        var look: Look
        switch style {
        case .neutral, .neutralDestructive:
            look = Look(fill: hover ? DWBColor.overlayPressed : DWBColor.overlaySelected,
                        border: DWBAccessibility.border,
                        label: style == .neutral ? DWBColor.textPrimary : DWBColor.errorText)
        case .primary:
            let fill = hover ? theme.accentSolid.blended(withFraction: 0.08, of: .white) ?? theme.accentSolid
                             : theme.accentSolid
            look = Look(fill: fill, border: theme.accentSolid, label: DWBColor.textOnFill)
        case .destructive:
            let fill = hover ? DWBColor.errorText.blended(withFraction: 0.08, of: .white) ?? DWBColor.errorText
                             : DWBColor.errorText
            look = Look(fill: fill, border: DWBColor.errorText, label: DWBColor.textOnFill)
        case .plain:
            look = Look(fill: hover ? DWBColor.overlayHover : nil, border: nil, label: theme.accentText)
        case .pill, .pillDestructive:
            look = Look(fill: DWBColor.surfaceElevated,
                        border: DWBAccessibility.border,
                        label: style == .pill ? DWBColor.textPrimary : DWBColor.errorText)
        case .pillOutline:
            look = Look(fill: hover ? DWBColor.overlayHover : nil,
                        border: DWBColor.borderStrong,
                        label: theme.accentText)
        case .link:
            look = Look(fill: hover ? DWBColor.overlayPressed : DWBColor.overlaySelected,
                        border: DWBAccessibility.border,
                        label: theme.accentText)
        case .inlineDestructive:
            look = Look(fill: hover ? DWBColor.overlayHover : nil, border: nil, label: DWBColor.errorText)
        }
        if !isEnabled {
            let alpha = DWBMetrics.disabledAlpha
            look.fill = look.fill?.scaledAlpha(alpha)
            look.border = look.border?.scaledAlpha(alpha)
            look.label = look.label.scaledAlpha(alpha)
        }
        return look
    }

    private func symbolImage(_ name: String, color: NSColor) -> NSImage? {
        NSImage.dwbSymbol(name, pointSize: symbolPointSize, weight: .medium, color: color)
    }

    private func labelAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: labelFont, .foregroundColor: color]
    }

    // MARK: Sizing

    override var intrinsicContentSize: NSSize {
        let reference = NSColor.white
        var width = horizontalPadding * 2
        var parts = 0
        if let leadingSymbol, let image = symbolImage(leadingSymbol, color: reference) {
            width += ceil(image.size.width)
            parts += 1
        }
        if !title.isEmpty {
            width += ceil((title as NSString).size(withAttributes: labelAttributes(color: reference)).width)
            parts += 1
        }
        if let trailingSymbol, let image = symbolImage(trailingSymbol, color: reference) {
            width += ceil(image.size.width)
            parts += 1
        }
        if parts > 1 { width += symbolGap * CGFloat(parts - 1) }
        return NSSize(width: ceil(width), height: controlHeight)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let look = look()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        if let fill = look.fill {
            fill.setFill()
            path.fill()
        }
        if style == .pill || style == .pillDestructive, isEnabled, isHovering || isHighlighted {
            // `overlayHover` sits on top of the pill's own `surfaceElevated` fill.
            DWBColor.overlayHover.setFill()
            path.fill()
        }
        if let border = look.border {
            border.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        var parts: [(image: NSImage?, text: NSAttributedString?, width: CGFloat, height: CGFloat)] = []
        if let leadingSymbol, let image = symbolImage(leadingSymbol, color: look.label) {
            parts.append((image, nil, ceil(image.size.width), image.size.height))
        }
        if !title.isEmpty {
            let text = NSAttributedString(string: title, attributes: labelAttributes(color: look.label))
            let measured = text.size()
            parts.append((nil, text, ceil(measured.width), ceil(measured.height)))
        }
        if let trailingSymbol, let image = symbolImage(trailingSymbol, color: look.label) {
            parts.append((image, nil, ceil(image.size.width), image.size.height))
        }
        let total = parts.reduce(CGFloat(0)) { $0 + $1.width } + symbolGap * CGFloat(max(0, parts.count - 1))
        var x = floor((bounds.width - total) / 2)
        for part in parts {
            let y = floor((bounds.height - part.height) / 2)
            if let image = part.image {
                image.draw(in: NSRect(x: x, y: y, width: part.width, height: part.height))
            } else if let text = part.text {
                text.draw(at: NSPoint(x: x, y: y))
            }
            x += part.width + symbolGap
        }

        if isShowingFocus {
            let width = DWBAccessibility.focusWidth
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2),
                                    xRadius: cornerRadius, yRadius: cornerRadius)
            ring.lineWidth = width
            DWBAccessibility.focusRing.setStroke()
            ring.stroke()
        }
    }

    private var isShowingFocus: Bool {
        guard let window, window.isKeyWindow else { return false }
        return window.firstResponder === self
    }

    // MARK: State

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
    }

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

// MARK: - Pop-up button

/// A pop-up drawn as a 24 pt, radius 6 `surfaceElevated` control with a 1 pt `border`
/// (design system `PopUpButton`). The menu itself stays the standard AppKit menu.
final class DWBPopUpButton: NSPopUpButton {
    init() {
        super.init(frame: .zero, pullsDown: false)
        cell = DWBPopUpButtonCell(textCell: "", pullsDown: false)
        isBordered = false
        focusRingType = .none
        font = .systemFont(ofSize: 13)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        var longest: CGFloat = 0
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
        for item in itemArray {
            longest = max(longest, ceil((item.title as NSString).size(withAttributes: attributes).width))
        }
        return NSSize(width: longest + DWBPopUpButtonCell.leadingPadding + DWBPopUpButtonCell.trailingPadding,
                      height: 24)
    }

    @objc private func accessibilityDidChange() {
        needsDisplay = true
    }
}

private final class DWBPopUpButtonCell: NSPopUpButtonCell {
    static let leadingPadding: CGFloat = 10
    static let trailingPadding: CGFloat = 26

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let enabled = isEnabled
        let alpha = enabled ? 1 : DWBMetrics.disabledAlpha
        let path = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusControl, yRadius: DWBMetrics.radiusControl)
        DWBColor.surfaceElevated.scaledAlpha(alpha).setFill()
        path.fill()
        DWBAccessibility.border.scaledAlpha(alpha).setStroke()
        path.lineWidth = 1
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: DWBColor.textPrimary.scaledAlpha(alpha),
            .paragraphStyle: paragraph,
        ]
        let title = (selectedItem?.title ?? "") as NSString
        let height = ceil(title.size(withAttributes: attributes).height)
        title.draw(in: NSRect(x: cellFrame.minX + Self.leadingPadding,
                              y: cellFrame.minY + floor((cellFrame.height - height) / 2),
                              width: max(0, cellFrame.width - Self.leadingPadding - Self.trailingPadding + 8),
                              height: height),
                   withAttributes: attributes)

        if let chevron = NSImage.dwbSymbol("chevron.up.chevron.down", pointSize: 11, weight: .medium,
                                           color: DWBAccessibility.textSecondary.scaledAlpha(alpha)) {
            let size = chevron.size
            chevron.draw(in: NSRect(x: cellFrame.maxX - 8 - size.width,
                                    y: cellFrame.minY + floor((cellFrame.height - size.height) / 2),
                                    width: size.width,
                                    height: size.height))
        }

        if let window = controlView.window, window.isKeyWindow, window.firstResponder === controlView {
            let width = DWBAccessibility.focusWidth
            let ring = NSBezierPath(roundedRect: cellFrame.insetBy(dx: width / 2, dy: width / 2),
                                    xRadius: DWBMetrics.radiusControl, yRadius: DWBMetrics.radiusControl)
            ring.lineWidth = width
            DWBAccessibility.focusRing.setStroke()
            ring.stroke()
        }
    }
}

// MARK: - Segmented control

/// A custom-drawn segmented control (design system `SegmentedControl`): the selected
/// segment is `accentSolid` with a `textOnFill` label. Mirrors the parts of the
/// `NSSegmentedControl` API the app used: `segmentCount`, `setLabel(_:forSegment:)`,
/// `selectedSegment`, target and action.
final class DWBSegmentedControl: NSControl {
    enum Size {
        case regular
        case small
    }

    private var labels: [String] = []
    private let size: Size

    var segmentCount: Int {
        get { labels.count }
        set {
            let count = max(0, newValue)
            if count > labels.count {
                labels.append(contentsOf: Array(repeating: "", count: count - labels.count))
            } else if count < labels.count {
                labels.removeLast(labels.count - count)
            }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    var selectedSegment: Int = -1 {
        didSet { needsDisplay = true; accessibilityElementsCache = nil }
    }

    private var accessibilityElementsCache: [NSAccessibilityElement]?

    init(size: Size = .regular) {
        self.size = size
        super.init(frame: .zero)
        focusRingType = .none
        setAccessibilityRole(.radioGroup)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    func setLabel(_ label: String, forSegment segment: Int) {
        guard labels.indices.contains(segment) else { return }
        labels[segment] = label
        invalidateIntrinsicContentSize()
        accessibilityElementsCache = nil
        needsDisplay = true
    }

    // MARK: Metrics

    private var segmentHeight: CGFloat { size == .regular ? 22 : 20 }
    private var segmentPadding: CGFloat { size == .regular ? 12 : 9 }
    private var fontSize: CGFloat { size == .regular ? 12 : 11 }
    private let inset: CGFloat = 2
    private let gap: CGFloat = 2

    private func segmentFont(selected: Bool) -> NSFont {
        .systemFont(ofSize: fontSize, weight: selected ? .semibold : .regular)
    }

    private func segmentWidths() -> [CGFloat] {
        // Measure the semibold face so selecting a segment never reflows the row.
        let attributes: [NSAttributedString.Key: Any] = [.font: segmentFont(selected: true)]
        return labels.map { label in
            ceil((label as NSString).size(withAttributes: attributes).width) + segmentPadding * 2
        }
    }

    private func segmentRects() -> [NSRect] {
        var x = inset
        return segmentWidths().map { width in
            defer { x += width + gap }
            return NSRect(x: x, y: inset, width: width, height: segmentHeight)
        }
    }

    override var intrinsicContentSize: NSSize {
        let widths = segmentWidths()
        let total = widths.reduce(0, +) + gap * CGFloat(max(0, widths.count - 1)) + inset * 2
        return NSSize(width: ceil(total), height: segmentHeight + inset * 2)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let alpha = isEnabled ? 1 : DWBMetrics.disabledAlpha
        let container = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        DWBColor.surfaceElevated.scaledAlpha(alpha).setFill()
        container.fill()
        DWBAccessibility.border.scaledAlpha(alpha).setStroke()
        container.lineWidth = 1
        container.stroke()

        for (index, rect) in segmentRects().enumerated() {
            let selected = index == selectedSegment
            if selected {
                theme.accentSolid.scaledAlpha(alpha).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: segmentFont(selected: selected),
                .foregroundColor: (selected ? DWBColor.textOnFill : DWBColor.textPrimary).scaledAlpha(alpha),
            ]
            let text = labels[index] as NSString
            let measured = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: rect.minX + floor((rect.width - measured.width) / 2),
                                  y: rect.minY + floor((rect.height - measured.height) / 2)),
                      withAttributes: attributes)
        }

        if let window, window.isKeyWindow, window.firstResponder === self {
            let width = DWBAccessibility.focusWidth
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2), xRadius: 7, yRadius: 7)
            ring.lineWidth = width
            DWBAccessibility.focusRing.setStroke()
            ring.stroke()
        }
    }

    // MARK: Interaction

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let index = segmentRects().firstIndex(where: { $0.insetBy(dx: -gap / 2, dy: -inset).contains(point) }) {
            select(index)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, !labels.isEmpty else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 123: select(max(0, selectedSegment - 1))
        case 124: select(min(labels.count - 1, selectedSegment + 1))
        default: super.keyDown(with: event)
        }
    }

    private func select(_ index: Int) {
        guard labels.indices.contains(index), index != selectedSegment else { return }
        selectedSegment = index
        sendAction(action, to: target)
    }

    @objc private func accessibilityDidChange() {
        needsDisplay = true
    }

    // MARK: Accessibility

    override func accessibilityChildren() -> [Any]? {
        if let cached = accessibilityElementsCache { return cached }
        let rects = segmentRects()
        let elements = labels.enumerated().map { index, label -> NSAccessibilityElement in
            let element = DWBSegmentAccessibilityElement()
            element.setAccessibilityRole(.radioButton)
            element.setAccessibilityLabel(label)
            element.setAccessibilityValue(index == selectedSegment ? 1 : 0)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(rects[index])
            element.onPress = { [weak self] in
                guard let self, self.isEnabled else { return false }
                self.select(index)
                return true
            }
            return element
        }
        accessibilityElementsCache = elements
        return elements
    }
}

private final class DWBSegmentAccessibilityElement: NSAccessibilityElement {
    var onPress: (() -> Bool)?

    override func accessibilityPerformPress() -> Bool {
        onPress?() ?? false
    }
}

// MARK: - Field chrome

/// A text field whose focus changes are observable (it becomes first responder, then
/// hands editing to the field editor, so the chrome watches both ends).
final class DWBInlineTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }
}

/// The chrome of a design-system text or number field: `surfaceSunken` ground,
/// a 1 pt `borderStrong` edge, and a 2 pt focus ring (3 pt `accentText` under Increase
/// Contrast). The wrapped field keeps its native cell, delegate, formatter and editing.
final class DWBFieldChrome: NSView {
    let field: DWBInlineTextField
    private let cornerRadius: CGFloat
    private let fixedWidth: CGFloat?
    private let fieldHeight: CGFloat
    private var isFocused = false
    /// Set by the rename sheet to draw the error edge and ring.
    var isError = false {
        didSet { needsDisplay = true }
    }
    /// The extension token (or any trailing view) the sheet's field row hosts.
    var trailingAccessory: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let trailingAccessory { addSubview(trailingAccessory) }
            needsLayout = true
        }
    }

    init(field: DWBInlineTextField = DWBInlineTextField(),
         width: CGFloat? = nil,
         height: CGFloat = 22,
         cornerRadius: CGFloat = 5,
         monospaced: Bool = false,
         fontSize: CGFloat = 12) {
        self.field = field
        self.fixedWidth = width
        self.fieldHeight = height
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = DWBColor.textPrimary
        field.font = monospaced ? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
                                : .systemFont(ofSize: fontSize)
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.onFocusChange = { [weak self] focused in
            self?.isFocused = focused
            self?.needsDisplay = true
        }
        addSubview(field)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: fixedWidth ?? NSView.noIntrinsicMetric, height: fieldHeight)
    }

    /// The disabled treatment (design system 9.5): the whole field at 0.32 alpha.
    var isDimmed = false {
        didSet {
            alphaValue = isDimmed ? DWBMetrics.disabledAlpha : 1
            field.isEnabled = !isDimmed
        }
    }

    override func layout() {
        super.layout()
        let accessoryWidth = trailingAccessory?.fittingSize.width ?? 0
        if let trailingAccessory {
            // One point in from the edge so the field's own border stays visible.
            trailingAccessory.frame = NSRect(x: bounds.maxX - accessoryWidth - 1, y: 1,
                                             width: accessoryWidth, height: bounds.height - 2)
        }
        let textHeight = ceil(field.intrinsicContentSize.height)
        field.frame = NSRect(x: 7,
                             y: floor((bounds.height - textHeight) / 2),
                             width: max(0, bounds.width - 14 - accessoryWidth - (accessoryWidth > 0 ? 1 : 0)),
                             height: textHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        DWBColor.surfaceSunken.setFill()
        path.fill()
        // The accessory (extension token) paints above the ground, then the edge on top.
        let edge = isError ? DWBColor.errorText : DWBColor.borderStrong
        edge.setStroke()
        path.lineWidth = 1
        path.stroke()
        if isFocused {
            let width = DWBAccessibility.focusWidth
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2),
                                    xRadius: cornerRadius, yRadius: cornerRadius)
            ring.lineWidth = width
            (isError ? DWBColor.errorFill : DWBAccessibility.focusRing).setStroke()
            ring.stroke()
        }
    }

    override var isOpaque: Bool { false }

    @objc private func accessibilityDidChange() {
        field.textColor = DWBColor.textPrimary
        needsDisplay = true
    }
}

// MARK: - Pill chrome

/// A filled, bordered rounded rectangle (`surfaceElevated`, 1 pt `border`) that hosts a
/// field: the search and filter pills.
final class DWBPillChromeView: NSView {
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = DWBMetrics.radiusPill) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: cornerRadius, yRadius: cornerRadius)
        DWBColor.surfaceElevated.setFill()
        path.fill()
        DWBAccessibility.border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    @objc private func accessibilityDidChange() {
        needsDisplay = true
    }
}

// MARK: - Search field cell

/// A search field cell without the system magnifier, so a pill can draw its own glyph
/// and the text starts flush at the field's leading edge. The clear button stays.
final class DWBSearchFieldCell: NSSearchFieldCell {
    override init(textCell string: String) {
        super.init(textCell: string)
        isEditable = true
        isScrollable = true
        usesSingleLineMode = true
        lineBreakMode = .byClipping
    }

    required init(coder: NSCoder) { fatalError("programmatic only") }

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect { .zero }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        let cancel = cancelButtonRect(forBounds: rect)
        let right = cancel.isEmpty ? rect.maxX : cancel.minX - 4
        let font = self.font ?? NSFont.systemFont(ofSize: 11)
        let height = ceil(font.ascender - font.descender + font.leading)
        return NSRect(x: rect.minX,
                      y: rect.minY + floor((rect.height - height) / 2),
                      width: max(0, right - rect.minX),
                      height: height)
    }
}
