import AppKit

// Settings > Shortcuts: a keyboard map, a toolbar (search and Restore Defaults…), the scope
// text, and the shortcut rows grouped by task. Hovering or focusing a row lights its keys on
// the map. Clicking a key opens the Edit shortcut sheet. Every key comes from
// `ShortcutCommandTable` and `ShortcutStore`, so the rows follow the user's changes.

// MARK: - Page

final class ShortcutsPageView: NSView, NSTextFieldDelegate {

    private let mapView = ShortcutsKeyboardMapView()
    private let searchPill = ShortcutsSearchPill()
    private let restoreButton = DWBButton(title: ShortcutsPresentation.restoreDefaultsTitle, style: .neutral)
    private let toolbar = ShortcutsToolbarView()
    private let scopeLabel = DWBLabel(ShortcutsPresentation.scopeText, size: 11, tone: .tertiary)
    private let noMatchesLabel = DWBLabel(ShortcutsPresentation.noMatchesText, size: 12, tone: .tertiary)
    private let groupsStack = NSStackView()
    private let stack = NSStackView()
    private let store: ShortcutStore
    private var shortcutObserver: NSObjectProtocol?
    /// The command whose first key takes keyboard focus after the next rebuild (after an edit).
    private var commandToRefocus: ShortcutCommandID?

    init(store: ShortcutStore = .shared) {
        self.store = store
        super.init(frame: .zero)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        mapView.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        groupsStack.orientation = .vertical
        groupsStack.alignment = .leading
        groupsStack.spacing = 18
        groupsStack.translatesAutoresizingMaskIntoConstraints = false

        toolbar.install(search: searchPill, button: restoreButton)
        restoreButton.target = self
        restoreButton.action = #selector(restoreDefaultsTapped)
        restoreButton.setAccessibilityHelp("Resets every keyboard shortcut in dwb skim to its default.")

        scopeLabel.lineBreakMode = .byWordWrapping
        noMatchesLabel.setAccessibilityLabel(ShortcutsPresentation.noMatchesText)

        stack.addArrangedSubview(mapView)
        stack.addArrangedSubview(toolbar)
        stack.addArrangedSubview(scopeLabel)
        stack.addArrangedSubview(groupsStack)
        stack.setCustomSpacing(6, after: toolbar)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            toolbar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            groupsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        searchPill.field.delegate = self
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: .shortcutsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit {
        if let shortcutObserver { NotificationCenter.default.removeObserver(shortcutObserver) }
    }

    private var query: String { searchPill.field.stringValue }

    func controlTextDidChange(_ obj: Notification) {
        rebuildGroups()
    }

    /// Rebuilds the map tones and the rows from the keys in use now. The search text stays.
    private func reload() {
        mapView.tones = ShortcutsPresentation.mapTones(in: ShortcutsPresentation.groups(store: store))
        rebuildGroups()
    }

    private func rebuildGroups() {
        for view in groupsStack.arrangedSubviews {
            groupsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        mapView.highlightedKeys = []
        let groups = ShortcutsPresentation.filtered(ShortcutsPresentation.groups(store: store), query: query)
        if groups.isEmpty {
            groupsStack.addArrangedSubview(noMatchesLabel)
        }
        var refocus: NSView?
        for group in groups {
            let section = makeSection(group)
            groupsStack.addArrangedSubview(section.view)
            section.view.widthAnchor.constraint(equalTo: groupsStack.widthAnchor).isActive = true
            if refocus == nil, let id = commandToRefocus, let row = section.rows.first(where: { $0.row.commandID == id }) {
                refocus = row.preferredFocusView
            }
        }
        if let refocus {
            commandToRefocus = nil
            DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(refocus) }
        }
    }

    private func makeSection(_ group: ShortcutGroup) -> (view: NSView, rows: [ShortcutRowView]) {
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

        var rowViews: [ShortcutRowView] = []
        for row in group.rows {
            let view = ShortcutRowView(row: row)
            view.onHighlightChange = { [weak self] highlighted in
                self?.mapView.highlightedKeys = highlighted ? Set(row.mapKeys) : []
            }
            view.onEdit = { [weak self] key in self?.presentEditor(for: row.commandID, key: key) }
            rows.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            rowViews.append(view)
        }
        rows.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return (section, rowViews)
    }

    // MARK: Actions

    private func presentEditor(for id: ShortcutCommandID, key: ShortcutKey?) {
        guard let window else { return }
        commandToRefocus = id
        let editor = ShortcutEditorSheetController(commandID: id, editingKey: key, store: store)
        // A saved or removed key rebuilds the rows and returns focus to this action's first key;
        // a cancelled sheet leaves focus where it was.
        editor.onCancelled = { [weak self] in self?.commandToRefocus = nil }
        editor.present(on: window)
    }

    @objc private func restoreDefaultsTapped() {
        guard let window else { return }
        let store = store
        ConfirmSheetController(title: ShortcutsPresentation.restoreConfirmTitle,
                               message: ShortcutsPresentation.restoreConfirmMessage,
                               actionTitle: ShortcutsPresentation.restoreConfirmAction) {
            store.restoreDefaults()
        }.present(on: window)
    }
}

// MARK: - Toolbar

/// The search pill and the Restore Defaults… button on one line; the button wraps below the
/// field when the page is too narrow for both.
private final class ShortcutsToolbarView: NSView {
    private var search: NSView?
    private var button: NSView?
    private var isWrapped = false
    private let gap: CGFloat = 8

