import Cocoa

// The active queue footer (design system 10.5): exactly two rows at every width.
//
//   Row 1, actions:  Remove · primary prefix (N) · secondary prefix (M) · Undo — four equal sections.
//   Row 2, status:   Rescan · total · Clear queue — 100 / flexible / 110 (compact 34 / flexible / 34).
//
// Each section is the complete button and hit target. Hover and pressed are neutral `textPrimary` washes over
// the whole section; nothing moves, scales or reflows. Frames come from `QueueFooterLayout`.

// MARK: - Footer

final class QueueFooterView: NSView {

    var onRemove: (() -> Void)?
    var onPrefix: ((QueueMarkerChip.Kind) -> Void)?
    var onUndo: (() -> Void)?
    var onRescan: (() -> Void)?
    var onClearQueue: (() -> Void)?

    private let removeCell = QueueFooterCellView()
    private let primaryCell = QueueFooterCellView()
    private let secondaryCell = QueueFooterCellView()
    private let undoCell = QueueFooterCellView()
    private let rescanCell = QueueFooterCellView()
    private let clearCell = QueueFooterCellView()
    private let totalLabel = DWBLabel("", size: 10.5, weight: .medium, tone: .secondary, tabularDigits: true)

    private let topRule = DWBRuleView(kind: .gridLine)
    private let actionRule = DWBRuleView(kind: .gridLine)
    private let actionDividers = (0..<3).map { _ in QueueDividerView() }
    private let totalDividers = (0..<2).map { _ in QueueDividerView() }

    private(set) var layoutModel = QueueFooterLayout.make(width: 0)

    private var durationText = MediaFileSupport.formatClockDuration(0)
    private var itemCount = 0
    private var visibleCount = 0
    private var isFiltered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = DWBColor.canvas.cgColor

        removeCell.content = .symbol(QueueRemovalPresentation.buttonSymbolName)
        removeCell.toolTip = QueueRemovalPresentation.buttonToolTip
        removeCell.setAccessibilityLabel(QueueRemovalPresentation.buttonAccessibilityLabel)
        removeCell.target = self
        removeCell.action = #selector(removeTapped)

        primaryCell.content = .marker(kind: .primary, label: QueueMarkerChip.blankLabel)
        primaryCell.target = self
        primaryCell.action = #selector(primaryTapped)

        secondaryCell.content = .marker(kind: .secondary, label: QueueMarkerChip.blankLabel)
        secondaryCell.target = self
        secondaryCell.action = #selector(secondaryTapped)

        undoCell.content = .symbol("arrow.uturn.backward")
        undoCell.toolTip = "Undo the last prefix change (⌘Z)"
        undoCell.setAccessibilityLabel("Undo last prefix change")
        undoCell.target = self
        undoCell.action = #selector(undoTapped)

        rescanCell.content = .utility(symbol: "arrow.clockwise", title: "Rescan")
        rescanCell.setAccessibilityLabel("Rescan Folder")
        rescanCell.target = self
        rescanCell.action = #selector(rescanTapped)
        setRescanSource("Individual files")

        clearCell.content = .utility(symbol: "trash", title: "Clear queue")
        clearCell.toolTip = "Clear Queue"
        clearCell.setAccessibilityLabel("Clear Queue")
        clearCell.target = self
        clearCell.action = #selector(clearTapped)

        totalLabel.alignment = .center
        totalLabel.lineBreakMode = .byClipping
        totalLabel.setAccessibilityRole(.staticText)

        for view in [topRule, actionRule] as [NSView] { addSubview(view) }
        for view in [removeCell, primaryCell, secondaryCell, undoCell, rescanCell, clearCell] as [NSView] { addSubview(view) }
        for view in actionDividers + totalDividers { addSubview(view) }
        addSubview(totalLabel)
        updateTotalText()
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    // MARK: State

    /// - Parameters:
    ///   - chips: the marker chips from `QueueMarkerChip.chips`; a missing secondary leaves its grid position empty.
    ///   - canRemove: something is targeted (the selection, or the visible current item).
    func update(chips: [QueueMarkerChip], canRemove: Bool, canUndo: Bool, hasItems: Bool) {
        for (cell, kind) in [(primaryCell, QueueMarkerChip.Kind.primary), (secondaryCell, .secondary)] {
            guard let chip = chips.first(where: { $0.kind == kind }) else {
                // Suppressed (the secondary repeats the primary): the position stays, with no action.
                cell.isHidden = true
                cell.isEnabled = false
                continue
            }
            cell.isHidden = false
            cell.content = .marker(kind: kind, label: chip.label)
            cell.markState = chip.markState
            cell.toolTip = chip.tooltip
            cell.setAccessibilityLabel(chip.accessibilityLabel)
            cell.setAccessibilityValue(chip.accessibilityValue)
            cell.isEnabled = chip.isEnabled
        }
        removeCell.isEnabled = hasItems && canRemove
        undoCell.isEnabled = canUndo
        rescanCell.isEnabled = hasItems
        clearCell.isEnabled = hasItems
        needsLayout = true
    }

