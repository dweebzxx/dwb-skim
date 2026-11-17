import Cocoa

// MARK: - Controller

/// App-wide in-app debug console. Off by default; toggle in Settings > Developer.
/// Ring buffer of 5,000 entries. Supports category, level, and text filtering,
/// plus Pause/Resume for freezing the visible log while the app continues buffering.
/// While the console is off, warnings, errors, and the 400 info lines before them are still kept
/// in memory (see `DebugConsoleRetention`); nothing is written to disk.
final class DebugConsoleController: NSWindowController {

    static let shared = DebugConsoleController()

    // MARK: - Constants

    // Cap text-view rebuild rate during log storms. With multiple windows generating
    // sustained logs, an unthrottled rebuild blocks the main thread enough to freeze
    // the whole app (debug console included).
    private static let minRenderInterval: CFTimeInterval = 0.05  // ~20 Hz max

    // MARK: - Buffer state

    private var retention = DebugConsoleRetention()
    private var entries: [DebugLogEntry] { retention.entries }
    private(set) var isEnabled: Bool = false
    private var isPaused: Bool = false
    private var knownCategories: [String] = []

    // Coalesced render scheduling. All log appends in one runloop pass produce at most
    // one text-view rebuild; the rebuild itself is rate-limited to minRenderInterval.
    private var pendingRender: Bool = false
    private var lastRenderMT: CFTimeInterval = 0

    // MARK: - Filter state

    private var filterCategory: String? = nil     // nil = all categories
    private var filterMinLevel: DebugLevel? = nil // nil = all levels
    private var filterText: String = ""

    // MARK: - UI

    private let textView          = NSTextView()
    private let scrollView        = NSScrollView()
    private let searchField       = NSSearchField()
    private let filterPill        = DWBPillChromeView(cornerRadius: DWBMetrics.radiusPill)
    private let categoryPopup     = DWBPopUpButton()
    private let levelSegment      = DWBSegmentedControl(size: .small)
    private let pauseButton       = DWBButton(title: "Pause", style: .neutral, size: .small)
    private let statusLabel       = DWBLabel("", size: 10, tone: .tertiary, monospaced: true)

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let logFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let levelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
    /// Tab stops for the log columns: time, level (glyph and word), category, message.
    private static let levelTabStop: CGFloat = 88
    private static let categoryTabStop: CGFloat = 146
    private static let messageTabStop: CGFloat = 262

    // MARK: - Log entry points (main-thread only; dispatches if called off-main)

    static func log(_ category: String, _ message: String) {
        log(level: .info, category: category, message: message)
    }

