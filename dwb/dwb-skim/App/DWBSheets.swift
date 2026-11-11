import AppKit

// Design-system sheets (section 9.3 and the destructive confirm in section 5).
//
// Each sheet is a borderless panel presented with `beginSheet`, so it hangs under the
// title bar. The window's content is dimmed with black at 45% while a sheet is up.
// The rename and batch sheets are 400 and 420 pt wide, the confirm sheet 380 pt, all
// `surfaceElevated` with a 1 pt `border` and a 10 pt bottom radius.

// MARK: - Panel and chrome

final class DWBSheetPanel: NSPanel {
    /// Called for Escape (and `cancelOperation`).
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// The sheet body: `surfaceElevated`, a 1 pt `border` on the left, right and bottom,
/// and a 10 pt radius on the bottom corners. Content goes in `stack`.
final class DWBSheetChromeView: NSView {
    let stack = NSStackView()
    private let width: CGFloat

    init(width: CGFloat) {
        self.width = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func draw(_ dirtyRect: NSRect) {
        let radius = DWBMetrics.radiusCard
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        outline.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
        outline.appendArc(withCenter: NSPoint(x: rect.minX + radius, y: rect.minY + radius),
                          radius: radius, startAngle: 180, endAngle: 270)
        outline.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
        outline.appendArc(withCenter: NSPoint(x: rect.maxX - radius, y: rect.minY + radius),
                          radius: radius, startAngle: 270, endAngle: 360)
        outline.line(to: NSPoint(x: rect.maxX, y: rect.maxY))

        let filled = outline.copy() as! NSBezierPath
        filled.close()
        DWBColor.surfaceElevated.setFill()
        filled.fill()
        DWBAccessibility.border.setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }

    @objc private func accessibilityDidChange() {
        needsDisplay = true
    }
}

// MARK: - Stage dim

private final class DWBStageDimView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        autoresizingMask = [.width, .height]
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func mouseDown(with event: NSEvent) {}
}

// MARK: - Presenter

enum DWBSheet {
    /// Presents `panel` under `window`'s title bar, dimming the window's content.
    static func present(_ panel: DWBSheetPanel,
                        on window: NSWindow,
                        completion: @escaping (NSApplication.ModalResponse) -> Void) {
        var dim: DWBStageDimView?
        if let content = window.contentView {
            let view = DWBStageDimView(frame: content.bounds)
            content.addSubview(view, positioned: .above, relativeTo: nil)
            let duration = DWBAccessibility.duration(DWBMotion.fade)
            if duration > 0 {
                view.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    view.animator().alphaValue = 1
                }
            }
            dim = view
        }
        window.beginSheet(panel) { response in
            dim?.removeFromSuperview()
            completion(response)
        }
    }

    /// Ends the sheet. The completion given to `present` runs with `response`.
    static func dismiss(_ panel: DWBSheetPanel, response: NSApplication.ModalResponse) {
        guard let parent = panel.sheetParent else {
            panel.orderOut(nil)
            return
        }
        parent.endSheet(panel, returnCode: response)
        panel.orderOut(nil)
    }

    /// A borderless, transparent panel sized to `chrome`.
    static func makePanel(chrome: DWBSheetChromeView) -> DWBSheetPanel {
        chrome.layoutSubtreeIfNeeded()
        let size = NSSize(width: chrome.frame.width, height: ceil(chrome.fittingSize.height))
        let panel = DWBSheetPanel(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.borderless],
                                  backing: .buffered,
                                  defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        chrome.frame = NSRect(origin: .zero, size: size)
        chrome.autoresizingMask = [.width, .height]
        panel.contentView = chrome
        return panel
    }

    /// A wrapping label for sheet text.
    static func wrappingLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                              tone: DWBLabel.Tone, width: CGFloat) -> DWBLabel {
        let label = DWBLabel(text, size: size, weight: weight, tone: tone)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        label.preferredMaxLayoutWidth = width
        return label
    }

    /// A horizontal row that right-aligns `buttons`.
    static func buttonRow(_ buttons: [NSView]) -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [spacer] + buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }
}

