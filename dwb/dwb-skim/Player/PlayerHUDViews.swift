import Cocoa

// The player window's transient overlays, built to the design system (sections 5 and 9.4):
// the status HUD, title overlay, failure message, undo toast, and drop zone.
// Every color comes from `DWBColor` or `theme`; backings turn opaque under Increase Contrast and
// fades are instant under Reduce Motion (`DWBAccessibility`).

// MARK: - Shared surface

/// A rounded, layer-backed HUD surface: a backing color, an optional 1 pt edge, an optional
/// shadow, and the hold-then-fade lifecycle every transient overlay shares.
class HUDSurfaceView: NSView {
    private let backing: () -> NSColor
    private let edge: (() -> NSColor)?
    private let hasShadow: Bool
    private var generation = 0
    private var dismissalWorkItem: DispatchWorkItem?

    init(backing: @escaping () -> NSColor,
         edge: (() -> NSColor)? = nil,
         hasShadow: Bool = false,
         cornerRadius: CGFloat = DWBMetrics.radiusCard) {
        self.backing = backing
        self.edge = edge
        self.hasShadow = hasShadow
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = false
        if edge != nil { layer?.borderWidth = 1 }
        if hasShadow {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.45
            layer?.shadowOffset = CGSize(width: 0, height: -8)
            layer?.shadowRadius = 12
        }
        alphaValue = 0
        isHidden = true
        refreshColors()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(accessibilityOptionsChanged),
                                               name: DWBAccessibility.didChange,
                                               object: nil)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit {
        dismissalWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    /// HUDs never take clicks; the video underneath stays interactive.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @objc private func accessibilityOptionsChanged() { refreshColors() }

    /// Re-resolves colors that depend on Increase Contrast. Subclasses extend this.
    func refreshColors() {
        layer?.backgroundColor = backing().cgColor
        if let edge { layer?.borderColor = edge().cgColor }
    }

    /// Shows the surface at full alpha and fades it out after `hold` seconds.
    func present(hold: TimeInterval) {
        dismissalWorkItem?.cancel()
        generation += 1
        let shown = generation
        isHidden = false
        alphaValue = 1
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == shown else { return }
            self.fadeOut(generation: shown)
        }
        dismissalWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: work)
    }

    private func fadeOut(generation shown: Int) {
        let duration = DWBAccessibility.duration(DWBMotion.fade)
        guard duration > 0 else {
            alphaValue = 0
            isHidden = true
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            self.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.generation == shown else { return }
            self.isHidden = true
        }
    }

    /// Hides at once, with no fade. Used when another overlay takes this one's slot.
    func dismissImmediately() {
        dismissalWorkItem?.cancel()
        dismissalWorkItem = nil
        generation += 1
        alphaValue = 0
        isHidden = true
    }

    var isShowing: Bool { !isHidden && alphaValue > 0 }

    /// Announces `text` to VoiceOver from this view.
    func announce(_ text: String, priority: NSAccessibilityPriorityLevel) {
        NSAccessibility.post(element: self,
                             notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: priority.rawValue])
    }
}

/// Text helpers shared by the overlays.
enum HUDText {
    /// A filename with its marker prefix (primary on `N`, secondary on `M`) in the marker color and bold.
    static func filename(_ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
        let truncation = NSMutableParagraphStyle()
        truncation.lineBreakMode = .byTruncatingMiddle
        let result = NSMutableAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: truncation,
        ])
        let marker = SkimReviewStatusDescriptor.describe(
            displayName: name,
            primaryPrefix: SettingsWindowController.customPrefixValue(),
            secondaryPrefix: SettingsWindowController.customPrefixSecondaryValue())
        if let prefix = marker.prefixToken, let markerColor = marker.statusColor {
            result.addAttributes([
                .foregroundColor: markerColor,
                .font: NSFont.systemFont(ofSize: size, weight: .bold),
            ], range: NSRange(location: 0, length: (prefix as NSString).length))
        }
        return result
    }

    static func width(_ text: NSAttributedString) -> CGFloat { ceil(text.size().width) }

    /// A text field draws its text inset by about 2 pt on each side. A frame for `textWidth` of text
    /// at `x` is therefore `labelFrame(x:y:textWidth:height:)`, so the text itself starts at `x`.
    static func labelFrame(x: CGFloat, y: CGFloat, textWidth: CGFloat, height: CGFloat) -> NSRect {
        NSRect(x: x - 2, y: y, width: max(0, textWidth) + 4, height: height)
    }

    static func label(_ text: NSAttributedString = NSAttributedString()) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.attributedStringValue = text
        field.lineBreakMode = .byTruncatingMiddle
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.setAccessibilityElement(false)
        return field
    }

    static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular, tint: NSColor) -> NSImageView {
        let view = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        view.contentTintColor = tint
        view.imageScaling = .scaleProportionallyDown
        view.setAccessibilityElement(false)
        return view
    }
}

