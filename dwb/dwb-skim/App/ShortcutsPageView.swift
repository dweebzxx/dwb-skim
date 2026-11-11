import AppKit

// Settings > Shortcuts (design system `ShortcutsPage`): a keyboard map, a search pill,
// and the shortcut rows grouped by task. Hovering a row lights its keys on the map.

// MARK: - Page

final class ShortcutsPageView: NSView, NSTextFieldDelegate {

    private let mapView = ShortcutsKeyboardMapView()
    private let searchPill = ShortcutsSearchPill()
    private let groupsStack = NSStackView()
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        mapView.translatesAutoresizingMaskIntoConstraints = false
        searchPill.translatesAutoresizingMaskIntoConstraints = false
        groupsStack.orientation = .vertical
        groupsStack.alignment = .leading
        groupsStack.spacing = 18
        groupsStack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(mapView)
        stack.addArrangedSubview(searchPill)
        stack.addArrangedSubview(groupsStack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            searchPill.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            searchPill.widthAnchor.constraint(equalTo: stack.widthAnchor).withPriority(.defaultHigh),
            groupsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        searchPill.field.delegate = self
        mapView.tones = ShortcutsPresentation.mapTones()
        rebuildGroups(query: "")
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private var query: String { searchPill.field.stringValue }

    func controlTextDidChange(_ obj: Notification) {
        rebuildGroups(query: query)
    }

    private func rebuildGroups(query: String) {
        for view in groupsStack.arrangedSubviews {
            groupsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        mapView.highlightedKeys = []
        for group in ShortcutsPresentation.filtered(ShortcutsPresentation.groups, query: query) {
            let section = makeSection(group)
            groupsStack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: groupsStack.widthAnchor).isActive = true
        }
    }

    private func makeSection(_ group: ShortcutGroup) -> NSView {
        let title = DWBLabel(group.title, size: 11, weight: .semibold, tone: .accent)
        title.setAccessibilityRole(.staticText)
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0

        let section = NSStackView(views: [title, rows])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6

        for row in group.rows {
            let view = ShortcutRowView(row: row)
            view.onHoverChange = { [weak self] hovering in
                self?.mapView.highlightedKeys = hovering ? Set(row.mapKeys) : []
            }
            rows.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        rows.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

// MARK: - Search

/// A 28 pt, radius 12 pill: `surfaceElevated`, 1 pt `border`, a `magnifyingglass` glyph
/// and a 12 pt field.
private final class ShortcutsSearchPill: NSView {
    let field = DWBInlineTextField()
    private let icon = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = DWBColor.textPrimary
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setAccessibilityLabel("Search shortcuts")
        applyPlaceholder()
        addSubview(field)

        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityElement(false)
        addSubview(icon)
        applyIcon()
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 28) }

    private func applyPlaceholder() {
        field.placeholderAttributedString = NSAttributedString(string: "Search shortcuts", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: DWBAccessibility.textTertiary,
        ])
    }

    private func applyIcon() {
        icon.image = NSImage.dwbSymbol("magnifyingglass", pointSize: 12, weight: .regular,
                                       color: DWBAccessibility.textTertiary)
    }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 10, y: floor((bounds.height - 14) / 2), width: 14, height: 14)
        let height = ceil(field.intrinsicContentSize.height)
        field.frame = NSRect(x: 30,
                             y: floor((bounds.height - height) / 2),
                             width: max(0, bounds.width - 30 - 10),
                             height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusPill, yRadius: DWBMetrics.radiusPill)
        DWBColor.surfaceElevated.setFill()
        path.fill()
        DWBAccessibility.border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    @objc private func accessibilityDidChange() {
        applyPlaceholder()
        applyIcon()
        needsDisplay = true
    }
}

// MARK: - Row

/// A shortcut row: at least 30 pt tall, a `gridLine` bottom edge, and the keys drawn as
/// `surfaceElevated` caps with a `borderStrong` edge (the marker color for `N` and `M`).
private final class ShortcutRowView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    private let row: ShortcutRow
    private let titleLabel: DWBLabel
    private let capsStack = NSStackView()
    private var isHovering = false {
        didSet { needsDisplay = true }
    }
    private var trackingAreaReference: NSTrackingArea?

    init(row: ShortcutRow) {
        self.row = row
        titleLabel = DWBLabel(row.title, size: 13, tone: .primary)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        capsStack.orientation = .horizontal
        capsStack.spacing = 4
        capsStack.translatesAutoresizingMaskIntoConstraints = false
        for cap in row.caps {
            capsStack.addArrangedSubview(ShortcutKeyCapView(text: cap, tone: row.tone))
        }
        capsStack.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(capsStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            capsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            capsStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: capsStack.leadingAnchor, constant: -12),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityLabel(row.accessibilityLabel)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func draw(_ dirtyRect: NSRect) {
        if isHovering {
            DWBColor.overlayHover.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: DWBMetrics.radiusControl,
                         yRadius: DWBMetrics.radiusControl).fill()
        }
        DWBColor.gridLine.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
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
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        onHoverChange?(false)
    }
}

/// A key cap in a row: min width 22, 20 pt tall, radius 4, monospaced 11 pt medium.
private final class ShortcutKeyCapView: NSView {
    private let text: String
    private let tone: ShortcutRow.Tone