    func install(search: NSView, button: NSView) {
        self.search = search
        self.button = button
        for view in [search, button] {
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
        }
    }

    private var searchSize: NSSize { search?.intrinsicContentSize ?? .zero }
    private var buttonSize: NSSize { button?.fittingSize ?? .zero }

    override var intrinsicContentSize: NSSize {
        let height = isWrapped ? searchSize.height + gap + buttonSize.height : max(searchSize.height, buttonSize.height)
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func layout() {
        super.layout()
        guard let search, let button else { return }
        let wrap = bounds.width < searchSize.width + gap + buttonSize.width
        if wrap != isWrapped {
            isWrapped = wrap
            invalidateIntrinsicContentSize()
        }
        let height = bounds.height
        let searchWidth = min(searchSize.width, bounds.width)
        if wrap {
            search.frame = NSRect(x: 0, y: height - searchSize.height, width: searchWidth, height: searchSize.height)
            button.frame = NSRect(x: 0, y: 0, width: min(buttonSize.width, bounds.width), height: buttonSize.height)
        } else {
            search.frame = NSRect(x: 0, y: floor((height - searchSize.height) / 2), width: searchWidth, height: searchSize.height)
            button.frame = NSRect(x: searchWidth + gap, y: floor((height - buttonSize.height) / 2),
                                  width: buttonSize.width, height: buttonSize.height)
        }
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

/// A shortcut row: at least 30 pt tall, a `gridLine` bottom edge, the action name with its
/// context text under it, and the keys at the end as key caps. An editable action's keys are
/// buttons that open the editor; a reference row's caps only show. A row lights its keys on
/// the map while it is hovered or holds keyboard focus.
private final class ShortcutRowView: NSView {
    var onHighlightChange: ((Bool) -> Void)?
    var onEdit: ((ShortcutKey?) -> Void)?

    let row: ShortcutRow
    private let titleLabel: DWBLabel
    private let contextLabel: DWBLabel?
    private let capsStack = NSStackView()
    private var caps: [ShortcutKeyCapControl] = []
    private var isHovering = false {
        didSet { needsDisplay = true; updateHighlight() }
    }
    private var focusCount = 0 {
        didSet { updateHighlight() }
    }
    private var isRowFocused = false {
        didSet { needsDisplay = true; updateHighlight() }
    }
    private var trackingAreaReference: NSTrackingArea?

    init(row: ShortcutRow) {
        self.row = row
        titleLabel = DWBLabel(row.title, size: 13, tone: .primary)
        if let text = row.contextText {
            let label = DWBLabel(text, size: 11, tone: .tertiary)
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            label.cell?.wraps = true
            label.cell?.isScrollable = false
            contextLabel = label
        } else {
            contextLabel = nil
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0
        titleLabel.cell?.wraps = true
        titleLabel.cell?.isScrollable = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [titleLabel] + (contextLabel.map { [$0] } ?? []))
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(textStack)
        self.textStack = textStack

        capsStack.orientation = .horizontal
        capsStack.spacing = 4
        capsStack.translatesAutoresizingMaskIntoConstraints = false
        buildCaps()
        capsStack.setContentHuggingPriority(.required, for: .horizontal)
        capsStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(capsStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            capsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            capsStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: capsStack.leadingAnchor, constant: -12),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityLabel(row.accessibilityLabel)
        if let text = row.contextText { setAccessibilityHelp(text) }
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private var textStack: NSStackView!

    /// The control that takes focus after an edit: the row's first key, or the row itself.
    var preferredFocusView: NSView? { caps.first(where: { $0.isInteractive }) ?? (acceptsFirstResponder ? self : nil) }

    private func buildCaps() {
        if let gesture = row.gestureText {
            add(ShortcutKeyCapControl(kind: .reference(gesture), tone: row.tone, title: row.title))
        } else if !row.isEditable {
            for key in row.keys {
                add(ShortcutKeyCapControl(kind: .reference(key.capText), tone: row.tone, title: row.title, spoken: key.spokenText))
            }
        } else if row.keys.isEmpty {
            let cap = ShortcutKeyCapControl(kind: .unassigned, tone: row.tone, title: row.title)
            cap.onActivate = { [weak self] in self?.onEdit?(nil) }
            add(cap)
        } else {
            for key in row.keys {
                let cap = ShortcutKeyCapControl(kind: .key(key.capText), tone: row.tone, title: row.title, spoken: key.spokenText)
                cap.onActivate = { [weak self] in self?.onEdit?(key) }
                add(cap)
            }
            let plus = ShortcutKeyCapControl(kind: .add, tone: row.tone, title: row.title)
            plus.onActivate = { [weak self] in self?.onEdit?(nil) }
            add(plus)
        }
    }

    private func add(_ cap: ShortcutKeyCapControl) {
        cap.onFocusChange = { [weak self] focused in
            guard let self else { return }
            self.focusCount += focused ? 1 : -1
        }
        caps.append(cap)
        capsStack.addArrangedSubview(cap)
    }

    private func updateHighlight() {
        onHighlightChange?(isHovering || focusCount > 0 || isRowFocused)
    }

    // A reference row has nothing to click, so keyboard focus lands on the row itself.
    override var acceptsFirstResponder: Bool { !row.isEditable }

    override func becomeFirstResponder() -> Bool {
        isRowFocused = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRowFocused = false
        return true
    }

    override func layout() {
        // Wrap the title and the context text to the width the caps leave free.
        let free = max(60, bounds.width - 8 - 12 - 8 - capsStack.fittingSize.width)
        if titleLabel.preferredMaxLayoutWidth != free || contextLabel?.preferredMaxLayoutWidth != free {
            titleLabel.preferredMaxLayoutWidth = free
            contextLabel?.preferredMaxLayoutWidth = free
        }
        super.layout()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovering {
            DWBColor.overlayHover.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: DWBMetrics.radiusControl,
                         yRadius: DWBMetrics.radiusControl).fill()
        }
        DWBColor.gridLine.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        if isRowFocused {
            let width = DWBAccessibility.focusWidth
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2),
                                    xRadius: DWBMetrics.radiusControl, yRadius: DWBMetrics.radiusControl)
            ring.lineWidth = width
            DWBAccessibility.focusRing.setStroke()
            ring.stroke()
        }
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
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }
}

/// A key cap in a row: min width 22, 20 pt tall, radius 4, monospaced 11 pt medium. An
/// editable action's caps are buttons: Return or Space on a focused one, or a click, opens the
/// editor. `Unassigned` and the add (+) cap use the same cap.
private final class ShortcutKeyCapControl: NSControl {
    enum Kind: Equatable {
        case key(String)
        case reference(String)
        case unassigned
        case add
    }