// MARK: - Title overlay

/// The video title at the top-center of the stage: `backingTitle`, 42 pt tall (38 under 560 pt wide).
final class TitleOverlayView: HUDSurfaceView {
    private let label = HUDText.label()
    private var title = ""

    init() {
        super.init(backing: { DWBAccessibility.backingTitle })
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    func show(title: String, in stage: NSRect, hold: TimeInterval) {
        self.title = title
        place(in: stage)
        setAccessibilityLabel(title)
        present(hold: hold)
    }

    /// Sizes and positions the overlay: at most 800 pt wide, 20 pt below the stage top.
    func place(in stage: NSRect) {
        guard !title.isEmpty, stage.width > 0, stage.height > 0 else { return }
        let compact = stage.width < 560
        let text = HUDText.filename(title, size: compact ? 17 : 20, weight: .semibold, color: DWBColor.textPrimary)
        let height: CGFloat = compact ? 38 : 42
        let padding: CGFloat = 18
        let width = max(0, min(min(stage.width - 40, 800), HUDText.width(text) + padding * 2))
        frame = NSRect(x: stage.minX + (stage.width - width) / 2,
                       y: stage.maxY - 20 - height,
                       width: width,
                       height: height)
        label.attributedStringValue = text
        let labelHeight = ceil(text.size().height)
        label.frame = HUDText.labelFrame(x: padding, y: (height - labelHeight) / 2,
                                         textWidth: width - padding * 2, height: labelHeight)
    }
}

// MARK: - Failure message

/// "Unable to play "<filename>" — skipped": `backingHUD` with a 1 pt `errorFill` edge.
final class FailureMessageView: HUDSurfaceView {
    static let height: CGFloat = 40
    private let iconView = HUDText.symbol("xmark.octagon.fill", size: 16, tint: DWBColor.errorText)
    private let label = HUDText.label()
    private var message = ""

    init() {
        super.init(backing: { DWBAccessibility.backingHUD }, edge: { DWBColor.errorFill }, hasShadow: true)
        addSubview(iconView)
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    func show(filename: String, in stage: NSRect, topOffset: CGFloat) {
        message = "Unable to play \"\(filename)\""
        place(in: stage, topOffset: topOffset)
        let spoken = "\(message) — skipped"
        setAccessibilityLabel(spoken)
        present(hold: DWBMotion.failureHold)
        announce(spoken, priority: .high)
    }

    /// Centered at the top of the stage, `topOffset` below its top edge.
    func place(in stage: NSRect, topOffset: CGFloat) {
        guard !message.isEmpty, stage.width > 0, stage.height > 0 else { return }
        let truncation = NSMutableParagraphStyle()
        truncation.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(string: message, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: DWBColor.textPrimary,
            .paragraphStyle: truncation,
        ])
        text.append(NSAttributedString(string: " — skipped", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: DWBAccessibility.textSecondary,
            .paragraphStyle: truncation,
        ]))
        let padding: CGFloat = 14
        let icon: CGFloat = 16
        let gap: CGFloat = 10
        let width = max(0, min(stage.width - 40, padding * 2 + icon + gap + HUDText.width(text)))
        frame = NSRect(x: stage.minX + (stage.width - width) / 2,
                       y: stage.maxY - topOffset - Self.height,
                       width: width,
                       height: Self.height)
        iconView.frame = NSRect(x: padding, y: (Self.height - icon) / 2, width: icon, height: icon)
        label.attributedStringValue = text
        let labelHeight = ceil(text.size().height)
        label.frame = HUDText.labelFrame(x: padding + icon + gap, y: (Self.height - labelHeight) / 2,
                                         textWidth: width - padding * 2 - icon - gap, height: labelHeight)
    }
}

// MARK: - Undo toast

/// The undo toast after a prefix change: 40 pt tall, `backingHUD`, with an "Undo" button.
final class UndoToastView: HUDSurfaceView {
    static let height: CGFloat = 40
    var onUndo: (() -> Void)?

    private let iconView = HUDText.symbol("checkmark.circle.fill", size: 15, tint: DWBAccessibility.textSecondary)
    private let leadingLabel = HUDText.label()
    private let valueLabel = HUDText.label()
    private let button = UndoToastButton()
    private var presentation: UndoToastPresentation?