    init(text: String, tone: ShortcutRow.Tone) {
        self.text = text
        self.tone = tone
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
         .foregroundColor: DWBColor.textPrimary]
    }

    override var intrinsicContentSize: NSSize {
        let width = ceil((text as NSString).size(withAttributes: attributes).width)
        return NSSize(width: max(22, width + 12), height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusKey, yRadius: DWBMetrics.radiusKey)
        DWBColor.surfaceElevated.setFill()
        path.fill()
        let edge: NSColor
        switch tone {
        case .accent: edge = DWBColor.borderStrong
        case .markerPrimary: edge = theme.markerPrimary
        case .markerSecondary: edge = theme.markerSecondary
        }
        edge.setStroke()
        path.lineWidth = 1
        path.stroke()

        let measured = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: floor((bounds.width - measured.width) / 2),
                                            y: floor((bounds.height - measured.height) / 2)),
                                withAttributes: attributes)
    }

    @objc private func accessibilityDidChange() {
        needsDisplay = true
    }
}

// MARK: - Keyboard map

/// The QWERTY map: 26 × 24 pt key rects, the space bar and the arrow keys. Keys that have
/// a shortcut take `overlaySelected` and an accent edge (the marker color for `N` and
/// `M`); unused keys are `textDisabled`. The hovered row's keys light solid.
final class ShortcutsKeyboardMapView: NSView {

    var tones: [String: ShortcutRow.Tone] = [:] {
        didSet { needsDisplay = true }
    }

    var highlightedKeys: Set<String> = [] {
        didSet {
            if highlightedKeys != oldValue { needsDisplay = true }
        }
    }

    private let keyWidth: CGFloat = 26
    private let keyHeight: CGFloat = 24
    private let gap: CGFloat = 4
    private let padding: CGFloat = 12
    private let spaceWidth: CGFloat = 150

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        var widestLetters: CGFloat = 0
        for (index, row) in ShortcutsPresentation.mapLetterRows.enumerated() {
            let keys = CGFloat(row.count)
            let rowWidth: CGFloat = CGFloat(index) * 12 + keys * keyWidth + (keys - 1) * gap
            widestLetters = max(widestLetters, rowWidth)
        }
        let arrows = CGFloat(ShortcutsPresentation.mapArrowKeys.count)
        let arrowsWidth: CGFloat = arrows * keyWidth + (arrows - 1) * gap
        let bottom: CGFloat = 66 + spaceWidth + 20 + arrowsWidth
        let rows = CGFloat(ShortcutsPresentation.mapLetterRows.count + 1)
        let width: CGFloat = padding * 2 + max(widestLetters, bottom)
        let height: CGFloat = padding * 2 + rows * keyHeight + (rows - 1) * gap
        return NSSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let container = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                     xRadius: DWBMetrics.radiusCard, yRadius: DWBMetrics.radiusCard)
        DWBColor.canvas.setFill()
        container.fill()
        DWBAccessibility.border.setStroke()
        container.lineWidth = 1
        container.stroke()

        var y = padding
        for (index, row) in ShortcutsPresentation.mapLetterRows.enumerated() {
            var x = padding + CGFloat(index) * 12
            for key in row {
                drawKey(key, in: NSRect(x: x, y: y, width: keyWidth, height: keyHeight))
                x += keyWidth + gap
            }
            y += keyHeight + gap
        }
        var x = padding + 66
        drawKey(ShortcutsPresentation.mapSpaceKey, in: NSRect(x: x, y: y, width: spaceWidth, height: keyHeight))
        x += spaceWidth + 20
        for key in ShortcutsPresentation.mapArrowKeys {
            drawKey(key, in: NSRect(x: x, y: y, width: keyWidth, height: keyHeight))
            x += keyWidth + gap
        }
    }

    private func drawKey(_ key: String, in rect: NSRect) {
        let tone = tones[key]
        let isHot = highlightedKeys.contains(key)
        let toneColor: NSColor
        switch tone {
        case .markerPrimary: toneColor = theme.markerPrimary
        case .markerSecondary: toneColor = theme.markerSecondary
        default: toneColor = theme.accentFill
        }

        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusKey, yRadius: DWBMetrics.radiusKey)
        let fill: NSColor?
        if isHot {
            switch tone {
            case .markerPrimary: fill = theme.markerPrimary
            case .markerSecondary: fill = theme.markerSecondary
            default: fill = theme.accentSolid
            }
        } else {
            fill = tone != nil ? DWBColor.overlaySelected : nil
        }
        if let fill {
            fill.setFill()
            path.fill()
        }
        (tone != nil ? toneColor : DWBColor.gridLine).setStroke()
        path.lineWidth = 1
        path.stroke()

        guard key != ShortcutsPresentation.mapSpaceKey else { return }
        let textColor: NSColor
        if isHot {
            textColor = DWBColor.textOnFill
        } else if let tone {
            textColor = tone == .accent ? DWBColor.textPrimary : toneColor
        } else {
            textColor = DWBColor.textDisabled
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: textColor,
        ]
        let measured = (key as NSString).size(withAttributes: attributes)
        (key as NSString).draw(at: NSPoint(x: rect.midX - measured.width / 2,
                                           y: rect.midY - measured.height / 2),
                               withAttributes: attributes)
    }

    @objc private func accessibilityDidChange() {
        needsDisplay = true
    }
}
