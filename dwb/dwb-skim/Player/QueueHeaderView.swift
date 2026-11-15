import Cocoa

// The active queue header (design system 10.2): one 52 pt row at every width with the search field,
// the sort button, the bookmark filter and close. No title. Frames come from `QueueHeaderLayout`.
// All colors resolve at draw time, so Increase Contrast applies live.

// MARK: - Header

final class QueueHeaderView: NSView {

    let searchBox = QueueSearchBoxView()
    private let sortButton = QueueHeaderButton()
    private let filterButton = QueueHeaderButton()
    private let closeButton = QueueHeaderButton()
    private let rule = DWBRuleView(kind: .gridLine)

    var searchField: QueueSearchTextField { searchBox.field }

    var onSortModeChosen: ((QueueSortMode) -> Void)?
    var onBookmarkFilterToggled: (() -> Void)?
    var onCloseRequested: (() -> Void)?
    /// The clear button removes only the query; the owner clears the field and refilters.
    var onClearSearch: (() -> Void)? {
        didSet { searchBox.onClear = onClearSearch }
    }

    private(set) var layoutModel = QueueHeaderLayout.make(width: 0, hasSearchText: false)
    private(set) var sortMode: QueueSortMode = .manual
    private(set) var isBookmarkFilterOn = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = DWBColor.canvas.cgColor

        addSubview(searchBox)

        sortButton.target = self
        sortButton.action = #selector(sortTapped)
        sortButton.setAccessibilityLabel("Queue sort order")
        addSubview(sortButton)

        filterButton.target = self
        filterButton.action = #selector(filterTapped)
        filterButton.setAccessibilityLabel("Bookmark filter")
        addSubview(filterButton)

        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.content = .symbol(name: "xmark", pointSize: 15)
        closeButton.toolTip = "Close Queue"
        closeButton.setAccessibilityLabel("Close Queue")
        addSubview(closeButton)

        addSubview(rule)
        configure(sortMode: .manual, bookmarkFilterOn: false)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
        applyAccessibilityColors()
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    // MARK: State

    func configure(sortMode: QueueSortMode, bookmarkFilterOn: Bool) {
        self.sortMode = sortMode
        isBookmarkFilterOn = bookmarkFilterOn

        sortButton.toolTip = "Sort: \(sortMode.title)"
        sortButton.setAccessibilityValue(sortMode.title)
        sortButton.setAccessibilityHelp("Sort: \(sortMode.title). Choose a different queue order.")

        filterButton.isOn = bookmarkFilterOn
        filterButton.content = .symbol(name: bookmarkFilterOn ? "bookmark.fill" : "bookmark", pointSize: 15)
        filterButton.toolTip = bookmarkFilterOn ? "Showing bookmarked queue files" : "Show bookmarked queue files"
        filterButton.setAccessibilityValue(bookmarkFilterOn ? "on" : "off")
        needsLayout = true
        needsDisplay = true
    }

    /// Shows or hides the clear button after the field's text changed.
    func searchTextDidChange() {
        needsLayout = true
    }

    private func applyAccessibilityColors() {
        let placeholder = NSAttributedString(string: "Search queue", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: DWBAccessibility.textTertiary,
        ])
        searchField.placeholderAttributedString = placeholder
        needsDisplay = true
    }

    @objc private func accessibilityDidChange() {
        applyAccessibilityColors()
    }

    // MARK: Layout

    private var sortLabelWidth: CGFloat {
        QueueFonts.width(of: sortMode.title, font: QueueHeaderButton.sortLabelFont)
    }

    override func layout() {
        super.layout()
        let model = QueueHeaderLayout.make(width: bounds.width,
                                           hasSearchText: !searchField.stringValue.isEmpty,
                                           sortLabelWidth: sortLabelWidth)
        layoutModel = model
        rule.frame = model.rule
        searchBox.frame = model.searchBox.insetBy(dx: -QueueSearchBoxView.ringWidth, dy: -QueueSearchBoxView.ringWidth)
        searchBox.setClearButtonFrame(model.clearButton)
        sortButton.frame = model.sortButton
        filterButton.frame = model.filterButton
        closeButton.frame = model.closeButton

        if model.isCompact {
            sortButton.content = .symbol(name: "arrow.up.arrow.down", pointSize: 13)
        } else {
            sortButton.content = .sortLabel(sortMode.title)
        }
    }

    // MARK: Actions

    @objc private func sortTapped() {
        let menu = NSMenu(title: "Queue sort order")
        for mode in QueueSortMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(sortItemChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mode.rawValue
            item.state = mode == sortMode ? .on : .off
            menu.addItem(item)
        }
        // The menu opens 4 pt below the button.
        menu.popUp(positioning: nil,
                   at: NSPoint(x: sortButton.bounds.minX, y: sortButton.bounds.minY - DWBMetrics.queueSortMenuOffset),
                   in: sortButton)
    }

    @objc private func sortItemChosen(_ sender: NSMenuItem) {
        guard let mode = QueueSortMode(rawValue: sender.tag) else { return }
        onSortModeChosen?(mode)
    }

    @objc private func filterTapped() { onBookmarkFilterToggled?() }
    @objc private func closeTapped() { onCloseRequested?() }
}

