import Cocoa
import CoreImage

// The empty and filtered-empty states of the queue list (design system 10.6). They are the only content of
// the list, centered. Frames come from `QueueEmptyStateLayout`.
//
//   Empty queue:      the faded app icon · "No media in queue" · "Add files or folders to build the queue." · Add Media
//   No search results / no bookmarks: a 44 pt glyph circle · title · one button (no app icon: the queue is not empty)

final class QueueEmptyStateView: NSView {

    /// The action button was pressed for this state.
    var onAction: ((QueueEmptyState) -> Void)?

    private let iconView = NSImageView()
    private let glyphCircle = QueueEmptyGlyphView()
    private let titleLabel = DWBLabel("", size: 14, weight: .semibold, tone: .primary)
    private let detailLabel = DWBLabel("", size: 11.5, tone: .tertiary)
    private let addMediaButton = DWBButton(title: "Add Media", style: .pillOutline)
    private let filterButton = QueueEmptyFilterButton()
    private(set) var state: QueueEmptyState = .emptyQueue

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.alphaValue = DWBMetrics.queueEmptyIconAlpha
        iconView.isEditable = false
        iconView.setAccessibilityElement(false)
        iconView.focusRingType = .none
        addSubview(iconView)

        addSubview(glyphCircle)

        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        detailLabel.alignment = .center
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 0
        detailLabel.cell?.wraps = true
        addSubview(detailLabel)

        addMediaButton.target = self
        addMediaButton.action = #selector(actionTapped)
        addSubview(addMediaButton)

        filterButton.target = self
        filterButton.action = #selector(actionTapped)
        addSubview(filterButton)

        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    func configure(state: QueueEmptyState) {
        self.state = state
        titleLabel.stringValue = state.title
        titleLabel.setAccessibilityLabel(state.title)
        let isEmptyQueue = state == .emptyQueue

        iconView.isHidden = !isEmptyQueue
        if isEmptyQueue { iconView.image = Self.fadedAppIcon }
        glyphCircle.isHidden = isEmptyQueue
        glyphCircle.symbolName = state.glyphName

        detailLabel.isHidden = state.detail == nil
        detailLabel.stringValue = state.detail ?? ""

        addMediaButton.isHidden = !isEmptyQueue
        addMediaButton.title = state.actionTitle
        addMediaButton.setAccessibilityLabel(state.actionTitle)
        addMediaButton.toolTip = isEmptyQueue ? "Add media to the queue" : nil
        filterButton.isHidden = isEmptyQueue
        filterButton.title = state.actionTitle
        filterButton.setAccessibilityLabel(state.actionTitle)
        needsLayout = true
    }

    @objc private func actionTapped() { onAction?(state) }

    // MARK: Layout

    /// The wrapped height of the detail line at `width`.
    private func detailHeight(width: CGFloat) -> CGFloat {
        guard let detail = state.detail, width > 0 else { return 0 }
        let rect = (detail as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                     attributes: [.font: NSFont.systemFont(ofSize: 11.5)])
        return ceil(rect.height)
    }

    override func layout() {
        super.layout()
        let isEmptyQueue = state == .emptyQueue
        let textW = QueueEmptyStateLayout.textWidth(containerWidth: bounds.width)
        let buttonSize = isEmptyQueue
            ? NSSize(width: ceil(addMediaButton.intrinsicContentSize.width), height: DWBMetrics.queueEmptyPill)
            : filterButton.intrinsicContentSize
        let model = QueueEmptyStateLayout.make(lead: isEmptyQueue ? .appIcon : .glyphCircle,
                                               container: bounds.size,
                                               detailHeight: detailHeight(width: textW),
                                               buttonSize: buttonSize)
        if isEmptyQueue {
            iconView.frame = model.lead
            addMediaButton.frame = model.button
        } else {
            glyphCircle.frame = model.lead
            filterButton.frame = model.button
        }
        titleLabel.frame = model.title
        if let detail = model.detail { detailLabel.frame = detail }
    }

    // MARK: Faded app icon

    /// `NSApp.applicationIconImage` at the design system's saturation (0.6). The 0.32 alpha is the image view's.
    private static let fadedAppIcon: NSImage? = {
        guard let icon = NSApplication.shared.applicationIconImage else { return nil }
        var rect = NSRect(x: 0, y: 0, width: DWBMetrics.queueEmptyIcon * 2, height: DWBMetrics.queueEmptyIcon * 2)
        guard let cgImage = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let filter = CIFilter(name: "CIColorControls") else { return icon }
        filter.setValue(CIImage(cgImage: cgImage), forKey: kCIInputImageKey)
        filter.setValue(DWBMetrics.queueEmptyIconSaturation, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage,
              let desaturated = CIContext().createCGImage(output, from: output.extent) else { return icon }
        return NSImage(cgImage: desaturated,
                       size: NSSize(width: DWBMetrics.queueEmptyIcon, height: DWBMetrics.queueEmptyIcon))
    }()
}

// MARK: - Filtered-empty glyph

/// The neutral 44 pt circle of the filtered empty states: `surfaceElevated` fill and a 1 pt `border`, with an
/// 18 pt `textSecondary` glyph.
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
        guard let image = NSImage.dwbSymbol(symbolName, pointSize: DWBMetrics.queueEmptyGlyph, weight: .regular,
                                            color: DWBAccessibility.textSecondary) else { return }
        let size = image.size
        image.draw(in: NSRect(x: bounds.midX - size.width / 2,
                              y: bounds.midY - size.height / 2,
                              width: size.width,
                              height: size.height))
    }
}

// MARK: - Filtered-empty action

/// The one button of a filtered-empty state: 11 pt, padding 7 / 12, radius 5, `surfaceElevated` with a 1 pt `border`.
final class QueueEmptyFilterButton: NSButton {

    private var isHovering = false { didSet { needsDisplay = true } }
    private var trackingAreaReference: NSTrackingArea?
    private let labelFont = NSFont.systemFont(ofSize: 11)

    init() {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        focusRingType = .exterior
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    @objc private func accessibilityDidChange() { needsDisplay = true }

    override var isHighlighted: Bool { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize {
        let lineHeight = ceil(labelFont.ascender - labelFont.descender + labelFont.leading)
        return NSSize(width: QueueFonts.width(of: title, font: labelFont) + 24 + 2, height: lineHeight + 14 + 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = DWBMetrics.queueEmptyButtonRadius
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        DWBColor.surfaceElevated.setFill()
        path.fill()
        if isHighlighted {
            DWBColor.overlayPressed.setFill()
            path.fill()
        } else if isHovering {
            DWBColor.overlayHover.setFill()
            path.fill()
        }
        DWBAccessibility.border.setStroke()
        path.lineWidth = 1
        path.stroke()

        let size = (title as NSString).size(withAttributes: [.font: labelFont])
        (title as NSString).draw(at: NSPoint(x: floor((bounds.width - size.width) / 2),
                                             y: floor((bounds.height - size.height) / 2)),
                                 withAttributes: [.font: labelFont, .foregroundColor: DWBColor.textPrimary])
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: DWBMetrics.queueEmptyButtonRadius,
                     yRadius: DWBMetrics.queueEmptyButtonRadius).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }

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