    init() {
        super.init(backing: { DWBAccessibility.backingHUD }, edge: { DWBColor.hairline }, hasShadow: true)
        addSubview(iconView)
        addSubview(leadingLabel)
        addSubview(valueLabel)
        button.target = self
        button.action = #selector(undoTapped)
        addSubview(button)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    /// Only the button takes clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let local = convert(point, from: superview)
        return button.frame.contains(local) ? button : nil
    }

    @objc private func undoTapped() { onUndo?() }

    /// Shows the toast centered horizontally on `stage`, its bottom edge `bottomOffset` above the stage bottom.
    /// A new rename replaces the one showing and restarts the 3 s hold.
    func show(_ presentation: UndoToastPresentation, in stage: NSRect, bottomOffset: CGFloat) {
        self.presentation = presentation
        place(in: stage, bottomOffset: bottomOffset)
        setAccessibilityLabel(presentation.announcement)
        present(hold: 3)
        announce(presentation.announcement, priority: .medium)
    }

    func place(in stage: NSRect, bottomOffset: CGFloat) {
        guard let presentation, stage.width > 0, stage.height > 0 else { return }
        let leading = NSAttributedString(string: presentation.leadingText, attributes: [
            .font: NSFont.systemFont(ofSize: 12.5),
            .foregroundColor: DWBAccessibility.textSecondary,
        ])
        let value: NSAttributedString
        switch presentation.content {
        case .file(let name):
            value = HUDText.filename(name, size: 12.5, weight: .semibold, color: DWBColor.textPrimary)
        case .batch(let count):
            let text = NSMutableAttributedString(string: "\(count)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: DWBColor.textPrimary,
            ])
            text.append(NSAttributedString(string: " files", attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: DWBColor.textPrimary,
            ]))
            value = text
        }

        let leftPadding: CGFloat = 14
        let rightPadding: CGFloat = 6
        let icon: CGFloat = 15
        let gap: CGFloat = 10
        let buttonWidth = button.preferredWidth
        let fixed = leftPadding + icon + gap + HUDText.width(leading) + gap + gap + buttonWidth + rightPadding
        let maxWidth = max(0, min(stage.width - 40, 640))
        let valueWidth = max(0, min(HUDText.width(value), maxWidth - fixed))
        let width = fixed + valueWidth

        frame = NSRect(x: stage.minX + (stage.width - width) / 2,
                       y: stage.minY + bottomOffset,
                       width: width,
                       height: Self.height)

        var x = leftPadding
        iconView.frame = NSRect(x: x, y: (Self.height - icon) / 2, width: icon, height: icon)
        x += icon + gap
        leadingLabel.attributedStringValue = leading
        let leadingHeight = ceil(leading.size().height)
        leadingLabel.frame = HUDText.labelFrame(x: x, y: (Self.height - leadingHeight) / 2,
                                                textWidth: HUDText.width(leading), height: leadingHeight)
        x += HUDText.width(leading) + gap
        valueLabel.attributedStringValue = value
        let valueHeight = ceil(value.size().height)
        valueLabel.frame = HUDText.labelFrame(x: x, y: (Self.height - valueHeight) / 2,
                                              textWidth: valueWidth, height: valueHeight)
        x += valueWidth + gap
        button.frame = NSRect(x: x, y: (Self.height - UndoToastButton.height) / 2,
                              width: buttonWidth, height: UndoToastButton.height)
    }

    override func refreshColors() {
        super.refreshColors()
        iconView.contentTintColor = DWBAccessibility.textSecondary
    }
}

/// "Undo": 28 pt tall, radius 6, `overlaySelected` fill, `accentText` label. No `⌘Z` hint is drawn.
private final class UndoToastButton: NSButton {
    static let height: CGFloat = 28
    private static let horizontalPadding: CGFloat = 10

    private var isHovering = false
    private var tracking: NSTrackingArea?

    private static let titleText = NSAttributedString(string: "Undo", attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
        .foregroundColor: theme.accentText,
    ])

    var preferredWidth: CGFloat {
        Self.horizontalPadding * 2 + HUDText.width(Self.titleText)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.cornerRadius = DWBMetrics.radiusControl
        layer?.backgroundColor = DWBColor.overlaySelected.cgColor
        setAccessibilityLabel("Undo")
        setAccessibilityHelp("Undo the last prefix change (Command-Z)")
    }

    convenience init() { self.init(frame: .zero) }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override var isHighlighted: Bool {
        didSet { refreshFill() }
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
        refreshFill()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        refreshFill()
    }

    private func refreshFill() {
        let fill = (isHighlighted || isHovering) ? DWBColor.overlayPressed : DWBColor.overlaySelected
        layer?.backgroundColor = fill.cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        let titleSize = Self.titleText.size()
        Self.titleText.draw(at: NSPoint(x: Self.horizontalPadding, y: (bounds.height - titleSize.height) / 2))
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: DWBMetrics.radiusControl, yRadius: DWBMetrics.radiusControl).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }
}