    let kind: Kind
    private let tone: ShortcutRow.Tone
    var onActivate: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    private var isHovering = false {
        didSet { needsDisplay = true }
    }
    private var isPressed = false {
        didSet { needsDisplay = true }
    }
    private var trackingAreaReference: NSTrackingArea?

    var isInteractive: Bool {
        if case .reference = kind { return false }
        return true
    }

    private var text: String {
        switch kind {
        case .key(let text), .reference(let text): return text
        case .unassigned: return ShortcutRow.unassignedText
        case .add: return ""
        }
    }

    init(kind: Kind, tone: ShortcutRow.Tone, title: String, spoken: String? = nil) {
        self.kind = kind
        self.tone = tone
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        focusRingType = .none
        switch kind {
        case .reference:
            setAccessibilityElement(false)
        case .key:
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("\(spoken ?? text), shortcut for \(title)")
            setAccessibilityHelp("Opens the shortcut editor.")
        case .unassigned:
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Unassigned, shortcut for \(title)")
            setAccessibilityHelp("Opens the shortcut editor to add a key.")
        case .add:
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Add another shortcut for \(title)")
            setAccessibilityHelp("Opens the shortcut editor to add a key.")
        }
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private var attributes: [NSAttributedString.Key: Any] {
        let color: NSColor = kind == .unassigned ? DWBAccessibility.textTertiary : DWBColor.textPrimary
        return [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: color]
    }

    override var intrinsicContentSize: NSSize {
        if kind == .add { return NSSize(width: 22, height: 20) }
        let width = ceil((text as NSString).size(withAttributes: attributes).width)
        return NSSize(width: max(22, width + 12), height: 20)
    }

    override var acceptsFirstResponder: Bool { isInteractive }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isInteractive }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        onFocusChange?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        onFocusChange?(false)
        return true
    }

