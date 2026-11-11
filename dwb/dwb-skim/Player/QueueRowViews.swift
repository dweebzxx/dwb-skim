import Cocoa

// Queue panel rows and small queue drawing views (design system 5 "Queue panel" and
// "File markers", 9.7 "Queue interactions"). All colors resolve at draw time, so
// Increase Contrast applies when the rows reload.

// MARK: - Row background

/// The row card: 56 pt tall, inset 4 pt, radius 8, 1 pt `gridLine` edge.
///
/// - Current: `accentTint` fill, 1 pt `accentFill` edge, a 3 pt `accentFill` bar.
/// - Selected: `overlaySelected` fill with a 1 pt `borderStrong` edge.
/// - Hover: `overlayHover`.
final class QueuePageRowView: NSTableRowView {

    var isCurrent: Bool = false {
        didSet { needsDisplay = true }
    }

    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    private var trackingAreaReference: NSTrackingArea?

    // Ensure the row redraws whenever isSelected changes. With selectionHighlightStyle = .none,
    // AppKit may not reliably call setNeedsDisplay on the row view after a programmatic
    // selectRowIndexes call, so we force it here.
    override var isSelected: Bool {
        get { super.isSelected }
        set { if super.isSelected != newValue { super.isSelected = newValue; needsDisplay = true } }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        let inset = DWBMetrics.queueRowInset
        let card = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusRow, yRadius: DWBMetrics.radiusRow)

        let fill: NSColor?
        if isCurrent {
            fill = DWBAccessibility.accentTint
        } else if isSelected {
            fill = DWBColor.overlaySelected
        } else if isHovering {
            fill = DWBColor.overlayHover
        } else {
            fill = nil
        }
        if let fill {
            fill.setFill()
            path.fill()
        }

        (isSelected ? DWBColor.borderStrong : (isCurrent ? theme.accentFill : DWBColor.gridLine)).setStroke()
        path.lineWidth = 1
        path.stroke()

        if isCurrent {
            theme.accentFill.setFill()
            let bar = NSRect(x: card.minX + 4, y: card.minY + 10, width: 3, height: max(0, card.height - 20))
            NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
        }
    }

    // Use drawBackground for selection so we don't get the system blue.
    override var isEmphasized: Bool { get { false } set {} }

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
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }
}

// MARK: - Row content

final class QueuePageCell: NSView {

    private let leadingIcon = NSImageView()
    private let nameView = QueueRowNameView()
    private let metadataLabel = DWBLabel("", size: 10.5, tone: .tertiary, tabularDigits: true)
    private let bookmarkIndicator = NSImageView()

    init(reuseID: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = reuseID

        leadingIcon.imageScaling = .scaleProportionallyDown
        addSubview(leadingIcon)

        addSubview(nameView)

        metadataLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(metadataLabel)

        bookmarkIndicator.imageScaling = .scaleProportionallyDown
        addSubview(bookmarkIndicator)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let inset = DWBMetrics.queueRowInset
        let card = bounds.insetBy(dx: inset, dy: inset)
        let slotX = card.minX + 12
        let slotWidth: CGFloat = 14
        leadingIcon.frame = NSRect(x: slotX, y: card.midY - 7, width: slotWidth, height: 14)

        let textX = slotX + slotWidth + 8
        var right = card.maxX - 10
        if !bookmarkIndicator.isHidden {
            bookmarkIndicator.frame = NSRect(x: right - 12, y: card.midY - 6, width: 12, height: 12)
            right -= 12 + 8
        }
        let width = max(0, right - textX)
        let nameHeight: CGFloat = 16
        let metadataHeight: CGFloat = 13
        let gap: CGFloat = 3
        let blockBottom = card.midY - (nameHeight + gap + metadataHeight) / 2
        metadataLabel.frame = NSRect(x: textX, y: blockBottom, width: width, height: metadataHeight)
        nameView.frame = NSRect(x: textX, y: blockBottom + metadataHeight + gap, width: width, height: nameHeight)
    }