// MARK: - Rename sheet

/// The single-file rename sheet (design system `RenameSheet`).
final class RenameSheetController: NSObject, NSTextFieldDelegate {
    static let width: CGFloat = DWBMetrics.renameSheetWidth

    private let original: RenameFilenameParts
    private let nameExists: (String) -> Bool
    private let onRename: (String) -> Void

    /// Keeps the controller alive while its sheet is up.
    private var retainedSelf: AnyObject?
    private let panel: DWBSheetPanel
    private let fieldChrome: DWBFieldChrome
    private let messageIcon = NSImageView()
    private let messageLabel = DWBLabel("", size: 11, tone: .error)
    private let renameButton: DWBButton
    private let cancelButton: DWBButton

    /// - Parameters:
    ///   - filename: The file's current complete name.
    ///   - caption: The sentence under the title.
    ///   - nameExists: Whether a complete name is already taken in the file's folder.
    ///   - onRename: Receives the complete new filename (stem plus the protected extension).
    init(filename: String,
         caption: String,
         nameExists: @escaping (String) -> Bool,
         onRename: @escaping (String) -> Void) {
        original = RenameFilenameParts(filename: filename)
        self.nameExists = nameExists
        self.onRename = onRename

        let chrome = DWBSheetChromeView(width: Self.width)
        let inner = Self.width - 40

        let title = DWBLabel("Rename File", size: 13.5, weight: .semibold, tone: .primary)
        let captionLabel = DWBSheet.wrappingLabel(caption, size: 11.5, tone: .secondary, width: inner)

        let field = DWBInlineTextField()
        fieldChrome = DWBFieldChrome(field: field, width: nil, height: DWBMetrics.sheetFieldHeight, fontSize: 12)
        fieldChrome.translatesAutoresizingMaskIntoConstraints = false
        field.stringValue = original.stem
        field.setAccessibilityLabel("File name")
        field.placeholderString = nil
        if !original.extensionSuffix.isEmpty {
            fieldChrome.trailingAccessory = RenameExtensionToken(extensionSuffix: original.extensionSuffix)
        }

        messageIcon.image = NSImage.dwbSymbol("exclamationmark.circle", pointSize: 11, color: DWBColor.errorText)
        messageIcon.translatesAutoresizingMaskIntoConstraints = false
        let message = NSStackView(views: [messageIcon, messageLabel])
        message.orientation = .horizontal
        message.alignment = .centerY
        message.spacing = 5
        message.translatesAutoresizingMaskIntoConstraints = false
        let messageContainer = NSView()
        messageContainer.translatesAutoresizingMaskIntoConstraints = false
        messageContainer.addSubview(message)
        NSLayoutConstraint.activate([
            messageContainer.heightAnchor.constraint(equalToConstant: 15),
            message.leadingAnchor.constraint(equalTo: messageContainer.leadingAnchor),
            message.centerYAnchor.constraint(equalTo: messageContainer.centerYAnchor),
            message.trailingAnchor.constraint(lessThanOrEqualTo: messageContainer.trailingAnchor),
        ])

        cancelButton = DWBButton(title: "Cancel", style: .neutral)
        renameButton = DWBButton(title: "Rename", style: .primary)
        let buttons = DWBSheet.buttonRow([cancelButton, renameButton])

        chrome.stack.addArrangedSubview(title)
        chrome.stack.addArrangedSubview(captionLabel)
        chrome.stack.addArrangedSubview(fieldChrome)
        chrome.stack.addArrangedSubview(messageContainer)
        chrome.stack.addArrangedSubview(buttons)
        chrome.stack.setCustomSpacing(8, after: captionLabel)
        chrome.stack.setCustomSpacing(6, after: fieldChrome)
        chrome.stack.setCustomSpacing(8, after: messageContainer)
        for view in [fieldChrome, messageContainer, buttons] {
            view.widthAnchor.constraint(equalTo: chrome.stack.widthAnchor).isActive = true
        }
        fieldChrome.heightAnchor.constraint(equalToConstant: DWBMetrics.sheetFieldHeight).isActive = true

        panel = DWBSheet.makePanel(chrome: chrome)
        super.init()

        field.delegate = self
        field.target = self
        field.action = #selector(submit)
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        renameButton.target = self
        renameButton.action = #selector(submit)
        renameButton.keyEquivalent = "\r"
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.initialFirstResponder = field
        revalidate()
    }

