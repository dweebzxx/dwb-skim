import Cocoa

// Queue panel rows and small queue drawing views (design system 10.4 "Rows"; 5 "File markers" for the prefix color;
// 9.7 "Queue interactions" for the search highlight). All colors resolve at draw time, so Increase Contrast applies
// when the rows reload. Geometry and state precedence come from `QueueRowMetrics` and `QueueRowAppearance`.

// MARK: - Row background

/// The row's ground, drawn in the row view's flipped coordinates.
///
/// - Flat row (44 pt): no fill and no outline at rest, with a 0.5 pt `gridLine` separator under it. Hover is
///   `overlayHover`. Selected is `overlaySelected` with a 1 pt `borderStrong` inner edge and no separator.
/// - Playing card (48 pt plus a 4 pt gap): a uniform `accentTintStrong` fill, a 0.5 pt `border` inner edge
///   (`borderStrong` on hover, 1 pt when selected) and a 3 pt `accentText` strip flush with the left edge,
///   clipped to the card's own rounded shape. No gradient, no detached stripe, no separator.
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
        let appearance = QueueRowAppearance.resolve(isCurrent: isCurrent, isSelected: isSelected, isHovering: isHovering)
        let card = QueueRowMetrics.cardFrame(rowWidth: bounds.width, isCurrent: isCurrent)
        let radius = appearance.cornerRadius
        let shape = NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius)

        switch appearance.fill {
        case .none: break
        case .overlayHover: DWBColor.overlayHover.setFill(); shape.fill()
        case .overlaySelected: DWBColor.overlaySelected.setFill(); shape.fill()
        case .accentTintStrong: theme.accentTintStrong.setFill(); shape.fill()
        }

        switch appearance.edge {
        case .none:
            break
        case .border, .borderStrong:
            // The edge is drawn inside the card so nothing overhangs it, and nothing draws over it afterwards.
            let edgeRect = QueueRowMetrics.edgeRect(card: card, width: appearance.edgeWidth)
            let edge = NSBezierPath(roundedRect: edgeRect,
                                    xRadius: radius - appearance.edgeWidth / 2,
                                    yRadius: radius - appearance.edgeWidth / 2)
            edge.lineWidth = appearance.edgeWidth
            (appearance.edge == .border ? DWBAccessibility.border : DWBColor.borderStrong).setStroke()
            edge.stroke()
        }

        if appearance.showsPlayingStrip {
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            theme.accentText.setFill()
            QueueRowMetrics.playingStripFrame(card: card).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        if appearance.showsSeparator {
            DWBColor.gridLine.setFill()
            QueueRowMetrics.separatorFrame(card: card).fill()
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

    private var isCurrent = false
    private var isFailed = false
    private var isSearching = false
    private var fullName = NSAttributedString()
    private var metadataText = ""
    /// The width the name was last fitted to, with a generation so new content refits.
    private var fittedNameWidth: CGFloat = -1
    private var contentGeneration = 0
    private var fittedGeneration = -1

    init(reuseID: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = reuseID

        leadingIcon.imageScaling = .scaleProportionallyDown
        addSubview(leadingIcon)

        addSubview(nameView)

        metadataLabel.lineBreakMode = .byTruncatingTail
        addSubview(metadataLabel)

        bookmarkIndicator.imageScaling = .scaleProportionallyDown
        addSubview(bookmarkIndicator)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let card = QueueRowMetrics.cardFrame(rowWidth: bounds.width, isCurrent: isCurrent)
        let frames = QueueRowMetrics.frames(card: card,
                                            isCurrent: isCurrent,
                                            isFailed: isFailed,
                                            hasBookmark: !bookmarkIndicator.isHidden)
        leadingIcon.frame = frames.leadingGlyph ?? .zero
        if let bookmark = frames.bookmark { bookmarkIndicator.frame = bookmark }
        nameView.frame = frames.name
        metadataLabel.frame = frames.meta
        fitName(to: frames.name.width)
        fitMetadata(to: frames.meta.width)
    }

    /// Middle-truncates the name to the width left after the accessories (section 10.4). While a search is
    /// active the name is end-clipped instead, so the first match keeps its position.
    private func fitName(to width: CGFloat) {
        guard fittedNameWidth != width || fittedGeneration != contentGeneration else { return }
        fittedNameWidth = width
        fittedGeneration = contentGeneration
        nameView.attributedText = isSearching ? fullName : QueueNameFitting.fitted(fullName, maxWidth: width)
    }

    private func fitMetadata(to width: CGFloat) {
        if isFailed {
            metadataLabel.stringValue = QueueRowTextPresentation.failedMeta(maxWidth: width) {
                QueueFonts.width(of: $0, font: QueueFonts.metadata)
            }
        } else {
            metadataLabel.stringValue = metadataText
        }
    }

    func configure(item: QueuePageView.Item,
                   isCurrent: Bool,
                   searchQuery: String,
                   primaryPrefix: String,
                   secondaryPrefix: String) {
        self.isCurrent = isCurrent
        isFailed = item.isFailed
        isSearching = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        fullName = QueueNameStyle.attributed(for: item.displayName,
                                              isCurrent: isCurrent,
                                              searchQuery: searchQuery,
                                              primaryPrefix: primaryPrefix,
                                              secondaryPrefix: secondaryPrefix)
        contentGeneration += 1

        metadataText = QueueRowTextPresentation.metadata(duration: item.duration, fileSize: item.fileSize)
        metadataLabel.tone = item.isFailed ? .error : .tertiary

        if isCurrent {
            leadingIcon.image = Self.symbol("play.fill", pointSize: DWBMetrics.queuePlayingGlyph, label: "Now playing")
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
            bookmarkIndicator.image = Self.symbol("bookmark.fill", pointSize: 10, label: "Bookmarked")
            bookmarkIndicator.contentTintColor = DWBAccessibility.textSecondary
            bookmarkIndicator.isHidden = false
        } else {
            bookmarkIndicator.image = nil
            bookmarkIndicator.isHidden = true
        }
        needsLayout = true

        // The full name is the row's identity: tooltip and accessible name, whatever is drawn.
        toolTip = item.displayName
        var accessibilityParts = [item.displayName]
        if item.isBookmarked {
            accessibilityParts.append("bookmarked")
        }
        setAccessibilityLabel(accessibilityParts.joined(separator: ", "))
        setAccessibilityValue(isCurrent ? "now playing" : (item.isFailed ? "failed" : "queued"))
        setAccessibilityHelp(item.isFailed ? QueueRowTextPresentation.failedMetaFull : nil)
    }

    private static func symbol(_ name: String, pointSize: CGFloat, label: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: label)
        return image?.withSymbolConfiguration(configuration) ?? image
    }
}

// MARK: - Filename text

/// One line of filename text drawn with TextKit so the search match gets a rounded
/// (radius 2) ground, which an attributed-string background cannot give. The text arrives already fitted
/// (`QueueNameFitting`), so the line itself only clips.
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
        textContainer.lineBreakMode = .byClipping
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

/// The drag-reorder insertion line (Manual order, no filter): a straight 2 pt `accentText` line on the
/// shared edge between two rows. No ring.
final class QueueDropIndicatorView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        theme.accentText.setFill()
        NSRect(x: 0, y: bounds.midY - DWBMetrics.dropLine / 2, width: bounds.width, height: DWBMetrics.dropLine).fill()
    }
}