// MARK: - Buttons

/// A 28 pt tall, radius 5 header button with no fill at rest: overlayHover on hover, overlayPressed while pressed,
/// accentTint with an accentText glyph when toggled on. Keyboard focus uses the system focus ring.
final class QueueHeaderButton: NSButton {

    enum Content: Equatable {
        case symbol(name: String, pointSize: CGFloat)
        /// The expanded sort button: the current order and a chevron.
        case sortLabel(String)
    }

    static let sortLabelFont = NSFont.systemFont(ofSize: 10.5, weight: .regular)

    var content: Content = .symbol(name: "xmark", pointSize: 15) {
        didSet { if content != oldValue { needsDisplay = true } }
    }

    var isOn = false {
        didSet { if isOn != oldValue { needsDisplay = true } }
    }

    /// False for the clear button, which has no hover or pressed ground.
    var drawsGround = true
    /// The clear button's glyph is `textSecondary`; every other header glyph is `textPrimary`.
    var usesSecondaryGlyph = false

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    private var isHovering = false {
        didSet { needsDisplay = true }
    }
    private var trackingAreaReference: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        focusRingType = .exterior
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    @objc private func accessibilityDidChange() { needsDisplay = true }

    // MARK: Drawing

    private var glyphColor: NSColor {
        if isOn { return theme.accentText }
        return usesSecondaryGlyph ? DWBAccessibility.textSecondary : DWBColor.textPrimary
    }

    override func draw(_ dirtyRect: NSRect) {
        if drawsGround {
            let path = NSBezierPath(roundedRect: bounds,
                                    xRadius: DWBMetrics.queueHeaderButtonRadius,
                                    yRadius: DWBMetrics.queueHeaderButtonRadius)
            if isOn {
                DWBAccessibility.accentTint.setFill()
                path.fill()
            } else if isHighlighted {
                DWBColor.overlayPressed.setFill()
                path.fill()
            } else if isHovering {
                DWBColor.overlayHover.setFill()
                path.fill()
            }
        }
        switch content {
        case .symbol(let name, let pointSize):
            drawSymbol(name, pointSize: pointSize, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        case .sortLabel(let title):
            drawSortLabel(title)
        }
    }

    private func drawSymbol(_ name: String, pointSize: CGFloat, centeredAt center: NSPoint) {
        guard let image = NSImage.dwbSymbol(name, pointSize: pointSize, weight: .medium, color: glyphColor) else { return }
        let size = image.size
        image.draw(in: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                              width: size.width, height: size.height))
    }

    private func drawSortLabel(_ title: String) {
        let pad = QueueHeaderLayout.sortButtonPadding
        let chevron = QueueHeaderLayout.sortChevron
        let chevronCenter = NSPoint(x: bounds.maxX - pad - chevron / 2, y: bounds.midY)
        drawSymbol("chevron.down", pointSize: chevron, centeredAt: chevronCenter)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.sortLabelFont, .foregroundColor: DWBColor.textPrimary, .paragraphStyle: paragraph,
        ]
        let lineHeight = ceil(Self.sortLabelFont.ascender - Self.sortLabelFont.descender + Self.sortLabelFont.leading)
        let textWidth = max(0, bounds.width - pad * 2 - QueueHeaderLayout.sortLabelChevronGap - chevron)
        (title as NSString).draw(in: NSRect(x: pad, y: bounds.midY - lineHeight / 2, width: textWidth, height: lineHeight),
                                 withAttributes: attributes)
    }

    // MARK: Focus ring

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds,
                     xRadius: DWBMetrics.queueHeaderButtonRadius,
                     yRadius: DWBMetrics.queueHeaderButtonRadius).fill()
    }

    // MARK: Hover

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

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }
}

// MARK: - Search