    /// Shows the sheet under `window`. The stem starts selected.
    func present(on window: NSWindow) {
        retainedSelf = self
        DWBSheet.present(panel, on: window) { [weak self] _ in self?.retainedSelf = nil }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.makeFirstResponder(self.fieldChrome.field)
            self.fieldChrome.field.selectText(nil)
        }
    }

    private func revalidate() {
        let validation = RenameNameValidation.validate(typedStem: fieldChrome.field.stringValue,
                                                       original: original,
                                                       nameExists: nameExists)
        renameButton.isEnabled = validation.allowsRename
        fieldChrome.isError = validation.isError
        messageLabel.stringValue = validation.inlineMessage ?? ""
        messageIcon.isHidden = !validation.isError
        messageLabel.isHidden = !validation.isError
    }

    func controlTextDidChange(_ obj: Notification) {
        revalidate()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            submit()
            return true
        default:
            return false
        }
    }

    @objc private func cancel() {
        DWBSheet.dismiss(panel, response: .cancel)
    }

    @objc private func submit() {
        let typed = fieldChrome.field.stringValue
        let validation = RenameNameValidation.validate(typedStem: typed, original: original, nameExists: nameExists)
        guard validation.allowsRename else { return }
        let complete = RenameNameValidation.completeFilename(typedStem: typed, original: original)
        DWBSheet.dismiss(panel, response: .OK)
        onRename(complete)
    }
}

/// The read-only extension token at the end of the stem field: `surface` fill, a 1 pt
/// `border` on its left side, monospaced 11 pt `textTertiary`, and `lock.fill` at 8 pt.
private final class RenameExtensionToken: NSView {
    private let text: String
    private let gap: CGFloat = 4
    private let padding: CGFloat = 8

    init(extensionSuffix: String) {
        text = extensionSuffix
        super.init(frame: .zero)
        toolTip = "The extension is protected"
        setAccessibilityLabel("Extension \(extensionSuffix), protected")
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
         .foregroundColor: DWBAccessibility.textTertiary]
    }

    override var fittingSize: NSSize {
        NSSize(width: ceil((text as NSString).size(withAttributes: attributes).width) + padding * 2 + gap + 8,
               height: DWBMetrics.sheetFieldHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        DWBColor.surface.setFill()
        bounds.fill()
        DWBAccessibility.border.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()

        var x = padding
        if let lock = NSImage.dwbSymbol("lock.fill", pointSize: 8, color: DWBColor.textDisabled) {
            lock.draw(in: NSRect(x: x, y: floor((bounds.height - lock.size.height) / 2),
                                 width: lock.size.width, height: lock.size.height))
            x += ceil(lock.size.width) + gap
        }
        let measured = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: x, y: floor((bounds.height - measured.height) / 2)),
                                withAttributes: attributes)
    }
}

// MARK: - Batch rename sheet

/// The multi-file marker rename confirmation (design system `BatchRenameSheet`).
final class BatchRenameSheetController: NSObject {
    static let width: CGFloat = DWBMetrics.batchSheetWidth

    /// Keeps the controller alive while its sheet is up.
    private var retainedSelf: AnyObject?
    private let panel: DWBSheetPanel
    private let onConfirm: () -> Void
    private let cancelButton: DWBButton
    private let confirmButton: DWBButton