// MARK: - Status HUD

/// The non-modal status HUD (9.4): at least 44 pt tall, in the volume HUD's slot.
final class StatusHUDView: HUDSurfaceView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    private enum Metrics {
        static let padding = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 18)
        static let icon: CGFloat = 16
        static let gap: CGFloat = 10
        static let maxWidth: CGFloat = 420
        static let detailMaxLines: CGFloat = 2
    }

    init() {
        super.init(backing: { DWBAccessibility.backingHUD }, edge: { DWBColor.hairline }, hasShadow: true)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setAccessibilityElement(false)
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = DWBColor.textPrimary
        titleLabel.setAccessibilityElement(false)
        addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = DWBAccessibility.textSecondary
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = Int(Metrics.detailMaxLines)
        detailLabel.setAccessibilityElement(false)
        addSubview(detailLabel)

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private var symbolName = ""
    private var symbolTint = DWBColor.textPrimary
    private var currentTitle = ""
    private var currentDetail: String?

    /// `spoken` replaces the default "title. detail" announcement when the visible text uses
    /// separators that read badly aloud.
    func show(symbol: String, tint: NSColor, title: String, detail: String?, hold: TimeInterval,
              in stage: NSRect, spoken: String? = nil) {
        symbolName = symbol
        symbolTint = tint
        currentTitle = title
        currentDetail = detail
        place(in: stage)
        let spoken = spoken ?? [title, detail].compactMap { $0 }.joined(separator: ". ")
        setAccessibilityLabel(spoken)
        present(hold: hold)
        announce(spoken, priority: .medium)
    }

    /// Centered on the stage, in the volume HUD's slot (`DWBMetrics.hudBottomOffset` above the stage bottom).
    func place(in stage: NSRect) {
        guard !currentTitle.isEmpty, stage.width > 0, stage.height > 0 else { return }
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Metrics.icon, weight: .regular))
        iconView.contentTintColor = symbolTint
        titleLabel.stringValue = currentTitle
        detailLabel.stringValue = currentDetail ?? ""
        detailLabel.isHidden = currentDetail == nil

        let titleSize = titleLabel.intrinsicContentSize
        // The detail wraps onto a second line at the HUD's maximum width instead of truncating.
        let maxTextWidth = max(0, min(stage.width - 40, Metrics.maxWidth)
                               - Metrics.padding.left - Metrics.icon - Metrics.gap - Metrics.padding.right)
        var detailSize = NSSize.zero
        if let detail = currentDetail, let font = detailLabel.font {
            let singleLine = ceil(detailLabel.intrinsicContentSize.width)
            let width = min(singleLine, maxTextWidth)
            let lineHeight = ceil(detailLabel.intrinsicContentSize.height)
            let wrapped = (detail as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                                           options: [.usesLineFragmentOrigin],
                                                           attributes: [.font: font])
            detailSize = NSSize(width: width, height: min(ceil(wrapped.height), lineHeight * Metrics.detailMaxLines))
        }
        let textWidth = max(ceil(titleSize.width), ceil(detailSize.width))
        let textHeight = ceil(titleSize.height) + (currentDetail == nil ? 0 : 1 + ceil(detailSize.height))
        let width = min(min(stage.width - 40, Metrics.maxWidth),
                        Metrics.padding.left + Metrics.icon + Metrics.gap + textWidth + Metrics.padding.right)
        let height = max(DWBMetrics.statusHUDMinHeight, Metrics.padding.top + textHeight + Metrics.padding.bottom)
        frame = NSRect(x: stage.minX + (stage.width - width) / 2,
                       y: stage.minY + DWBMetrics.hudBottomOffset,
                       width: width,
                       height: height)

        iconView.frame = NSRect(x: Metrics.padding.left, y: (height - Metrics.icon) / 2,
                                width: Metrics.icon, height: Metrics.icon)
        let textX = Metrics.padding.left + Metrics.icon + Metrics.gap
        let textW = max(0, width - textX - Metrics.padding.right)
        var y = (height + textHeight) / 2
        y -= ceil(titleSize.height)
        titleLabel.frame = HUDText.labelFrame(x: textX, y: y, textWidth: textW, height: ceil(titleSize.height))
        if currentDetail != nil {
            y -= 1 + ceil(detailSize.height)
            detailLabel.frame = HUDText.labelFrame(x: textX, y: y, textWidth: textW, height: ceil(detailSize.height))
        }
    }

    override func refreshColors() {
        super.refreshColors()
        detailLabel.textColor = DWBAccessibility.textSecondary
    }
}