    static func log(level: DebugLevel, category: String, message: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { log(level: level, category: category, message: message) }
            return
        }
        let entry = DebugLogEntry(date: Date(), level: level, category: category, message: message)
        if shared.isEnabled {
            shared.appendEntry(entry)
        } else {
            // Console off: keep the line in memory per the retention rules, and do no display work
            // (no text view, category popup, or status update).
            shared.retention.store(entry, isConsoleEnabled: false)
        }
    }

    // MARK: - Internal append

    private func appendEntry(_ entry: DebugLogEntry) {
        if !knownCategories.contains(entry.category) {
            knownCategories.append(entry.category)
            knownCategories.sort()
            rebuildCategoryPopup()
        }
        retention.store(entry, isConsoleEnabled: true)
        scheduleRender()
    }

    /// Coalesces text-view rebuilds + status updates onto a single async tick,
    /// rate-limited to minRenderInterval. Safe to call from any code path.
    private func scheduleRender() {
        if pendingRender { return }
        pendingRender = true
        DispatchQueue.main.async { [weak self] in self?.drainRender() }
    }

    private func drainRender() {
        let now = CACurrentMediaTime()
        let elapsed = now - lastRenderMT
        if elapsed < Self.minRenderInterval {
            // Re-queue to honor the minimum interval without dropping the render.
            DispatchQueue.main.asyncAfter(deadline: .now() + (Self.minRenderInterval - elapsed)) { [weak self] in
                self?.drainRender()
            }
            return
        }
        pendingRender = false
        lastRenderMT = now
        if !isPaused, window?.isVisible == true {
            rebuildTextView()
        }
        updateStatus()
    }

    // MARK: - Filtering

    private func entryMatchesFilters(_ entry: DebugLogEntry) -> Bool {
        if let cat = filterCategory, cat != entry.category { return false }
        if let minLev = filterMinLevel, entry.level < minLev { return false }
        if !filterText.isEmpty {
            let q = filterText.lowercased()
            if !entry.message.lowercased().contains(q) && !entry.category.lowercased().contains(q) {
                return false
            }
        }
        return true
    }

    private func visibleEntries() -> [DebugLogEntry] {
        entries.filter { entryMatchesFilters($0) }
    }

    private func rebuildTextView() {
        guard let storage = textView.textStorage else { return }
        let combined = NSMutableAttributedString()
        for entry in visibleEntries() {
            combined.append(displayLine(for: entry))
        }
        storage.setAttributedString(combined)
        textView.scrollToEndOfDocument(nil)
    }

    /// One log line for display: time, level (glyph, status color and word), category,
    /// message. Copy and Export keep using `formatEntry`.
    private func displayLine(for entry: DebugLogEntry) -> NSAttributedString {
        let statusColor: NSColor
        switch entry.level {
        case .info: statusColor = DWBAccessibility.textSecondary
        case .warning: statusColor = DWBColor.cautionText
        case .error: statusColor = DWBColor.errorText
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [
            NSTextTab(textAlignment: .left, location: Self.levelTabStop),
            NSTextTab(textAlignment: .left, location: Self.categoryTabStop),
            NSTextTab(textAlignment: .left, location: Self.messageTabStop),
        ]
        paragraph.defaultTabInterval = Self.messageTabStop
        paragraph.headIndent = Self.messageTabStop
        paragraph.firstLineHeadIndent = 0
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.paragraphSpacing = 2

        var base: [NSAttributedString.Key: Any] = [
            .font: Self.logFont,
            .paragraphStyle: paragraph,
        ]
        if entry.level == .error {
            base[.backgroundColor] = DWBColor.errorFill.withAlphaComponent(0.16)
        }
        func attributes(color: NSColor, font: NSFont = Self.logFont) -> [NSAttributedString.Key: Any] {
            var result = base
            result[.foregroundColor] = color
            result[.font] = font
            return result
        }

        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: timeFormatter.string(from: entry.date) + "\t",
                                       attributes: attributes(color: DWBAccessibility.textTertiary)))

        if let image = NSImage.dwbSymbol(entry.level.glyphName, pointSize: 10, weight: .semibold,
                                         color: statusColor) {
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: -1.5, width: image.size.width, height: image.size.height)
            let glyph = NSMutableAttributedString(attachment: attachment)
            glyph.addAttributes(base, range: NSRange(location: 0, length: glyph.length))
            line.append(glyph)
            line.append(NSAttributedString(string: " ", attributes: attributes(color: statusColor)))
        }
        line.append(NSAttributedString(string: entry.level.word + "\t",
                                       attributes: attributes(color: statusColor, font: Self.levelFont)))
        line.append(NSAttributedString(string: entry.category + "\t",
                                       attributes: attributes(color: DWBAccessibility.textSecondary)))
        line.append(NSAttributedString(string: entry.message + "\n",
                                       attributes: attributes(color: DWBColor.textPrimary)))
        return line
    }

    private func updateStatus() {
        let total   = entries.count
        let visible = filterCategory == nil && filterMinLevel == nil && filterText.isEmpty
            ? total
            : visibleEntries().count
        let pausedSuffix = isPaused ? " — PAUSED" : ""
        statusLabel.stringValue = "Showing \(visible) of \(total) total\(pausedSuffix)"
    }

    private func formatEntry(_ entry: DebugLogEntry) -> String {
        let ts = timeFormatter.string(from: entry.date)
        switch entry.level {
        case .info:    return "[\(ts)] [\(entry.category)] \(entry.message)"
        case .warning: return "[\(ts)] [WARN] [\(entry.category)] \(entry.message)"
        case .error:   return "[\(ts)] [ERR ] [\(entry.category)] \(entry.message)"
        }
    }

    // MARK: - Category popup

    private func rebuildCategoryPopup() {
        let selected = filterCategory
        categoryPopup.removeAllItems()
        categoryPopup.addItem(withTitle: "All Categories")
        categoryPopup.lastItem?.tag = -1
        for cat in knownCategories {
            categoryPopup.addItem(withTitle: cat)
        }
        if let cat = selected,
           let item = categoryPopup.itemArray.first(where: { $0.title == cat }) {
            categoryPopup.select(item)
        } else {
            categoryPopup.selectItem(withTag: -1)
        }
    }

    // MARK: - Settings observation

    @objc private func debugConsoleSettingDidChange() {
        let enabled = SettingsWindowController.isDebugConsoleEnabled()
        if enabled && !isEnabled {
            isEnabled = true
            // Lines kept while off join the main buffer first; then the category list is rebuilt
            // from what is stored and the view renders once, with the enable line included.
            retention.flushContext()
            retention.store(DebugLogEntry(date: Date(), level: .info, category: "console",
                                          message: "Debug Console enabled. Before this point only warnings, errors, and the lines just before them were kept."),
                            isConsoleEnabled: true)
            knownCategories = retention.categories
            rebuildCategoryPopup()
            rebuildTextView()
            updateStatus()
            showWindow(nil)
        } else if !enabled && isEnabled {
            appendEntry(DebugLogEntry(date: Date(), level: .info,
                                      category: "console", message: "Debug Console disabled"))
            isEnabled = false
            window?.orderOut(nil)
        }
    }

    // MARK: - Button actions

    @objc private func pauseTapped() {
        isPaused.toggle()
        pauseButton.title = isPaused ? "Resume" : "Pause"
        if !isPaused {
            rebuildTextView()
        }
        updateStatus()
    }

    @objc private func clearTapped() {
        retention.removeAll()
        knownCategories.removeAll()
        filterCategory = nil
        rebuildCategoryPopup()
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        updateStatus()
    }

    @objc private func copyAllTapped() {
        let text = sanitizedText(entries.map { formatEntry($0) }.joined(separator: "\n"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopyFeedback()
    }

    @objc private func exportTapped() {
        let panel = NSSavePanel()
        panel.title = "Export Debug Log"
        let safe = timeFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        panel.nameFieldStringValue = "dwb skim debug-\(safe).txt"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url, let self = self else { return }
            let text = self.sanitizedText(self.entries.map { self.formatEntry($0) }.joined(separator: "\n"))
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                if let window = self.window {
                    MessageSheetController.present(
                        title: DWBMessageText.exportFailed,
                        message: "The debug log could not be written to the selected location.\n\n\(error.localizedDescription)",
                        on: window)
                }
            }
        }
    }

    @objc private func copySnapshotTapped() {
        let total = entries.count
        let visible = visibleEntries().count
        let pausedNote = isPaused ? " [PAUSED]" : ""
        let ts = timeFormatter.string(from: Date())
        var lines: [String] = [
            "dwb skim Debug Snapshot — \(ts)",
            "Buffer: \(total) entries, \(visible) visible\(pausedNote)",
            ""
        ]
        let recent = entries.suffix(20)
        lines.append("Last \(recent.count) of \(total) entries:")
        lines.append(contentsOf: recent.map { formatEntry($0) })
        let text = sanitizedText(lines.joined(separator: "\n"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopyFeedback()
    }

    // MARK: - Sanitization helpers

    private func sanitizedText(_ raw: String) -> String {
        let prefixes = [
            SettingsWindowController.customPrefixValue(),
            SettingsWindowController.customPrefixSecondaryValue()
        ].filter { !$0.isEmpty }
        return DebugLogSanitizer(prefixesToRedact: prefixes).sanitize(raw)
    }

    private func showCopyFeedback() {
        statusLabel.stringValue = "Copied to clipboard (sanitized)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            if self.statusLabel.stringValue == "Copied to clipboard (sanitized)" {
                self.updateStatus()
            }
        }
    }

    @objc private func categoryChanged(_ sender: NSPopUpButton) {
        let title = sender.titleOfSelectedItem ?? ""
        filterCategory = (title == "All Categories") ? nil : title
        if !isPaused { rebuildTextView() }
        updateStatus()
    }

    @objc private func levelChanged(_ sender: DWBSegmentedControl) {
        switch sender.selectedSegment {
        case 1:  filterMinLevel = .warning
        case 2:  filterMinLevel = .error
        default: filterMinLevel = nil
        }
        if !isPaused { rebuildTextView() }
        updateStatus()
    }

    @objc private func searchTextChanged(_ notification: Notification) {
        filterText = searchField.stringValue
        if !isPaused { rebuildTextView() }
        updateStatus()
    }

    // MARK: - Init

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "dwb skim Debug Console"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 500, height: 300)
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { buttonType in
            panel.standardWindowButton(buttonType)?.isHidden = false
            panel.standardWindowButton(buttonType)?.isEnabled = true
        }
        super.init(window: panel)
        buildUI()
        isEnabled = SettingsWindowController.isDebugConsoleEnabled()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(debugConsoleSettingDidChange),
            name: .debugConsoleSettingChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(searchTextChanged(_:)),
            name: NSControl.textDidChangeNotification,
            object: searchField
        )
        if isEnabled { showWindow(nil) }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI construction

    private func buildUI() {
        guard let cv = window?.contentView else { return }
        let bg     = DWBColor.surfaceSunken
        let barBg  = DWBColor.canvas
        window?.backgroundColor = bg
        window?.appearance = NSAppearance(named: .darkAqua)

        let W = cv.bounds.width   // 780
        let barInset: CGFloat = 10

        // ── Toolbar (top, on canvas) ─────────────────────────────────
        let toolbarH: CGFloat = 40
        let toolbar = NSView(frame: NSRect(x: 0, y: cv.bounds.height - toolbarH, width: W, height: toolbarH))
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = barBg.cgColor
        toolbar.autoresizingMask = [.width, .minYMargin]
        cv.addSubview(toolbar)

        let toolbarRule = DWBRuleView(kind: .border)
        toolbarRule.frame = NSRect(x: 0, y: 0, width: W, height: 1)
        toolbarRule.autoresizingMask = [.width]
        toolbar.addSubview(toolbarRule)

        let filterH: CGFloat = 24
        let filterY = floor((toolbarH - filterH) / 2) + 1
        let catW:    CGFloat = 150
        let lvlW:    CGFloat = 150
        let gap:     CGFloat = 8
        let searchW  = W - barInset - gap - catW - gap - lvlW - barInset

        // Filter: a 24 pt pill (radius 12) on `surfaceElevated` with a 1 pt `border`.
        filterPill.frame = NSRect(x: barInset, y: filterY, width: searchW, height: filterH)
        filterPill.autoresizingMask = [.width]
        toolbar.addSubview(filterPill)

        searchField.cell = DWBSearchFieldCell(textCell: "")
        searchField.placeholderAttributedString = NSAttributedString(string: "Filter…", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: DWBAccessibility.textTertiary,
        ])
        searchField.font = .systemFont(ofSize: 11)
        searchField.textColor = DWBColor.textPrimary
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.frame = NSRect(x: 26, y: 2, width: searchW - 26 - 8, height: filterH - 4)
        searchField.autoresizingMask = [.width]
        searchField.setAccessibilityLabel("Filter log")
        filterPill.addSubview(searchField)
        let filterIcon = NSImageView(frame: NSRect(x: 9, y: floor((filterH - 12) / 2), width: 12, height: 12))
        filterIcon.image = NSImage.dwbSymbol("magnifyingglass", pointSize: 11, weight: .regular,
                                             color: DWBAccessibility.textTertiary)
        filterIcon.imageScaling = .scaleProportionallyDown
        filterIcon.setAccessibilityElement(false)
        filterPill.addSubview(filterIcon)

        categoryPopup.font = .systemFont(ofSize: 11)
        categoryPopup.target = self
        categoryPopup.action = #selector(categoryChanged(_:))
        categoryPopup.addItem(withTitle: "All Categories")
        categoryPopup.lastItem?.tag = -1
        categoryPopup.setAccessibilityLabel("Log category")
        categoryPopup.frame = NSRect(x: W - lvlW - gap - catW - barInset, y: filterY, width: catW, height: filterH)
        categoryPopup.autoresizingMask = [.minXMargin]
        toolbar.addSubview(categoryPopup)

        levelSegment.segmentCount = 3
        levelSegment.setLabel("All",   forSegment: 0)
        levelSegment.setLabel("⚠ Warn", forSegment: 1)
        levelSegment.setLabel("✕ Err",  forSegment: 2)
        levelSegment.selectedSegment = 0
        levelSegment.target = self
        levelSegment.action = #selector(levelChanged(_:))
        levelSegment.setAccessibilityLabel("Log level")
        let levelSize = levelSegment.intrinsicContentSize
        levelSegment.frame = NSRect(x: W - levelSize.width - barInset,
                                    y: floor((toolbarH - levelSize.height) / 2) + 1,
                                    width: levelSize.width,
                                    height: levelSize.height)
        levelSegment.autoresizingMask = [.minXMargin]
        toolbar.addSubview(levelSegment)

        // ── Footer (bottom, on canvas) ───────────────────────────────
        let footerH: CGFloat = 40
        let footer = NSView(frame: NSRect(x: 0, y: 0, width: W, height: footerH))
        footer.wantsLayer = true
        footer.layer?.backgroundColor = barBg.cgColor
        footer.autoresizingMask = [.width]
        cv.addSubview(footer)

        let footerRule = DWBRuleView(kind: .border)
        footerRule.frame = NSRect(x: 0, y: footerH - 1, width: W, height: 1)
        footerRule.autoresizingMask = [.width, .minYMargin]
        footer.addSubview(footerRule)

        let buttonH: CGFloat = 24
        let buttonY = floor((footerH - buttonH) / 2) - 1
        func makeButton(_ title: String, action: Selector) -> DWBButton {
            DWBButton(title: title, style: .neutral, size: .small, target: self, action: action)
        }
        let buttons = [
            makeButton("Clear",    action: #selector(clearTapped)),
            makeButton("Copy All", action: #selector(copyAllTapped)),
            makeButton("Snapshot", action: #selector(copySnapshotTapped)),
            makeButton("Export…",  action: #selector(exportTapped)),
        ]
        var bx = barInset
        for button in buttons {
            let width = ceil(button.intrinsicContentSize.width)
            button.frame = NSRect(x: bx, y: buttonY, width: width, height: buttonH)
            footer.addSubview(button)
            bx += width + 6
        }

        pauseButton.target = self
        pauseButton.action = #selector(pauseTapped)
        let pauseW: CGFloat = 70
        pauseButton.frame = NSRect(x: W - pauseW - barInset, y: buttonY, width: pauseW, height: buttonH)
        pauseButton.autoresizingMask = [.minXMargin]
        footer.addSubview(pauseButton)

        // Status text sits between the buttons and Pause.
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.alignment = .right
        let statusX = bx + 8
        statusLabel.frame = NSRect(x: statusX,
                                   y: floor((footerH - 14) / 2) - 1,
                                   width: max(0, W - pauseW - barInset - 8 - statusX),
                                   height: 14)
        statusLabel.autoresizingMask = [.width]
        footer.addSubview(statusLabel)

        // ── Log (`surfaceSunken`) ────────────────────────────────────
        scrollView.frame = NSRect(x: 0, y: footerH, width: W, height: cv.bounds.height - footerH - toolbarH)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = bg
        cv.addSubview(scrollView)

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = bg
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                   height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.setAccessibilityLabel("Debug log")
        scrollView.documentView = textView

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(accessibilityDidChange),
                                               name: DWBAccessibility.didChange,
                                               object: nil)
        updateStatus()
    }

    /// Increase Contrast changes the secondary and tertiary text the log is drawn with.
    @objc private func accessibilityDidChange() {
        searchField.placeholderAttributedString = NSAttributedString(string: "Filter…", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: DWBAccessibility.textTertiary,
        ])
        rebuildTextView()
    }
}