    override func keyDown(with event: NSEvent) {
        // Return, keypad Enter, and Space press the focused key.
        if isInteractive, [36, 76, 49].contains(event.keyCode) {
            onActivate?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive else { return super.mouseDown(with: event) }
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isInteractive else { return super.mouseUp(with: event) }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if inside { onActivate?() }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isInteractive else { return false }
        onActivate?()
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        guard isInteractive else { return }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusKey, yRadius: DWBMetrics.radiusKey)
        DWBColor.surfaceElevated.setFill()
        path.fill()
        if isInteractive, isHovering || isPressed {
            (isPressed ? DWBColor.overlayPressed : DWBColor.overlayHover).setFill()
            path.fill()
        }
        let edge: NSColor
        switch tone {
        case .accent: edge = DWBColor.borderStrong
        case .markerPrimary: edge = theme.markerPrimary
        case .markerSecondary: edge = theme.markerSecondary
        }
        edge.setStroke()
        path.lineWidth = 1
        path.stroke()

        if kind == .add {
            if let image = NSImage.dwbSymbol("plus", pointSize: 10, weight: .semibold, color: DWBAccessibility.textSecondary) {
                image.draw(in: NSRect(x: floor((bounds.width - image.size.width) / 2),
                                      y: floor((bounds.height - image.size.height) / 2),
                                      width: image.size.width, height: image.size.height))
            }
        } else {
            let measured = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: floor((bounds.width - measured.width) / 2),
                                                y: floor((bounds.height - measured.height) / 2)),
                                    withAttributes: attributes)
        }

        if isInteractive, window?.firstResponder === self {
            let width = DWBAccessibility.focusWidth
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: -width / 2, dy: -width / 2),
                                    xRadius: DWBMetrics.radiusKey + width / 2, yRadius: DWBMetrics.radiusKey + width / 2)
            ring.lineWidth = width
            DWBAccessibility.focusRing.setStroke()
            ring.stroke()
        }
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