// MARK: - Drop zone

/// The drag-and-drop overlay over the video stage (valid state only): a dashed `accentText` edge,
/// an `accentTint` fill, and a `backingHUD` card saying what will be added.
final class DropZoneView: NSView {
    private let dashedEdge = CAShapeLayer()
    private let card = HUDSurfaceView(backing: { DWBAccessibility.backingHUD })
    private let iconView = HUDText.symbol("plus", size: 24, tint: theme.accentText)
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var generation = 0

    private enum Metrics {
        static let inset: CGFloat = 12
        static let radius: CGFloat = 12
        static let cardPadding = NSSize(width: 22, height: 16)
        static let cardGap: CGFloat = 8
        static let icon: CGFloat = 24
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        alphaValue = 0
        isHidden = true

        dashedEdge.lineWidth = 2
        dashedEdge.lineDashPattern = [6, 4]
        layer?.addSublayer(dashedEdge)

        addSubview(card)
        card.alphaValue = 1
        card.isHidden = false
        card.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = DWBColor.textPrimary
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        card.addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = DWBAccessibility.textSecondary
        detailLabel.alignment = .center
        card.addSubview(detailLabel)

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        refreshColors()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(accessibilityOptionsChanged),
                                               name: DWBAccessibility.didChange,
                                               object: nil)
    }

    convenience init() { self.init(frame: .zero) }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @objc private func accessibilityOptionsChanged() { refreshColors() }

    private func refreshColors() {
        dashedEdge.strokeColor = theme.accentText.cgColor
        dashedEdge.fillColor = DWBAccessibility.accentTint.cgColor
        detailLabel.textColor = DWBAccessibility.textSecondary
        card.refreshColors()
    }

    override func layout() {
        super.layout()
        // The 2 pt stroke is centered on the path, so the path sits 1 pt inside the 12 pt inset.
        let path = bounds.insetBy(dx: Metrics.inset + 1, dy: Metrics.inset + 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dashedEdge.path = CGPath(roundedRect: path, cornerWidth: Metrics.radius, cornerHeight: Metrics.radius, transform: nil)
        CATransaction.commit()
        layoutCard()
    }

    private func layoutCard() {
        let titleSize = titleLabel.intrinsicContentSize
        let detailSize = detailLabel.intrinsicContentSize
        let contentWidth = max(Metrics.icon, ceil(titleSize.width), ceil(detailSize.width))
        let width = min(bounds.width * 0.8, contentWidth + Metrics.cardPadding.width * 2)
        let height = Metrics.cardPadding.height * 2 + Metrics.icon + Metrics.cardGap * 2
            + ceil(titleSize.height) + ceil(detailSize.height)
        card.frame = NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2,
                            width: width, height: height)
        let innerWidth = max(0, width - Metrics.cardPadding.width * 2)
        var y = height - Metrics.cardPadding.height - Metrics.icon
        iconView.frame = NSRect(x: (width - Metrics.icon) / 2, y: y, width: Metrics.icon, height: Metrics.icon)
        y -= Metrics.cardGap + ceil(titleSize.height)
        titleLabel.frame = NSRect(x: Metrics.cardPadding.width, y: y, width: innerWidth, height: ceil(titleSize.height))
        y -= Metrics.cardGap + ceil(detailSize.height)
        detailLabel.frame = NSRect(x: Metrics.cardPadding.width, y: y, width: innerWidth, height: ceil(detailSize.height))
    }

    func show(_ presentation: DropZonePresentation, over stage: NSRect) {
        frame = stage
        titleLabel.stringValue = presentation.title
        detailLabel.stringValue = presentation.detail
        setAccessibilityLabel("\(presentation.title). \(presentation.detail)")
        needsLayout = true
        layoutSubtreeIfNeeded()
        generation += 1
        isHidden = false
        let duration = DWBAccessibility.duration(DWBMotion.fade)
        if duration > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                self.animator().alphaValue = 1
            }
        } else {
            alphaValue = 1
        }
    }

    func hide() {
        generation += 1
        let hidden = generation
        let duration = DWBAccessibility.duration(DWBMotion.fade)
        guard duration > 0, !isHidden else {
            alphaValue = 0
            isHidden = true
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            self.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.generation == hidden else { return }
            self.isHidden = true
        }
    }
}