    /// The row's filename, with its configured marker prefix in bold marker color at 100%
    /// and the first search match in bold on an `accentTintStrong` ground with a 1 pt
    /// `accentText` underline.
    static func attributedName(for name: String,
                               isCurrent: Bool,
                               isFailed: Bool,
                               searchQuery: String,
                               primaryPrefix: String,
                               secondaryPrefix: String) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: 12.5, weight: isCurrent ? .semibold : .medium)
        let boldFont = NSFont.systemFont(ofSize: 12.5, weight: .bold)
        let result = NSMutableAttributedString(string: name, attributes: [
            .font: baseFont,
            .foregroundColor: isFailed ? DWBAccessibility.textSecondary : DWBColor.textPrimary,
        ])

        let marker = SkimReviewStatusDescriptor.describe(displayName: name,
                                                         primaryPrefix: primaryPrefix,
                                                         secondaryPrefix: secondaryPrefix)
        if let token = marker.prefixToken, let color = marker.statusColor {
            result.addAttributes([
                .font: boldFont,
                .foregroundColor: color,
            ], range: NSRange(location: 0, length: (token as NSString).length))
        }

        if let match = QueueSearchHighlight.matchRange(in: name, query: searchQuery) {
            result.addAttributes([
                .font: boldFont,
                .backgroundColor: theme.accentTintStrong,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: theme.accentText,
            ], range: match)
        }
        return result
    }

    func configure(item: QueuePageView.Item,
                   isCurrent: Bool,
                   searchQuery: String,
                   primaryPrefix: String,
                   secondaryPrefix: String) {
        nameView.attributedText = Self.attributedName(for: item.displayName,
                                                      isCurrent: isCurrent,
                                                      isFailed: item.isFailed,
                                                      searchQuery: searchQuery,
                                                      primaryPrefix: primaryPrefix,
                                                      secondaryPrefix: secondaryPrefix)

        metadataLabel.stringValue = "\(item.duration) | \(item.fileSize)"
        metadataLabel.tone = item.isFailed ? .error : .tertiary

        if isCurrent {
            leadingIcon.image = Self.symbol("play.fill", pointSize: 11, label: "Now playing")
            leadingIcon.contentTintColor = theme.accentText
            leadingIcon.isHidden = false
        } else if item.isFailed {
            leadingIcon.image = Self.symbol("exclamationmark.triangle.fill", pointSize: 12, label: "Failed")
            leadingIcon.contentTintColor = DWBColor.errorText
            leadingIcon.isHidden = false
        } else {
            leadingIcon.image = nil
            leadingIcon.isHidden = true
        }

        if item.isBookmarked {
            bookmarkIndicator.image = Self.symbol("bookmark.fill", pointSize: 12, label: "Bookmarked")
            bookmarkIndicator.contentTintColor = DWBAccessibility.textSecondary
            bookmarkIndicator.isHidden = false
        } else {
            bookmarkIndicator.image = nil
            bookmarkIndicator.isHidden = true
        }
        needsLayout = true

        var accessibilityParts = [item.displayName]
        if item.isBookmarked {
            accessibilityParts.append("bookmarked")
        }
        setAccessibilityLabel(accessibilityParts.joined(separator: ", "))
        setAccessibilityValue(isCurrent ? "now playing" : (item.isFailed ? "failed" : "queued"))
    }

    private static func symbol(_ name: String, pointSize: CGFloat, label: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: label)
        return image?.withSymbolConfiguration(configuration) ?? image
    }
}

// MARK: - Filename text

/// One line of filename text drawn with TextKit so the search match gets a rounded
/// (radius 2) ground, which an attributed-string background cannot give.
final class QueueRowNameView: NSView {

    private let textStorage = NSTextStorage()
    private let layoutManager = QueueRoundedBackgroundLayoutManager()
    private let textContainer = NSTextContainer()

    var attributedText = NSAttributedString() {
        didSet {
            textStorage.setAttributedString(attributedText)
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 1
        textContainer.lineBreakMode = .byTruncatingMiddle
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        textContainer.containerSize = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else { return }
        let used = layoutManager.usedRect(for: textContainer)
        let origin = NSPoint(x: 0, y: floor((bounds.height - used.height) / 2))
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
    }
}

private final class QueueRoundedBackgroundLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>,
                                          count rectCount: Int,
                                          forCharacterRange charRange: NSRange,
                                          color: NSColor) {
        color.setFill()
        for index in 0..<rectCount {
            NSBezierPath(roundedRect: rectArray[index], xRadius: 2, yRadius: 2).fill()
        }
    }
}

// MARK: - Drop line

/// The drag-reorder drop line: a 2 pt `accentText` line in the row gap with an 8 pt ring
/// at its leading edge (2 pt `accentText` edge, `surface` fill).
final class QueueDropIndicatorView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let ring = DWBMetrics.dropRing
        let line = DWBMetrics.dropLine
        let midY = bounds.midY

        theme.accentText.setFill()
        NSBezierPath(roundedRect: NSRect(x: ring - 1, y: midY - line / 2,
                                         width: max(0, bounds.width - ring + 1), height: line),
                     xRadius: line / 2, yRadius: line / 2).fill()

        let circle = NSRect(x: 0, y: midY - ring / 2, width: ring, height: ring)
        let path = NSBezierPath(ovalIn: circle.insetBy(dx: 1, dy: 1))
        DWBColor.surface.setFill()
        path.fill()
        theme.accentText.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

// MARK: - Filtered-empty glyph

/// The neutral 44 pt circle of the filtered empty states: `surfaceElevated` fill and a
/// 1 pt `border`, with an 18 pt `textTertiary` glyph.
final class QueueEmptyGlyphView: NSView {

    var symbolName: String? {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        DWBColor.surfaceElevated.setFill()
        path.fill()
        DWBAccessibility.border.setStroke()
        path.lineWidth = 1
        path.stroke()

        guard let symbolName else { return }
        guard let image = NSImage.dwbSymbol(symbolName, pointSize: 18, weight: .regular,
                                            color: DWBAccessibility.textTertiary) else { return }
        let size = image.size
        image.draw(in: NSRect(x: bounds.midX - size.width / 2,
                              y: bounds.midY - size.height / 2,
                              width: size.width,
                              height: size.height))
    }
}