    /// The window's whole-queue duration text, and the counts for the status row's total.
    func setTotal(durationText: String, itemCount: Int, visibleCount: Int, isFiltered: Bool) {
        self.durationText = durationText
        self.itemCount = itemCount
        self.visibleCount = visibleCount
        self.isFiltered = isFiltered
        updateTotalText()
    }

    /// The retired source strip's information, kept on Rescan: its full path, or "Individual files".
    func setRescanSource(_ display: String) {
        let help = "Original source: \(display)"
        rescanCell.toolTip = "Rescan Folder — refresh the queue from current folder contents on disk\n\(help)"
        rescanCell.setAccessibilityHelp(help)
    }

    private func updateTotalText() {
        let count = QueueTotalPresentation.countText(itemCount: itemCount, visibleCount: visibleCount, isFiltered: isFiltered)
        let full = QueueTotalPresentation.fullText(durationText: durationText, countText: count)
        totalLabel.stringValue = QueueTotalPresentation.fit(durationText: durationText,
                                                            countText: count,
                                                            availableWidth: layoutModel.totalFitWidth) {
            QueueFonts.width(of: $0, font: QueueFonts.total)
        }
        totalLabel.toolTip = full
        totalLabel.setAccessibilityLabel(full)
        totalLabel.setAccessibilityValue(full)
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let model = QueueFooterLayout.make(width: bounds.width)
        layoutModel = model

        topRule.frame = model.topRule
        actionRule.frame = model.actionRule
        let cells = [removeCell, primaryCell, secondaryCell, undoCell]
        for (cell, frame) in zip(cells, model.actionCells) { cell.frame = frame }
        for (divider, frame) in zip(actionDividers, model.actionDividers) { divider.frame = frame }
        rescanCell.frame = model.rescanCell
        clearCell.frame = model.clearCell
        for (divider, frame) in zip(totalDividers, model.totalDividers) { divider.frame = frame }

        for cell in [primaryCell, secondaryCell] { cell.isCompact = model.isCompact }
        for cell in [rescanCell, clearCell] { cell.showsUtilityLabel = !model.isCompact }

        let lineHeight = ceil(QueueFonts.total.ascender - QueueFonts.total.descender + QueueFonts.total.leading)
        totalLabel.frame = NSRect(x: model.totalCell.minX + DWBMetrics.queueTotalFitInset / 2,
                                  y: floor((model.totalCell.height - lineHeight) / 2),
                                  width: max(0, model.totalCell.width - DWBMetrics.queueTotalFitInset),
                                  height: lineHeight)
        updateTotalText()
    }

    // MARK: Actions

    @objc private func removeTapped() { onRemove?() }
    @objc private func primaryTapped() { onPrefix?(.primary) }
    @objc private func secondaryTapped() { onPrefix?(.secondary) }
    @objc private func undoTapped() { onUndo?() }
    @objc private func rescanTapped() { onRescan?() }
    @objc private func clearTapped() { onClearQueue?() }

    /// The right edge of the total's cell in this view's coordinates (queue geometry diagnostics).
    var totalRightEdge: CGFloat { layoutModel.totalCell.maxX }
}

// MARK: - Divider

/// A 0.5 pt `border` divider (strong under Increase Contrast). It takes no clicks.
final class QueueDividerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyColor()
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func applyColor() { layer?.backgroundColor = DWBAccessibility.border.cgColor }

    @objc private func accessibilityDidChange() { applyColor() }
}

// MARK: - Cell

/// One footer section. It is the whole button: the hover and pressed washes fill it edge to edge, and its icon or
/// label is centered in it. A marker section may carry a state mark (a 4 pt dot for applied, a 4 pt ring for
/// mixed) in its top-right corner, in the label's color; there is no colored fill, pill or underline.
///
/// Disabled is the whole control at 0.4 alpha, applied once through `alphaValue`; the label keeps its own color.
/// A mouse click never takes focus, so the 2 pt focus ring (3 pt `accentText` under Increase Contrast) shows only
/// for keyboard focus.
final class QueueFooterCellView: NSView {

    enum Content: Equatable {
        case symbol(String)
        case marker(kind: QueueMarkerChip.Kind, label: String)
        case utility(symbol: String, title: String)
    }

    var content: Content = .symbol("questionmark") {
        didSet { if content != oldValue { needsDisplay = true } }
    }
    var markState: QueueMarkerChip.MarkState = .none {
        didSet { if markState != oldValue { needsDisplay = true } }
    }
    var isCompact = true {
        didSet { if isCompact != oldValue { needsDisplay = true } }
    }
    /// Rescan and Clear queue hide their labels in the compact footer.
    var showsUtilityLabel = false {
        didSet { if showsUtilityLabel != oldValue { needsDisplay = true } }
    }