    /// - Parameters:
    ///   - prefix: The prefix being applied.
    ///   - prefixColor: The prefix's marker color.
    init(preview: BatchRenamePreview,
         prefix: String,
         prefixColor: NSColor,
         onConfirm: @escaping () -> Void) {
        self.onConfirm = onConfirm
        let chrome = DWBSheetChromeView(width: Self.width)
        let inner = Self.width - 40

        let title = DWBLabel(preview.title, size: 13.5, weight: .semibold, tone: .primary)

        let caption = BatchRenameSheetController.captionText(count: preview.totalCount,
                                                             prefix: prefix,
                                                             color: prefixColor)
        let captionLabel = DWBSheet.wrappingLabel("", size: 11.5, tone: .secondary, width: inner)
        captionLabel.attributedStringValue = caption

        let well = BatchRenameWell(preview: preview, prefix: prefix, prefixColor: prefixColor)
        well.translatesAutoresizingMaskIntoConstraints = false

        cancelButton = DWBButton(title: "Cancel", style: .neutral)
        confirmButton = DWBButton(title: preview.confirmTitle, style: .primary)
        let buttons = DWBSheet.buttonRow([cancelButton, confirmButton])

        chrome.stack.addArrangedSubview(title)
        chrome.stack.addArrangedSubview(captionLabel)
        chrome.stack.addArrangedSubview(well)
        chrome.stack.addArrangedSubview(buttons)
        chrome.stack.setCustomSpacing(8, after: captionLabel)
        chrome.stack.setCustomSpacing(10, after: well)
        well.widthAnchor.constraint(equalTo: chrome.stack.widthAnchor).isActive = true
        buttons.widthAnchor.constraint(equalTo: chrome.stack.widthAnchor).isActive = true

        panel = DWBSheet.makePanel(chrome: chrome)
        super.init()

        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        confirmButton.target = self
        confirmButton.action = #selector(confirm)
        confirmButton.keyEquivalent = "\r"
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.initialFirstResponder = confirmButton
        chrome.setAccessibilityLabel(preview.title)
    }

    func present(on window: NSWindow) {
        retainedSelf = self
        DWBSheet.present(panel, on: window) { [weak self] _ in self?.retainedSelf = nil }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.makeFirstResponder(self.confirmButton)
        }
    }

    private static func captionText(count: Int, prefix: String, color: NSColor) -> NSAttributedString {
        let caption = BatchRenamePreview.caption(prefix: prefix, count: count)
        let result = NSMutableAttributedString(string: caption.text, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: DWBAccessibility.textSecondary,
        ])
        result.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: color,
        ], range: caption.prefixRange)
        return result
    }

    @objc private func cancel() {
        DWBSheet.dismiss(panel, response: .cancel)
    }

    @objc private func confirm() {
        DWBSheet.dismiss(panel, response: .OK)
        onConfirm()
    }
}

/// The sunken well of "old › new" rows: 1 pt `border`, radius 6.
private final class BatchRenameWell: NSView {
    private let rowHeight: CGFloat = 20

    init(preview: BatchRenamePreview, prefix: String, prefixColor: NSColor) {
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        for row in preview.rows {
            let view = makeRow(row, prefix: prefix, prefixColor: prefixColor)
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        if let more = preview.moreText {
            let label = DWBLabel(more, size: 11, tone: .tertiary)
            label.translatesAutoresizingMaskIntoConstraints = false
            let holder = NSView()
            holder.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(label)
            NSLayoutConstraint.activate([
                holder.heightAnchor.constraint(equalToConstant: rowHeight),
                label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 10),
                label.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            ])
            stack.addArrangedSubview(holder)
            holder.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        setAccessibilityRole(.list)
        setAccessibilityLabel(preview.rows.map(\.text).joined(separator: ", "))
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private func makeRow(_ row: BatchRenamePreview.Row, prefix: String, prefixColor: NSColor) -> NSView {
        let old = DWBLabel(row.oldName, size: 11.5, tone: .tertiary)
        old.lineBreakMode = .byTruncatingMiddle

        let new = DWBLabel("", size: 11.5, tone: .primary)
        new.lineBreakMode = .byTruncatingMiddle
        let attributed = NSMutableAttributedString(string: row.newName, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: DWBColor.textPrimary,
        ])
        if !prefix.isEmpty, row.newName.hasPrefix(prefix) {
            attributed.addAttributes([
                .font: NSFont.systemFont(ofSize: 11.5, weight: .bold),
                .foregroundColor: prefixColor,
            ], range: NSRange(location: 0, length: (prefix as NSString).length))
        }
        new.attributedStringValue = attributed

        let chevron = NSImageView()
        chevron.image = NSImage.dwbSymbol("chevron.right", pointSize: 10, color: DWBColor.textDisabled)
        chevron.setAccessibilityElement(false)

        for view in [old, chevron, new] { view.translatesAutoresizingMaskIntoConstraints = false }
        old.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        new.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        [old, chevron, new].forEach(holder.addSubview)
        // Three columns: the chevron sits at the row's midline so every row lines up.
        NSLayoutConstraint.activate([
            holder.heightAnchor.constraint(equalToConstant: rowHeight),
            old.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 10),
            old.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            chevron.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            chevron.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 8),
            old.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),
            new.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 8),
            new.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            new.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor, constant: -10),
        ])
        holder.setAccessibilityLabel(row.text)
        return holder
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusControl, yRadius: DWBMetrics.radiusControl)
        DWBColor.surfaceSunken.setFill()
        path.fill()
        DWBAccessibility.border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    @objc private func accessibilityDidChange() {
        needsDisplay = true
    }
}

