import AppKit

// The Edit shortcut sheet (design system 9.3 sheet chrome): the app and action name, a
// recorder, an inline message, and Remove, Cancel, Save. Built from the rename sheet's
// parts; it adds no new visual value.

// MARK: - Recorder

/// A field that captures the next key press with its modifiers. While it is first responder it
/// takes every key, including ⌘ combinations, before the menu bar sees them, so a recorded key
/// runs no command. Escape and Tab are not recordable: Escape cancels the sheet and Tab moves
/// keyboard focus on.
final class ShortcutRecorderView: NSView {
    static let label = "Press a key or key combination"

    var onRecord: ((ShortcutKey) -> Void)?
    var onEscape: (() -> Void)?
    var onReturn: (() -> Void)?

    /// The key shown. `nil` shows the placeholder.
    var recordedKey: ShortcutKey? {
        didSet {
            setAccessibilityValue(recordedKey.map { $0.isModifierOnly ? "\($0.spokenText), modifier only" : $0.spokenText } ?? "No key recorded")
            needsDisplay = true
        }
    }

    /// Draws the error edge and ring, as the rename sheet's field does.
    var isError = false {
        didSet { needsDisplay = true }
    }

    private var isFocused = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.textField)
        setAccessibilityLabel(Self.label)
        setAccessibilityHelp("Press the keys you want to use. Escape cancels. Tab moves to the next control.")
        setAccessibilityValue("No key recorded")
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: DWBMetrics.sheetFieldHeight) }

    override func becomeFirstResponder() -> Bool {
        isFocused = true
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isFocused = false
        needsDisplay = true
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    // ⌘ combinations reach the key window's views before the main menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self else { return false }
        if [36, 48, 53].contains(event.keyCode) { return false }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = ShortcutModifiers(eventFlags: event.modifierFlags)
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        if event.keyCode == 36 {
            onReturn?()
            return
        }
        if event.keyCode == 48 {
            if modifiers.contains(.shift) { window?.selectPreviousKeyView(nil) } else { window?.selectNextKeyView(nil) }
            return
        }
        record(event)
    }

    override func keyUp(with event: NSEvent) {}

    /// A modifier pressed alone is shown, and is not a valid shortcut.
    override func flagsChanged(with event: NSEvent) {
        let modifiers = ShortcutModifiers(eventFlags: event.modifierFlags)
        guard !modifiers.isEmpty else { return }
        let key = ShortcutKey(modifiers: modifiers, key: "")
        recordedKey = key
        onRecord?(key)
    }

    private func record(_ event: NSEvent) {
        let modifiers = ShortcutModifiers(eventFlags: event.modifierFlags)
        let base = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers
        guard let key = ShortcutKey.recorded(keyCode: event.keyCode, characters: base, modifiers: modifiers) else { return }
        recordedKey = key
        onRecord?(key)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 5
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        DWBColor.surfaceSunken.setFill()
        path.fill()
        (isError ? DWBColor.errorText : DWBColor.borderStrong).setStroke()
        path.lineWidth = 1
        path.stroke()
        if isFocused {
            let width = DWBAccessibility.focusWidth
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2), xRadius: radius, yRadius: radius)
            ring.lineWidth = width
            (isError ? DWBColor.errorFill : DWBAccessibility.focusRing).setStroke()
            ring.stroke()
        }

        let text: String
        let attributes: [NSAttributedString.Key: Any]
        if let recordedKey {
            text = recordedKey.capText
            attributes = [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                          .foregroundColor: DWBColor.textPrimary]
        } else {
            text = Self.label
            attributes = [.font: NSFont.systemFont(ofSize: 12),
                          .foregroundColor: DWBAccessibility.textTertiary]
        }
        let measured = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: 7, y: floor((bounds.height - measured.height) / 2)),
                                withAttributes: attributes)
    }

    @objc private func accessibilityDidChange() {
        needsDisplay = true
    }
}

// MARK: - Sheet

final class ShortcutEditorSheetController: NSObject {
    static let width: CGFloat = DWBMetrics.renameSheetWidth

    private let commandID: ShortcutCommandID
    private let editingKey: ShortcutKey?
    private let store: ShortcutStore

    /// Keeps the controller alive while its sheet is up.
    private var retainedSelf: AnyObject?
    private let panel: DWBSheetPanel
    private let recorder = ShortcutRecorderView()
    private let messageIcon = NSImageView()
    private let messageLabel: DWBLabel
    private let removeButton: DWBButton
    private let cancelButton: DWBButton
    private let saveButton: DWBButton
    private var candidate: ShortcutKey?
    /// Called when the sheet closes with no change (Cancel or Escape).
    var onCancelled: (() -> Void)?