/// The search field, with focus reported so the box can draw its focus edge. The field draws no ground,
/// magnifier or cancel button of its own.
final class QueueSearchTextField: NSSearchField {
    var onFocusChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = QueueSearchFieldCell(textCell: "")
        isEditable = true
        font = .systemFont(ofSize: 11)
        textColor = DWBColor.textPrimary
        drawsBackground = false
        isBordered = false
        focusRingType = .none
        sendsSearchStringImmediately = true
        sendsWholeSearchString = false
        toolTip = "Search queue filenames"
        setAccessibilityLabel("Search queue")
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

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

private final class QueueSearchFieldCell: NSSearchFieldCell {
    private let textLeading: CGFloat = 0
    private let textTrailing: CGFloat = 4

    override init(textCell string: String) {
        super.init(textCell: string)
        // NSCell.init(textCell:) creates a non-editable label cell; restore editability.
        isEditable = true
        usesSingleLineMode = true
        isScrollable = true
        lineBreakMode = .byClipping
        searchButtonCell = nil
        cancelButtonCell = nil
    }

    required init(coder: NSCoder) { fatalError() }

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect { .zero }
    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect { .zero }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textHeight = ceil(font.ascender - font.descender + font.leading)
        return NSRect(x: rect.minX + textLeading,
                      y: rect.minY + floor((rect.height - textHeight) / 2),
                      width: max(0, rect.width - textLeading - textTrailing),
                      height: textHeight)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect { searchTextRect(forBounds: rect) }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj,
                   delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                         delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj,
                     delegate: delegate, start: selStart, length: selLength)
    }
}

/// The search ground: 28 pt tall, radius 6, `surfaceElevated`, no border. Focused: a 1 pt `accentFill` edge
/// and a 1 pt `accentFill` outer ring (the view is 1 pt larger than the box on every side to hold the ring).
/// Under Increase Contrast the focus color is `accentText`.
final class QueueSearchBoxView: NSView {

    static let ringWidth: CGFloat = 1
    static let magnifierInset: CGFloat = 7
    static let magnifierSize: CGFloat = 12
    static let magnifierGap: CGFloat = 6

    let field = QueueSearchTextField()
    private let clearButton = QueueHeaderButton()
    var onClear: (() -> Void)?
    private var isFocused = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.onFocusChange = { [weak self] focused in self?.isFocused = focused }
        addSubview(field)

        clearButton.drawsGround = false
        clearButton.usesSecondaryGlyph = true
        clearButton.content = .symbol(name: "xmark", pointSize: 10)
        clearButton.toolTip = "Clear search text"
        clearButton.setAccessibilityLabel("Clear search text")
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        clearButton.isHidden = true
        addSubview(clearButton)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    @objc private func accessibilityDidChange() { needsDisplay = true }

    @objc private func clearTapped() { onClear?() }

    /// Places the clear button (given in the header's coordinates by the layout), or hides it.
    func setClearButtonFrame(_ headerFrame: CGRect?) {
        needsLayout = true
        guard let headerFrame else {
            clearButton.isHidden = true
            return
        }
        clearButton.isHidden = false
        clearButton.frame = CGRect(x: headerFrame.minX - frame.minX, y: headerFrame.minY - frame.minY,
                                   width: headerFrame.width, height: headerFrame.height)
    }

    override func layout() {
        super.layout()
        let ring = Self.ringWidth
        let boxMinX = ring
        let textX = boxMinX + Self.magnifierInset + Self.magnifierSize + Self.magnifierGap
        let rightLimit = clearButton.isHidden ? bounds.maxX - ring - 4 : clearButton.frame.minX
        let fieldH: CGFloat = 20
        field.frame = NSRect(x: textX, y: floor((bounds.height - fieldH) / 2),
                             width: max(0, rightLimit - textX), height: fieldH)
    }

    override func draw(_ dirtyRect: NSRect) {
        let ring = Self.ringWidth
        let box = bounds.insetBy(dx: ring, dy: ring)
        let radius = DWBMetrics.queueSearchRadius
        let boxPath = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
        DWBColor.surfaceElevated.setFill()
        boxPath.fill()

        if isFocused {
            let color = DWBAccessibility.focusRing
            color.setStroke()
            let inner = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
            inner.lineWidth = 1
            inner.stroke()
            let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius + 0.5, yRadius: radius + 0.5)
            outer.lineWidth = 1
            outer.stroke()
        }

        if let glyph = NSImage.dwbSymbol("magnifyingglass", pointSize: Self.magnifierSize, weight: .regular,
                                         color: DWBAccessibility.textTertiary) {
            let size = glyph.size
            glyph.draw(in: NSRect(x: box.minX + Self.magnifierInset,
                                  y: bounds.midY - size.height / 2,
                                  width: size.width, height: size.height))
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// A click anywhere on the box focuses the field.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(field)
    }
}