    private var isHovering = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }
    private var isKeyboardFocused = false { didSet { needsDisplay = true } }
    private var trackingAreaReference: NSTrackingArea?

    override var isFlipped: Bool { true }

    /// The action and its target are stored here: a bare view (unlike an `NSControl` with no cell) keeps them.
    weak var target: AnyObject?
    var action: Selector?

    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            alphaValue = isEnabled ? 1 : DWBMetrics.queueFooterDisabledAlpha
            if !isEnabled {
                isHovering = false
                isPressed = false
            }
            needsDisplay = true
        }
    }

    @discardableResult
    private func sendAction() -> Bool {
        guard let action else { return false }
        return NSApp.sendAction(action, to: target, from: self)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    @objc private func accessibilityDidChange() { needsDisplay = true }

    // MARK: Drawing

    private var markerColor: NSColor? {
        guard case .marker(let kind, _) = content else { return nil }
        return kind == .primary ? theme.markerPrimary : theme.markerSecondary
    }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled, isPressed || isHovering {
            let alpha = isPressed ? DWBMetrics.queueCellPressedAlpha : DWBMetrics.queueCellHoverAlpha
            DWBColor.textPrimary.withAlphaComponent(alpha).setFill()
            bounds.fill()
        }

        switch content {
        case .symbol(let name):
            drawGlyph(name, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        case .marker(_, let label):
            drawMarkerLabel(label)
            drawStateMark()
        case .utility(let symbol, let title):
            drawUtility(symbol: symbol, title: title)
        }

        if isKeyboardFocused {
            let ring = DWBAccessibility.focusWidth
            let path = NSBezierPath(rect: bounds.insetBy(dx: 3 + ring / 2, dy: 3 + ring / 2))
            path.lineWidth = ring
            DWBAccessibility.focusRing.setStroke()
            path.stroke()
        }
    }

    private func drawGlyph(_ name: String, centeredAt center: NSPoint) {
        guard let image = NSImage.dwbSymbol(name, pointSize: DWBMetrics.queueCellIcon, weight: .regular,
                                            color: DWBColor.textPrimary) else { return }
        let size = image.size
        image.draw(in: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                              width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func drawUtility(symbol: String, title: String) {
        guard let image = NSImage.dwbSymbol(symbol, pointSize: DWBMetrics.queueCellIcon, weight: .regular,
                                            color: DWBColor.textPrimary) else { return }
        let gap: CGFloat = 6
        let font = QueueFonts.utility
        let textWidth = showsUtilityLabel ? QueueFonts.width(of: title, font: font) : 0
        let total = image.size.width + (showsUtilityLabel ? gap + textWidth : 0)
        var x = floor((bounds.width - total) / 2)
        image.draw(in: NSRect(x: x, y: floor((bounds.height - image.size.height) / 2),
                              width: image.size.width, height: image.size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        guard showsUtilityLabel else { return }
        x += image.size.width + gap
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        (title as NSString).draw(at: NSPoint(x: x, y: floor((bounds.height - lineHeight) / 2)),
                                 withAttributes: [.font: font, .foregroundColor: DWBColor.textPrimary])
    }

    private func drawMarkerLabel(_ label: String) {
        guard let color = markerColor else { return }
        let limit = QueueMarkerCellGeometry.labelWidthLimit(sectionWidth: bounds.width, isCompact: isCompact)
        let shown = QueuePrefixLabelFitting.fit(label, maxWidth: limit)
        let font = QueueFonts.marker
        let width = QueueFonts.width(of: shown, font: font)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let frame = QueueMarkerCellGeometry.labelFrame(sectionSize: bounds.size, labelWidth: width, lineHeight: lineHeight)
        (shown as NSString).draw(at: frame.origin, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func drawStateMark() {
        guard let color = markerColor, markState != .none else { return }
        let frame = QueueMarkerCellGeometry.markFrame(sectionWidth: bounds.width)
        switch markState {
        case .applied:
            color.setFill()
            NSBezierPath(ovalIn: frame).fill()
        case .mixed:
            // 4 pt including its 1 pt stroke, so the ring stays inside the same box as the dot.
            let ring = NSBezierPath(ovalIn: frame.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1
            color.setStroke()
            ring.stroke()
        case .none:
            break
        }
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

    override func mouseEntered(with event: NSEvent) { if isEnabled { isHovering = true } }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if inside { sendAction() }
    }

    // MARK: Keyboard and accessibility

    /// Keyboard focus only. A mouse press never makes a section first responder: that would draw the focus ring on
    /// an ordinary click and take keyboard focus away from the list.
    override var acceptsFirstResponder: Bool {
        isEnabled && !isHidden && !QueuePointerEvent.isPointerDownInFlight
    }

    override func becomeFirstResponder() -> Bool {
        isKeyboardFocused = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isKeyboardFocused = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        // Space and Return press the focused section.
        if event.keyCode == 49 || event.keyCode == 36 {
            if isEnabled { sendAction() }
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        return sendAction()
    }

    override func isAccessibilityEnabled() -> Bool { isEnabled }
}

/// Whether the event being handled is a mouse press, so views that take keyboard focus can refuse it.
enum QueuePointerEvent {
    static var isPointerDownInFlight: Bool {
        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: return true
        default: return false
        }
    }
}