    /// - Parameters:
    ///   - commandID: The action being edited.
    ///   - editingKey: The key the user clicked, or `nil` to add a key.
    init(commandID: ShortcutCommandID, editingKey: ShortcutKey?, store: ShortcutStore = .shared) {
        self.commandID = commandID
        self.editingKey = editingKey
        self.store = store

        let command = ShortcutCommandTable.command(commandID)
        let chrome = DWBSheetChromeView(width: Self.width)
        let inner = Self.width - 40

        let title = DWBLabel("Edit shortcut", size: 13.5, weight: .semibold, tone: .primary)
        let appLabel = DWBLabel("dwb skim", size: 11.5, tone: .tertiary)
        let actionLabel = DWBSheet.wrappingLabel(command.name, size: 11.5, tone: .secondary, width: inner)

        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.recordedKey = editingKey

        messageLabel = DWBSheet.wrappingLabel("", size: 11, tone: .error, width: inner - 16)
        messageIcon.image = NSImage.dwbSymbol("exclamationmark.circle", pointSize: 11, color: DWBColor.errorText)
        messageIcon.translatesAutoresizingMaskIntoConstraints = false
        messageIcon.setAccessibilityElement(false)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        let message = NSStackView(views: [messageIcon, messageLabel])
        message.orientation = .horizontal
        message.alignment = .top
        message.spacing = 5
        message.translatesAutoresizingMaskIntoConstraints = false
        let messageContainer = NSView()
        messageContainer.translatesAutoresizingMaskIntoConstraints = false
        messageContainer.addSubview(message)
        // Two lines of 11 pt text, so a long action name never changes the sheet's height.
        NSLayoutConstraint.activate([
            messageContainer.heightAnchor.constraint(equalToConstant: 30),
            message.leadingAnchor.constraint(equalTo: messageContainer.leadingAnchor),
            message.topAnchor.constraint(equalTo: messageContainer.topAnchor),
            message.trailingAnchor.constraint(lessThanOrEqualTo: messageContainer.trailingAnchor),
        ])

        removeButton = DWBButton(title: "Remove", style: .neutral)
        cancelButton = DWBButton(title: "Cancel", style: .neutral)
        saveButton = DWBButton(title: "Save", style: .primary)
        saveButton.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [removeButton, spacer, cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        chrome.stack.addArrangedSubview(title)
        chrome.stack.addArrangedSubview(appLabel)
        chrome.stack.addArrangedSubview(actionLabel)
        chrome.stack.addArrangedSubview(recorder)
        chrome.stack.addArrangedSubview(messageContainer)
        chrome.stack.addArrangedSubview(buttons)
        chrome.stack.setCustomSpacing(2, after: title)
        chrome.stack.setCustomSpacing(2, after: appLabel)
        chrome.stack.setCustomSpacing(8, after: actionLabel)
        chrome.stack.setCustomSpacing(6, after: recorder)
        chrome.stack.setCustomSpacing(8, after: messageContainer)
        for view in [recorder, messageContainer, buttons] {
            view.widthAnchor.constraint(equalTo: chrome.stack.widthAnchor).isActive = true
        }
        recorder.heightAnchor.constraint(equalToConstant: DWBMetrics.sheetFieldHeight).isActive = true

        panel = DWBSheet.makePanel(chrome: chrome)
        panel.defaultButtonCell = saveButton.cell as? NSButtonCell
        super.init()

        recorder.onRecord = { [weak self] key in self?.recorded(key) }
        recorder.onEscape = { [weak self] in self?.cancel() }
        recorder.onReturn = { [weak self] in self?.saveButton.performClick(nil) }
        removeButton.target = self
        removeButton.action = #selector(remove)
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        saveButton.target = self
        saveButton.action = #selector(save)
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.initialFirstResponder = recorder
        recorder.nextKeyView = removeButton
        removeButton.nextKeyView = cancelButton
        cancelButton.nextKeyView = saveButton
        saveButton.nextKeyView = recorder
        chrome.setAccessibilityLabel("Edit shortcut for \(command.name)")
        chrome.setAccessibilityRole(.group)
        removeButton.isEnabled = editingKey != nil
        removeButton.setAccessibilityHelp(editingKey == nil ? "This action has no key to remove." : "Removes this key from the action.")
        refresh(validation: nil)
    }

    func present(on window: NSWindow) {
        retainedSelf = self
        DWBSheet.present(panel, on: window) { [weak self] _ in self?.retainedSelf = nil }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.makeFirstResponder(self.recorder)
        }
    }

    // MARK: Recording

    private func recorded(_ key: ShortcutKey) {
        candidate = key
        let validation = ShortcutValidation.evaluate(key, for: commandID, replacing: editingKey, store: store)
        refresh(validation: validation)
        if let text = validation.message {
            NSAccessibility.post(element: messageLabel,
                                 notification: .announcementRequested,
                                 userInfo: [.announcement: text,
                                            .priority: NSNumber(value: NSAccessibilityPriorityLevel.high.rawValue)])
        }
    }

    private func refresh(validation: ShortcutKeyValidation?) {
        let text = validation?.message
        messageLabel.stringValue = text ?? ""
        messageLabel.isHidden = text == nil
        messageIcon.isHidden = text == nil
        recorder.isError = text != nil
        let canSave = validation?.allowsSave == true && candidate != editingKey
        saveButton.isEnabled = canSave
        saveButton.setAccessibilityHelp(canSave ? "Saves the new key." : (text ?? "Press a key to enable Save."))
    }

    // MARK: Buttons

    @objc private func remove() {
        guard let editingKey else { return }
        DWBSheet.dismiss(panel, response: .OK)
        store.replaceKey(editingKey, with: nil, for: commandID)
    }

    @objc private func cancel() {
        DWBSheet.dismiss(panel, response: .cancel)
        onCancelled?()
    }

    @objc private func save() {
        guard let candidate, saveButton.isEnabled else { return }
        DWBSheet.dismiss(panel, response: .OK)
        store.replaceKey(editingKey, with: candidate, for: commandID)
    }
}