// MARK: - Confirm sheet

/// The destructive confirmation (design system `ConfirmDialog`): Cancel is the default
/// and focused button; the destructive action is solid `errorText`.
final class ConfirmSheetController: NSObject {
    static let width: CGFloat = 380

    /// Keeps the controller alive while its sheet is up.
    private var retainedSelf: AnyObject?
    private let panel: DWBSheetPanel
    private let onConfirm: () -> Void
    private let cancelButton: DWBButton
    private let confirmButton: DWBButton

    init(title: String, message: String, actionTitle: String, onConfirm: @escaping () -> Void) {
        self.onConfirm = onConfirm
        let chrome = DWBSheetChromeView(width: Self.width)
        let inner = Self.width - 40

        let icon = NSImageView()
        icon.image = NSImage.dwbSymbol("exclamationmark.triangle.fill", pointSize: 18, color: DWBColor.errorText)
        icon.setAccessibilityElement(false)
        let titleLabel = DWBSheet.wrappingLabel(title, size: 13.5, weight: .semibold, tone: .primary, width: inner - 28)
        let header = NSStackView(views: [icon, titleLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        let messageLabel = DWBSheet.wrappingLabel(message, size: 11.5, tone: .secondary, width: inner)

        cancelButton = DWBButton(title: "Cancel", style: .neutral)
        confirmButton = DWBButton(title: actionTitle, style: .destructive)
        let buttons = DWBSheet.buttonRow([cancelButton, confirmButton])

        chrome.stack.addArrangedSubview(header)
        chrome.stack.addArrangedSubview(messageLabel)
        chrome.stack.addArrangedSubview(buttons)
        chrome.stack.spacing = 10
        chrome.stack.setCustomSpacing(18, after: messageLabel)
        buttons.widthAnchor.constraint(equalTo: chrome.stack.widthAnchor).isActive = true

        panel = DWBSheet.makePanel(chrome: chrome)
        super.init()

        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        confirmButton.target = self
        confirmButton.action = #selector(confirm)
        // Cancel answers Return; the destructive action needs a deliberate click or Space.
        cancelButton.keyEquivalent = "\r"
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.initialFirstResponder = cancelButton
        chrome.setAccessibilityLabel(title)
        chrome.setAccessibilityRole(.group)
    }

    func present(on window: NSWindow) {
        retainedSelf = self
        DWBSheet.present(panel, on: window) { [weak self] _ in self?.retainedSelf = nil }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.makeFirstResponder(self.cancelButton)
        }
    }

    @objc private func cancel() {
        DWBSheet.dismiss(panel, response: .cancel)
    }

    @objc private func confirm() {
        DWBSheet.dismiss(panel, response: .OK)
        onConfirm()
    }
}
