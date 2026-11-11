import Cocoa

/// Delegate for queue-page interactions.
protocol QueuePageViewDelegate: AnyObject {
    func queuePage(_ view: QueuePageView, didSelectDisplayIndex index: Int)
    func queuePage(_ view: QueuePageView, didRequestRenameAt index: Int)
    func queuePage(_ view: QueuePageView, didRequestRevealAt index: Int)
    func queuePage(_ view: QueuePageView, didRequestDeleteAt index: Int)
    func queuePage(_ view: QueuePageView, didChangeSortMode mode: QueueSortMode)
    func queuePageDidRequestClose(_ view: QueuePageView)
    /// Called when the user drags a row from `from` to the insertion point `to`
    /// (NSTableView .above drop-operation semantics; 0…items.count).
    func queuePage(_ view: QueuePageView, didReorderFromIndex from: Int, toIndex to: Int)
    /// Called when the user activates "Remove All" in the queue page.
    func queuePageDidRequestRemoveAll(_ view: QueuePageView)
    /// Called when the user triggers the one-click custom prefix rename action (feature-gated).
    /// `indices` is always ascending. Caller must preflight all targets before renaming any.
    func queuePage(_ view: QueuePageView, didRequestCustomPrefixRenameAt indices: [Int])
    /// Called when the user triggers the secondary custom prefix rename action (feature-gated).
    /// `indices` is always ascending. Caller must preflight all targets before renaming any.
    func queuePage(_ view: QueuePageView, didRequestSecondaryCustomPrefixRenameAt indices: [Int])
    /// Called when the user presses Delete/Backspace with multiple rows selected.
    /// `indices` is sorted descending so the caller can delete safely without index shifts.
    func queuePage(_ view: QueuePageView, didRequestDeleteRows indices: [Int])
    /// Called from the queue empty state to use the app's existing media-open flow.
    func queuePageDidRequestAddMedia(_ view: QueuePageView)
    /// Called when the user triggers the folder rescan action from the queue footer.
    func queuePageDidRequestRescan(_ view: QueuePageView)
    /// Called when the user requests to undo the window's most recent marker
    /// rename (the same undo as Command-Z). This reverts a real file rename on
    /// disk, not just in-memory state.
    func queuePageDidRequestMarkerRenameUndo(_ view: QueuePageView)
}

/// Full in-window Queue Page panel.
/// Designed for the player's compact 280-360 point right-side panel.
/// Shows the playback set in current traversal order with filename, duration,
/// and file size. Supports single-click selection, double-click playback, and
/// queue file actions.
final class QueuePageView: NSView, NSSearchFieldDelegate {

    // MARK: - Item model

    struct Item {
        let id:          String
        let url:         URL
        var displayName: String
        var duration:    String   // "1:23:45" or "--:--"
        var fileSize:    String   // "12.3 MB" or "--"
        var isBookmarked: Bool = false
        /// The item failed to become playable this session (`SkimFailedItemTracker`).
        var isFailed: Bool = false
    }

    private struct VisibleRow {
        let displayIndex: Int
        let item: Item
    }

    // MARK: - Public state

    weak var delegate: QueuePageViewDelegate?

    /// Call update(items:currentIndex:) to refresh data and reload the table.
    private(set) var items: [Item] = []
    private var visibleItems: [Item] = []
    private var visibleToDisplayIndices: [Int] = []
    private var visibleRows: [VisibleRow] = []
    private(set) var currentDisplayIndex: Int = -1
    private var currentSortMode: QueueSortMode = .manual
    private var allowsManualReorder = true
    private var isUpdatingSortControl = false
    private var totalDurationText = MediaFileSupport.formatClockDuration(0)
    private var bookmarkFilterEnabled = false

    /// True while the owning window holds a marker rename undo step; enables
    /// the footer undo button.
    var isMarkerRenameUndoAvailable: Bool = false {
        didSet {
            chipGroup.isUndoEnabled = isMarkerRenameUndoAvailable
            needsLayout = true
        }
    }

    func update(items: [Item],
                currentIndex: Int,
                sortMode: QueueSortMode,
                totalDurationText: String,
                originalRootURL: URL?) {
        let selectedItemIDs = Set(tableView.selectedRowIndexes.compactMap { row -> String? in
            guard let item = visibleItem(at: row) else { return nil }
            return item.id
        })
        let scroll = currentIndex != currentDisplayIndex && currentIndex >= 0
        self.items = items
        self.currentDisplayIndex = currentIndex
        self.totalDurationText = totalDurationText
        updateOriginalRoot(originalRootURL)
        currentSortMode = sortMode
        allowsManualReorder = sortMode == .manual && currentSearchQuery.isEmpty
        updateSortControlSelection()
        updateHeaderSortIndicators()
        applySearchFilter(preservingSelectedItemIDs: selectedItemIDs)
        if scroll {
            scrollNowPlayingToTop()
        }
        applyColumnLayout(reason: "queue-reload", forceDiagnostic: false)
    }

    private func scrollNowPlayingToTop() {
        guard currentDisplayIndex >= 0,
              let itemRow = visibleRow(forDisplayIndex: currentDisplayIndex) else { return }
        let rowRect = tableView.rect(ofRow: itemRow)
        let targetY = max(0, rowRect.minY)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func updateOriginalRoot(_ url: URL?) {
        let display = url?.path ?? "Individual files"
        rootPathLabel.stringValue = display
        rootPathLabel.toolTip = display
        rootPathLabel.setAccessibilityLabel("Original source: \(display)")
        rootIcon.image = NSImage(systemSymbolName: url == nil ? "doc.on.doc" : "folder",
                                 accessibilityDescription: "Original source")
    }

    // MARK: - Subviews

    private let headerView       = NSView()
    private let titleLabel       = DWBLabel("Queue", size: 15, weight: .semibold, tone: .primary)
    private let searchSortPill   = QueueSearchSortPillView()
    private let searchSortDivider = QueuePassthroughView()
    private let searchIconView   = QueueCenteredSymbolView()
    private let sortPopUpButton  = NSPopUpButton()
    private let sortTitleView    = QueueCenteredTextView()
    private let sortChevronView  = QueueCenteredSymbolView()
    private let searchField      = NSSearchField()
    private let bookmarkFilterButton = QueueHeaderSymbolButton(frame: .zero)
    private let closeButton      = QueueHeaderSymbolButton(frame: .zero)
    private let topSeparator     = DWBRuleView(kind: .border)
    let scrollView               = NSScrollView()
    let tableView                = QueuePageTableView()
    private let emptyStateView   = NSView()
    private let emptyStateLogoView = NSImageView()
    private let emptyGlyphCircle = QueueEmptyGlyphView()
    private let emptyStateLabel  = DWBLabel("No media in queue", size: 14, weight: .semibold, tone: .primary)
    private let emptyStateDetailLabel = DWBLabel("Add files or folders to build the queue.", size: 11.5, tone: .tertiary)
    private let emptyStateActionButton = DWBButton(title: "Add Media", style: .pillOutline)
    private let bottomSeparator  = DWBRuleView(kind: .border)
    private let rootBar          = NSView()
    private let rootBarSeparator = DWBRuleView(kind: .gridLine)
    private let rootIcon         = NSImageView()
    private let rootPathLabel    = DWBLabel("Individual files", size: 11.5, tone: .secondary)
    private let bottomBar        = NSView()
    // Icon only, as in the dwb player footer; the title stays as its accessibility label.
    private let deleteButton              = DWBButton(title: "",
                                                      style: .inlineDestructive,
                                                      leadingSymbol: QueueRemovalPresentation.buttonSymbolName)
    private let chipGroup                 = QueueMarkerChipGroupView()
    private let rescanButton              = DWBButton(title: "Rescan", style: .pill)
    private let footerClearSeparator      = DWBRuleView(kind: .border, vertical: true)
    private let removeAllButton           = DWBButton(title: "Clear Queue", style: .pillDestructive)
    private let totalDurationLabel = DWBLabel("Total: 00:00:00", size: 10.5, weight: .medium, tone: .secondary, tabularDigits: true)

    // Column identifiers
    private static let colName = NSUserInterfaceItemIdentifier("name")
    private static let colDur  = NSUserInterfaceItemIdentifier("dur")
    private static let colSize = NSUserInterfaceItemIdentifier("size")

    // UserDefaults keys for optional column visibility (Duration and Size).
    // File column is always visible; these default to true.
    static let durationColumnVisibleKey = "com.dwb.queueColumnDurationVisible"
    static let sizeColumnVisibleKey     = "com.dwb.queueColumnSizeVisible"
    static let durationColumnWidthKey   = "com.dwb.queueColumnDurationWidth"
    static let sizeColumnWidthKey       = "com.dwb.queueColumnSizeWidth"

    private static let fileColumnMinimumWidth: CGFloat = 180

    // Shared metadata-column dimensions so Duration and Size are equal width.
    // Fixed adaptive widths for Duration/Size — no user-driven resize as of P43.4.
    // Old `*WidthKey` UserDefaults values from P43.2/P43.3 are intentionally ignored.
    private static let metadataColumnDefaultWidth: CGFloat = 68
    private static let metadataColumnMinimumWidth: CGFloat = 56

    private static let durationColumnDefaultWidth = metadataColumnDefaultWidth
    private static let durationColumnMinimumWidth = metadataColumnMinimumWidth

    private static let sizeColumnDefaultWidth = metadataColumnDefaultWidth
    private static let sizeColumnMinimumWidth = metadataColumnMinimumWidth

    // Footer-safe trailing boundary: keeps the total-duration label visually
    // separated from the far-right panel edge, aligning it under the metadata
    // columns rather than hugging the Size column's right text edge. This is
    // intentionally a footer-only inset; it does not affect column/header/row geometry.
    private static let totalDurationTrailingInset: CGFloat = 72

    // Padding constants used by QueueColumnGeometry to keep header labels, row
    // cells, and the bottom total-duration label aligned to the same content insets.
    fileprivate static let cellLeadingPadding: CGFloat = 8
    fileprivate static let cellTrailingPadding: CGFloat = 8

    // Pasteboard type for internal row-reorder drag
    private static let draggedRowType = NSPasteboard.PasteboardType("com.dwb.queueRow")
    private var lastCoordinateDiagnosticTimeByReason: [String: Date] = [:]

    // Layout reentrancy guard and coalescing state.
    // isApplyingColumnLayout is set while inside applyColumnLayout; prevents
    // synchronous recursion. pendingColumnLayout captures any request that
    // arrives while the guard is held — the defer block drains it via
    // DispatchQueue.main.async so it never recurses on the same call stack.
    private var isApplyingColumnLayout = false
    private var pendingColumnLayout: (reason: String, force: Bool)? = nil

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupViews() {
        layer?.backgroundColor = DWBColor.surface.cgColor

        // ── Header ──────────────────────────────────────────────────────────
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = DWBColor.canvas.cgColor
        addSubview(headerView)

        headerView.addSubview(titleLabel)

        addSubview(topSeparator)

        // The pill draws its own `surfaceElevated` ground and 1 pt `border`.
        headerView.addSubview(searchSortPill)

        searchSortDivider.wantsLayer = true
        searchSortPill.addSubview(searchSortDivider)

        searchIconView.configure(symbolName: "magnifyingglass",
                                 pointSize: 12,
                                 weight: .regular,
                                 color: DWBAccessibility.textTertiary,
                                 accessibilityDescription: nil)
        searchSortPill.addSubview(searchIconView)

        sortTitleView.font = .systemFont(ofSize: 10.5, weight: .regular)
        sortTitleView.textColor = DWBAccessibility.textSecondary
        searchSortPill.addSubview(sortTitleView)

        sortChevronView.configure(symbolName: "chevron.up.chevron.down",
                                  pointSize: 10,
                                  weight: .medium,
                                  color: DWBAccessibility.textSecondary,
                                  accessibilityDescription: nil)
        searchSortPill.addSubview(sortChevronView)

        sortPopUpButton.cell = QueueTransparentPopUpButtonCell(textCell: "", pullsDown: false)
        sortPopUpButton.font = .systemFont(ofSize: 10.5, weight: .regular)
        sortPopUpButton.bezelStyle = .rounded
        sortPopUpButton.isBordered = false
        sortPopUpButton.target = self
        sortPopUpButton.action = #selector(sortModeChanged)
        sortPopUpButton.toolTip = "Queue sort order"
        sortPopUpButton.setAccessibilityLabel("Queue sort order")
        QueueSortMode.allCases.forEach { mode in
            let title = mode == .manual ? "Sort: Manual" : "Sort: \(mode.title)"
            sortPopUpButton.addItem(withTitle: title)
            sortPopUpButton.lastItem?.tag = mode.rawValue
        }
        updateSortControlSelection()
        searchSortPill.addSubview(sortPopUpButton)

        searchField.cell = QueueSearchFieldCell(textCell: "")
        searchField.isEditable = true
        searchField.font = .systemFont(ofSize: 11)
        searchField.textColor = DWBColor.textPrimary
        searchField.drawsBackground = false
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.toolTip = "Search queue filenames"
        searchField.setAccessibilityLabel("Search queue")
        searchSortPill.searchField = searchField
        searchSortPill.addSubview(searchField)

        bookmarkFilterButton.isBordered = false
        bookmarkFilterButton.bezelStyle = .regularSquare
        bookmarkFilterButton.symbolPointSize = 14
        bookmarkFilterButton.symbolWeight = .medium
        bookmarkFilterButton.target = self
        bookmarkFilterButton.action = #selector(bookmarkFilterTapped)
        bookmarkFilterButton.setButtonType(.toggle)
        bookmarkFilterButton.toolTip = "Show bookmarked queue files"
        bookmarkFilterButton.setAccessibilityLabel("Bookmark filter")
        headerView.addSubview(bookmarkFilterButton)
        updateBookmarkFilterButton()

        closeButton.isBordered     = false
        closeButton.bezelStyle     = .regularSquare
        closeButton.symbolName     = "xmark"
        closeButton.symbolPointSize = 14
        closeButton.symbolWeight   = .medium
        closeButton.contentTintColor = DWBAccessibility.textSecondary
        closeButton.toolTip          = "Close Queue"
        closeButton.setAccessibilityLabel("Close Queue")
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        headerView.addSubview(closeButton)

        addSubview(bottomSeparator)

        // ── Table ─────────────────────────────────────────────────────────
        // NSTableColumn.minWidth is intentionally tiny (1) so AppKit cannot clamp
        // the real column widths back to a hard minimum and defeat the no-overflow
        // layout below. The `fileColumnMinimumWidth`, `durationColumnMinimumWidth`,
        // and `sizeColumnMinimumWidth` constants are layout *preferences* honored by
        // `applyColumnLayout`, not AppKit-enforced minimums. When the panel is too
        // narrow, the layout must be allowed to shrink rather than have AppKit
        // force the column sum past the visible clip width.
        let nameCol = NSTableColumn(identifier: Self.colName)
        nameCol.title  = "File"
        nameCol.resizingMask = []
        nameCol.minWidth = 1
        nameCol.headerCell = QueueColumnHeaderCell(title: "File", alignment: .left)

        let durCol  = NSTableColumn(identifier: Self.colDur)
        durCol.title = "Duration"
        durCol.width = Self.durationColumnDefaultWidth
        durCol.minWidth = 1
        durCol.maxWidth = Self.durationColumnDefaultWidth
        durCol.resizingMask = []
        durCol.headerCell = QueueColumnHeaderCell(title: "Duration", alignment: .right)

        let sizeCol = NSTableColumn(identifier: Self.colSize)
        sizeCol.title = "Size"
        sizeCol.width = Self.sizeColumnDefaultWidth
        sizeCol.minWidth = 1
        sizeCol.maxWidth = Self.sizeColumnDefaultWidth
        sizeCol.resizingMask = []
        sizeCol.headerCell = QueueColumnHeaderCell(title: "Size", alignment: .right)

        tableView.addTableColumn(nameCol)
        tableView.addTableColumn(durCol)
        tableView.addTableColumn(sizeCol)
        updateHeaderSortIndicators()
        // applyColumnLayout() is the single source of truth; AppKit must not mutate widths.
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.headerView   = nil
        tableView.rowHeight    = Self.rowPitch
        // Plain rows span the full clip width; the inset style would add 10 pt of padding on
        // each side and push the row cards past the clip.
        tableView.style        = .plain
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.gridColor = DWBColor.gridLine
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.allowsMultipleSelection = true
        tableView.dataSource   = self
        tableView.delegate     = self
        tableView.target       = self
        tableView.action       = #selector(rowClicked)
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.contextMenuProvider = { [weak self] row in
            self?.makeContextMenu(for: row)
        }

        // Enable row reordering via drag-and-drop. The drop line is drawn by the table
        // view itself, so the system's feedback is turned off.
        tableView.registerForDraggedTypes([Self.draggedRowType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.draggingDestinationFeedbackStyle = .none

        // The sidebar presentation renders file metadata inside each media card,
        // so the legacy Duration/Size columns remain hidden while their data
        // still feeds the row subtitle.
        durCol.isHidden = true
        sizeCol.isHidden = true

        let lockedClipView = LockedHorizontalClipView()
        lockedClipView.drawsBackground = false
        scrollView.contentView          = lockedClipView
        scrollView.documentView           = tableView
        scrollView.hasVerticalScroller     = true
        scrollView.hasHorizontalScroller   = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true
        scrollView.autohidesScrollers      = true
        scrollView.borderType              = .noBorder
        scrollView.backgroundColor         = .clear
        addSubview(scrollView)

        // ── Empty and filtered-empty states ───────────────────────────────
        emptyStateView.wantsLayer = true
        emptyStateView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(emptyStateView)

        // The faded app icon is the only imagery of the empty queue.
        emptyStateLogoView.image = NSApplication.shared.applicationIconImage
        emptyStateLogoView.imageScaling = .scaleProportionallyUpOrDown
        emptyStateLogoView.alphaValue = 0.32
        emptyStateLogoView.isEditable = false
        emptyStateLogoView.setAccessibilityElement(false)
        emptyStateLogoView.focusRingType = .none
        emptyStateView.addSubview(emptyStateLogoView)

        emptyStateView.addSubview(emptyGlyphCircle)

        emptyStateLabel.alignment = .center
        emptyStateLabel.lineBreakMode = .byWordWrapping
        emptyStateView.addSubview(emptyStateLabel)

        emptyStateDetailLabel.alignment = .center
        emptyStateDetailLabel.lineBreakMode = .byWordWrapping
        emptyStateDetailLabel.maximumNumberOfLines = 0
        emptyStateDetailLabel.cell?.wraps = true
        emptyStateView.addSubview(emptyStateDetailLabel)

        emptyStateActionButton.target = self
        emptyStateActionButton.action = #selector(emptyStateActionTapped)
        emptyStateView.addSubview(emptyStateActionButton)

        // Re-run the column layout when the clip view's width changes — this happens
        // when the vertical scroller toggles, which would otherwise leave the Size
        // column extending past the visible cell area on the right edge.
        scrollView.contentView.postsFrameChangedNotifications = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(scrollContentDidResize),
                                               name: NSView.frameDidChangeNotification,
                                               object: scrollView.contentView)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(scrollContentDidResize),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleCustomPrefixValueChanged),
                                               name: .customPrefixValueChanged,
                                               object: nil)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))

        // ── Fixed original source root ────────────────────────────────────
        rootBar.wantsLayer = true
        rootBar.layer?.backgroundColor = DWBColor.canvas.cgColor
        addSubview(rootBar)
        rootBar.addSubview(rootBarSeparator)
        rootIcon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Original root folder")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        rootIcon.contentTintColor = DWBAccessibility.textSecondary
        rootIcon.imageScaling = .scaleProportionallyDown
        rootBar.addSubview(rootIcon)
        rootPathLabel.lineBreakMode = .byTruncatingMiddle
        rootPathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rootBar.addSubview(rootPathLabel)

        // ── Bottom bar ────────────────────────────────────────────────────
        bottomBar.wantsLayer = true
        bottomBar.layer?.backgroundColor = DWBColor.canvas.cgColor
        addSubview(bottomBar)

        deleteButton.toolTip   = QueueRemovalPresentation.buttonToolTip
        deleteButton.setAccessibilityLabel(QueueRemovalPresentation.buttonAccessibilityLabel)
        deleteButton.target    = self
        deleteButton.action    = #selector(deleteTapped)
        bottomBar.addSubview(deleteButton)

        // Undo reverts the window's last marker rename, the same as Command-Z; it lives in
        // the chip group.
        chipGroup.onChipTapped = { [weak self] kind in self?.applyPrefix(kind) }
        chipGroup.onUndoTapped = { [weak self] in self?.markerUndoTapped() }
        bottomBar.addSubview(chipGroup)

        rescanButton.toolTip        = "Rescan Folder — refresh the queue from current folder contents on disk"
        rescanButton.setAccessibilityLabel("Rescan Folder")
        rescanButton.target         = self
        rescanButton.action         = #selector(rescanTapped)
        bottomBar.addSubview(rescanButton)

        bottomBar.addSubview(footerClearSeparator)

        removeAllButton.toolTip      = "Clear Queue"
        removeAllButton.setAccessibilityLabel("Clear Queue")
        removeAllButton.target       = self
        removeAllButton.action       = #selector(removeAllTapped)
        bottomBar.addSubview(removeAllButton)

        // Wire up keyboard-delete handler so Delete/Backspace on a selected row
        // removes that item.  Re-selecting the appropriate row is handled after
        // the table reloads (see QueuePageTableView.keyDown).
        tableView.deleteRowsHandler = { [weak self] indices in
            guard let self = self else { return }
            let displayIndices = indices.compactMap { self.displayIndex(forVisibleRow: $0) }.sorted(by: >)
            guard !displayIndices.isEmpty else { return }
            if displayIndices.count == 1 {
                self.delegate?.queuePage(self, didRequestDeleteAt: displayIndices[0])
            } else {
                self.delegate?.queuePage(self, didRequestDeleteRows: displayIndices)
            }
        }

        totalDurationLabel.alignment = .right
        totalDurationLabel.lineBreakMode = .byTruncatingTail
        bottomBar.addSubview(totalDurationLabel)

        applyAccessibilityColors()
        DispatchQueue.main.async { [weak self] in
            self?.applyColumnLayout(reason: "queue-setup", forceDiagnostic: true)
        }
        updateMarkerChips()
    }

    /// Re-resolves the colors set once at setup, so Increase Contrast applies live.
    private func applyAccessibilityColors() {
        searchSortDivider.layer?.backgroundColor = DWBAccessibility.border.cgColor
        searchIconView.color = DWBAccessibility.textTertiary
        sortTitleView.textColor = DWBAccessibility.textSecondary
        sortChevronView.color = DWBAccessibility.textSecondary
        let placeholder = NSAttributedString(string: "Search queue", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: DWBAccessibility.textTertiary,
        ])
        searchField.placeholderAttributedString = placeholder
        rootIcon.contentTintColor = DWBAccessibility.textSecondary
        closeButton.contentTintColor = DWBAccessibility.textSecondary
        updateBookmarkFilterButton()
        searchSortPill.needsDisplay = true
    }

    @objc private func accessibilityDidChange() {
        applyAccessibilityColors()
        chipGroup.needsDisplay = true
        tableView.reloadData()
    }

    // MARK: - Layout constants

    private let headerH:    CGFloat = DWBMetrics.queueHeaderHeight
    private let rootH:      CGFloat = 28
    /// One row's pitch: the 56 pt card plus the 4 pt inset above and below it.
    fileprivate static let rowPitch: CGFloat = DWBMetrics.queueRowHeight + DWBMetrics.queueRowInset * 2

    override func layout() {
        super.layout()
        let b = bounds

        // Footer first: its height depends on how the controls wrap at this width.
        let footerH = layoutFooter(width: b.width)

        // Header
        headerView.frame = NSRect(x: 0, y: b.height - headerH, width: b.width, height: headerH)
        let headerAxisY = headerView.bounds.midY
        let leadingPad: CGFloat = 16
        let trailingPad: CGFloat = 12
        let itemGap: CGFloat = 10
        let iconButtonSize: CGFloat = 26
        closeButton.frame = NSRect(x: max(leadingPad, b.width - trailingPad - iconButtonSize),
                                   y: floor(headerAxisY - iconButtonSize / 2),
                                   width: iconButtonSize,
                                   height: iconButtonSize)
        bookmarkFilterButton.frame = NSRect(x: max(leadingPad, closeButton.frame.minX - 4 - iconButtonSize),
                                            y: floor(headerAxisY - iconButtonSize / 2),
                                            width: iconButtonSize,
                                            height: iconButtonSize)

        let titlePreferredWidth = ceil(titleLabel.intrinsicContentSize.width) + 6
        let titleAvailableWidth = max(0, bookmarkFilterButton.frame.minX - itemGap - leadingPad)
        let titleWidth = min(titlePreferredWidth, titleAvailableWidth)
        let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
        titleLabel.frame = NSRect(x: leadingPad,
                                  y: floor(headerAxisY - titleHeight / 2),
                                  width: titleWidth,
                                  height: titleHeight)
        let pillX = titleLabel.frame.maxX + itemGap
        let pillRight = bookmarkFilterButton.frame.minX - itemGap
        let maxPillW = max(0, min(560, b.width * 0.72))
        let pillW = max(0, min(pillRight - pillX, maxPillW))
        let pillH: CGFloat = 28
        searchSortPill.frame = NSRect(x: pillX,
                                      y: floor(headerAxisY - pillH / 2),
                                      width: pillW,
                                      height: pillH)
        searchSortPill.isHidden = pillW <= 0
        let dividerH: CGFloat = 20
        let innerPad: CGFloat = 9
        let searchIconSlotWidth: CGFloat = 24
        let searchFieldX = innerPad + searchIconSlotWidth + 1
        let minimumSearchTextWidth: CGFloat = 52
        let minimumSortWidth: CGFloat = 80
        let sortWidth = min(CGFloat(122), max(minimumSortWidth, pillW * 0.34))
        let sortVisible = pillW >= searchFieldX + minimumSearchTextWidth + 6 + sortWidth
        let effectiveSortWidth = sortVisible ? sortWidth : 0
        let dividerX = sortVisible ? max(0, pillW - effectiveSortWidth - 1) : pillW
        let searchAreaWidth = sortVisible ? dividerX : pillW
        searchSortPill.searchFocusRect = NSRect(x: 0,
                                                y: 0,
                                                width: max(0, searchAreaWidth),
                                                height: pillH)
        searchSortDivider.frame = NSRect(x: dividerX,
                                         y: centeredY(height: dividerH, in: pillH),
                                         width: 1,
                                         height: dividerH)
        searchSortDivider.isHidden = !sortVisible
        searchIconView.frame = NSRect(x: innerPad,
                                      y: 0,
                                      width: searchIconSlotWidth,
                                      height: pillH)
        let searchFieldHeight: CGFloat = 22
        searchField.frame = NSRect(x: searchFieldX,
                                   y: centeredY(height: searchFieldHeight, in: pillH),
                                   width: max(0, searchAreaWidth - searchFieldX - 5),
                                   height: searchFieldHeight)
        let sortHeight: CGFloat = 24
        let sortFrame = NSRect(x: dividerX + 1,
                               y: centeredY(height: sortHeight, in: pillH),
                               width: max(0, effectiveSortWidth),
                               height: sortHeight)
        sortPopUpButton.isHidden = !sortVisible
        sortTitleView.isHidden = !sortVisible
        sortChevronView.isHidden = !sortVisible
        sortPopUpButton.frame = sortFrame
        let sortInnerPad: CGFloat = 12
        let chevronSlotWidth: CGFloat = 22
        sortChevronView.frame = NSRect(x: max(sortFrame.minX, sortFrame.maxX - chevronSlotWidth),
                                       y: sortFrame.minY,
                                       width: min(chevronSlotWidth, sortFrame.width),
                                       height: sortFrame.height)
        sortTitleView.frame = NSRect(x: sortFrame.minX + sortInnerPad,
                                     y: sortFrame.minY,
                                     width: max(0, sortChevronView.frame.minX - sortFrame.minX - sortInnerPad - 4),
                                     height: sortFrame.height)

        topSeparator.frame = NSRect(x: 0, y: b.height - headerH - 1, width: b.width, height: 1)

        // Table scroll view
        let tableTop = b.height - headerH - 1
        let tableBottom = footerH + rootH + 1
        let tableH   = max(0, tableTop - tableBottom)
        scrollView.frame = NSRect(x: 0, y: tableBottom, width: b.width, height: tableH)
        emptyStateView.frame = scrollView.frame.insetBy(dx: 22, dy: 28)
        layoutEmptyState()
        scrollView.layoutSubtreeIfNeeded()
        // Do not manually set tableView.headerView.frame here — tile() owns header width,
        // and writing it inside a layout pass posts a frame-change notification that fed
        // back into the P43.6 recursive layout storm.
        applyColumnLayout(reason: "layout", forceDiagnostic: false)

        // Source row, then the footer's top rule.
        rootBar.frame = NSRect(x: 0, y: footerH, width: b.width, height: rootH)
        rootBarSeparator.frame = NSRect(x: 0, y: 0, width: b.width, height: 1)
        rootIcon.frame = NSRect(x: 14, y: floor((rootH - 14) / 2) + 1, width: 14, height: 14)
        let rootLabelHeight = ceil(rootPathLabel.intrinsicContentSize.height)
        rootPathLabel.frame = NSRect(x: 34,
                                     y: floor((rootH - rootLabelHeight) / 2) + 1,
                                     width: max(0, b.width - 34 - 14),
                                     height: rootLabelHeight)
        bottomSeparator.frame = NSRect(x: 0, y: footerH + rootH, width: b.width, height: 1)
    }

    /// Lays out the footer controls and returns the footer's height.
    ///
    /// The icon-only Remove button and the marker chip group (primary prefix, secondary
    /// prefix, Undo) share the first row, with Undo dropping to its glyph before the group
    /// wraps to its own row (`QueueFooterPresentation.markerGroupPlan`). Rescan, the total
    /// and Clear Queue share the last row; when the total does not fit between them it
    /// takes its own row above.
    private func layoutFooter(width: CGFloat) -> CGFloat {
        let sidePad: CGFloat = 12
        let topPad: CGFloat = 8
        let rowGap: CGFloat = 6
        let bottomPad: CGFloat = 10
        let itemGap: CGFloat = 8
        let available = max(0, width - sidePad * 2)

        let removeSize = deleteButton.intrinsicContentSize
        let fullGroupWidth = chipGroup.width(compactUndo: false)
        let compactGroupWidth = chipGroup.width(compactUndo: true)
        let plan = QueueFooterPresentation.markerGroupPlan(availableWidth: available,
                                                           removeWidth: removeSize.width,
                                                           fullGroupWidth: fullGroupWidth,
                                                           compactGroupWidth: compactGroupWidth,
                                                           itemGap: itemGap)
        chipGroup.isUndoCompact = plan.isUndoCompact
        let groupItem: (view: NSView, size: NSSize) = (
            chipGroup,
            NSSize(width: plan.isUndoCompact ? compactGroupWidth : fullGroupWidth,
                   height: QueueMarkerChipGroupView.height))
        let removeItem: (view: NSView, size: NSSize) = (deleteButton, removeSize)
        let rows: [[(view: NSView, size: NSSize)]] = plan.wrapsMarkerGroup
            ? [[removeItem], [groupItem]]
            : [[removeItem, groupItem]]

        // The last row's controls, and whether the total fits between them.
        let lastRowHeight = DWBButton.height(for: .pill, size: .regular)
        let rescanSize = rescanButton.intrinsicContentSize
        let clearSize = removeAllButton.intrinsicContentSize
        let clearX = max(sidePad, width - sidePad - clearSize.width)
        let dividerX = clearX - 10
        let totalLeft = sidePad + rescanSize.width + itemGap
        let totalRight = dividerX - 10
        let totalSize = totalDurationLabel.intrinsicContentSize
        let totalHeight = ceil(totalSize.height)
        let totalFitsInline = ceil(totalSize.width) <= totalRight - totalLeft

        var rowHeights = rows.map { row in row.map(\.size.height).max() ?? 0 }
        if !totalFitsInline { rowHeights.append(totalHeight) }
        rowHeights.append(lastRowHeight)
        let total = topPad + rowHeights.reduce(0, +) + rowGap * CGFloat(rowHeights.count - 1) + bottomPad

        bottomBar.frame = NSRect(x: 0, y: 0, width: width, height: total)

        var rowTop = total - topPad
        for (index, row) in rows.enumerated() {
            let rowHeight = rowHeights[index]
            var itemX = sidePad
            for item in row {
                item.view.frame = NSRect(x: itemX,
                                         y: rowTop - rowHeight + floor((rowHeight - item.size.height) / 2),
                                         width: item.size.width,
                                         height: item.size.height)
                itemX += item.size.width + itemGap
            }
            rowTop -= rowHeight + rowGap
        }

        let lastY = bottomPad
        rescanButton.frame = NSRect(x: sidePad, y: lastY, width: rescanSize.width, height: lastRowHeight)
        removeAllButton.frame = NSRect(x: clearX, y: lastY, width: clearSize.width, height: lastRowHeight)
        footerClearSeparator.frame = NSRect(x: dividerX,
                                            y: lastY + floor((lastRowHeight - 16) / 2),
                                            width: 1,
                                            height: 16)
        if totalFitsInline {
            totalDurationLabel.frame = NSRect(x: totalLeft,
                                              y: lastY + floor((lastRowHeight - totalHeight) / 2),
                                              width: totalRight - totalLeft,
                                              height: totalHeight)
        } else {
            totalDurationLabel.frame = NSRect(x: sidePad,
                                              y: lastY + lastRowHeight + rowGap,
                                              width: available,
                                              height: totalHeight)
        }
        totalDurationLabel.alignment = totalFitsInline ? .right : .left

        let queueHasItems = !items.isEmpty
        deleteButton.isEnabled = queueHasItems
        rescanButton.isEnabled = queueHasItems
        removeAllButton.isEnabled = queueHasItems
        chipGroup.isUndoEnabled = isMarkerRenameUndoAvailable
        return total
    }

    private func layoutEmptyState() {
        let b = emptyStateView.bounds
        let state = currentEmptyState
        let contentW = min(b.width, 260)
        let x = floor((b.width - contentW) / 2)
        let titleH: CGFloat = 20
        let detailH: CGFloat = 48
        let buttonH: CGFloat = 26

        let imageSize: CGFloat = 96
        let circleSize: CGFloat = 44
        let imageBlock: CGFloat = state == .emptyQueue ? imageSize : circleSize
        // image/circle, 10, title, 6, detail, 10, button
        let totalH = imageBlock + 10 + titleH + 6 + detailH + 10 + buttonH
        var y = floor((b.height + totalH) / 2)   // top of the block, y-up

        let showsLogo = state == .emptyQueue
        emptyStateLogoView.isHidden = !showsLogo
        emptyGlyphCircle.isHidden = showsLogo
        if showsLogo {
            y -= imageSize
            emptyStateLogoView.frame = NSRect(x: floor((b.width - imageSize) / 2), y: y, width: imageSize, height: imageSize)
        } else {
            y -= circleSize
            emptyGlyphCircle.frame = NSRect(x: floor((b.width - circleSize) / 2), y: y, width: circleSize, height: circleSize)
        }
        y -= 10 + titleH
        emptyStateLabel.frame = NSRect(x: x, y: y, width: contentW, height: titleH)
        y -= 6 + detailH
        emptyStateDetailLabel.frame = NSRect(x: x, y: y, width: contentW, height: detailH)
        y -= 10 + buttonH
        let buttonW = min(contentW, ceil(emptyStateActionButton.intrinsicContentSize.width))
        emptyStateActionButton.frame = NSRect(x: floor((b.width - buttonW) / 2), y: y, width: buttonW, height: buttonH)
    }

    @objc private func scrollContentDidResize() {
        // Vertical scrolling and vertical-scroller toggles both mutate the clip view.
        // Schedule (do not run inline) so that the synchronous notification chain
        // produced by tile()/setFrame writes cannot recurse on the same call stack.
        scheduleColumnLayout(reason: "clip-geometry-change")
    }

    /// Coalesces column layout requests from frame/bounds notifications.
    /// Multiple notifications fired synchronously while layout is active are merged
    /// into a single deferred run on the next main-run-loop turn.
    private func scheduleColumnLayout(reason: String, force: Bool = false) {
        if let existing = pendingColumnLayout {
            pendingColumnLayout = (reason, existing.force || force)
            return
        }
        pendingColumnLayout = (reason, force)
        if isApplyingColumnLayout { return }  // defer block will drain it
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let req = self.pendingColumnLayout else { return }
            self.pendingColumnLayout = nil
            self.applyColumnLayout(reason: req.reason, forceDiagnostic: req.force)
        }
    }

    /// Single source of truth for queue column layout.
    ///
    /// Duration and Size are compact fixed-width columns (no user resize as of P43.4).
    /// File absorbs the remaining clip-view width. At narrow widths, optional columns
    /// shrink from rightmost-first toward their minimums before File is allowed to
    /// drop below `fileColumnMinimumWidth`. Widths are floored and the rounding
    /// remainder is absorbed by File so the visible columns sum exactly to the clip
    /// width — no horizontal overflow can occur.
    ///
    /// The native `NSTableHeaderView` and row cells both use the table's actual
    /// `NSTableColumn` rects, so header, row, and footer geometry share one
    /// coordinate system.
    private func applyColumnLayout(reason: String, forceDiagnostic: Bool) {
        // ── Reentrancy guard ───────────────────────────────────────────────
        // Any synchronous notification that fires while we are tiling (from
        // tile()/setFrame writes) calls scheduleColumnLayout, which sets
        // pendingColumnLayout and returns. But if applyColumnLayout is called
        // DIRECTLY (from layout(), update(), or toggleDuration/SizeColumn)
        // while already active, capture the request here and let the defer
        // block drain it on the next main-loop turn.
        if isApplyingColumnLayout {
            pendingColumnLayout = (reason, forceDiagnostic || pendingColumnLayout?.force == true)
            return
        }
        isApplyingColumnLayout = true
        defer {
            isApplyingColumnLayout = false
            if let pending = pendingColumnLayout {
                pendingColumnLayout = nil
                DispatchQueue.main.async { [weak self] in
                    self?.applyColumnLayout(reason: pending.reason,
                                            forceDiagnostic: pending.force)
                }
            }
        }

        guard let nameCol = tableView.tableColumn(withIdentifier: Self.colName),
              let durCol  = tableView.tableColumn(withIdentifier: Self.colDur),
              let sizeCol = tableView.tableColumn(withIdentifier: Self.colSize) else { return }

        // Check for clip x drift and log — do NOT scroll/reflect here.
        // LockedHorizontalClipView already enforces x = 0; mutation from inside
        // this method is what created the P43.6 recursive notification storm.
        lockHorizontalClipOrigin(reason: reason)

        let clipView = scrollView.contentView

        let rawAvailable = max(0, floor(clipView.bounds.width))
        let available = rawAvailable

        // Transient startup state: clip has not yet received real dimensions from
        // AppKit (this is normal — the view may enter the hierarchy before the first
        // real layout pass). Assigning zero-width columns would produce corrupt
        // geometry. Log the skip and schedule one coalesced retry so the layout
        // converges once the clip is meaningful. Natural frame/bounds notifications
        // (from layout(), scrollContentDidResize) will also trigger re-entry.
        // Guard the retry on reason to avoid an infinite spin if the clip stays zero.
        if rawAvailable <= 1 || available <= 1 {
            logQueueCoordinateState(reason: reason, outcome: "skipped-zero-clip", force: false)
            if reason != "zero-clip-retry" {
                scheduleColumnLayout(reason: "zero-clip-retry")
            }
            return
        }

        let nameWidth = max(0, floor(available))
        let durWidth: CGFloat = 0
        let sizeWidth: CGFloat = 0

        // ── Idempotent writes ──────────────────────────────────────────────
        // Only write a column width when it has actually changed (≥ 0.5 pt).
        //
        // The table frame is corrected here too: origin.x must converge to 0 and
        // size.width must converge to the available clip width. P43.7 removed all
        // frame writes to break the recursive notification storm; P43.8 restores
        // only this minimal, guarded, idempotent correction.
        //
        // Constraints:
        //   * Only tableView.frame is touched (documentView is tableView; we do
        //     not write scrollView.documentView.frame separately).
        //   * tableView.headerView.frame is NEVER written here — tile() owns it.
        //   * No scroll(to:), scrollToPoint, or reflectScrolledClipView calls.
        //   * The whole block runs under `isApplyingColumnLayout`, so any
        //     synchronous frame-change notification fired by these writes is
        //     coalesced into pendingColumnLayout by scheduleColumnLayout and
        //     never re-enters the call stack.
        //   * tile() is only called when at least one width OR the table frame
        //     was actually changed — avoiding unnecessary notification traffic.
        let tol: CGFloat = 0.5
        var widthsChanged = false
        if abs(nameCol.width - nameWidth) > tol { nameCol.width = nameWidth; widthsChanged = true }
        if !durCol.isHidden && abs(durCol.width - durWidth) > tol { durCol.width = durWidth; widthsChanged = true }
        if !sizeCol.isHidden && abs(sizeCol.width - sizeWidth) > tol { sizeCol.width = sizeWidth; widthsChanged = true }

        let currentFrame = tableView.frame
        let needsOriginFix = abs(currentFrame.origin.x) > tol
        let needsWidthFix  = abs(currentFrame.size.width - available) > tol
        var frameChanged = false
        if needsOriginFix || needsWidthFix {
            var target = currentFrame
            target.origin.x = 0
            target.size.width = available
            tableView.frame = target
            frameChanged = true
        }

        if widthsChanged || frameChanged { tableView.tile() }

        let outcome: String
        switch (widthsChanged, frameChanged) {
        case (true,  true):  outcome = "applied-widths-and-frame"
        case (true,  false): outcome = "applied-widths"
        case (false, true):  outcome = "applied-frame"
        case (false, false): outcome = "skipped"
        }
        logQueueCoordinateState(reason: reason, outcome: outcome, force: forceDiagnostic)
    }

    /// Checks for horizontal clip x drift and logs a warning if detected.
    /// Does NOT call scroll(to:) or reflectScrolledClipView — those calls drive
    /// NSClipView._immediateScrollToPoint, posting a bounds-change notification
    /// that is the root cause of the P43.6 recursive layout storm.
    /// LockedHorizontalClipView.constrainBoundsRect / setBoundsOrigin already
    /// enforce origin.x = 0; if drift appears here a bypass occurred externally.
    private func lockHorizontalClipOrigin(reason: String) {
        let x = scrollView.contentView.bounds.origin.x
        guard abs(x) > 0.5 else { return }
        let msg = "clipX drift reason=\(reason) x=\(String(format: "%.3f", x))"
        DebugConsoleController.log(level: .warning, category: "queue-geometry", message: msg)
        NSLog("dwb queueGeometryWarning %@", msg)
    }

    private func visibleColumnWidthSum() -> CGFloat {
        tableView.tableColumns.reduce(CGFloat(0)) { partial, column in
            column.isHidden ? partial : partial + column.width
        }
    }

    private func columnRectDescription(_ identifier: NSUserInterfaceItemIdentifier) -> String {
        guard let column = tableView.tableColumn(withIdentifier: identifier) else { return "missing" }
        guard !column.isHidden else { return "hidden" }
        let index = tableView.column(withIdentifier: identifier)
        guard index >= 0 else { return "missing-index" }
        return NSStringFromRect(tableView.rect(ofColumn: index))
    }

    private func logQueueCoordinateState(reason: String, outcome: String, force: Bool) {
        if !force {
            let now = Date()
            if let last = lastCoordinateDiagnosticTimeByReason[reason],
               now.timeIntervalSince(last) < 0.75 {
                return
            }
            lastCoordinateDiagnosticTimeByReason[reason] = now
        }

        let clip       = scrollView.contentView
        let clipInPanel = clip.convert(clip.bounds, to: self)
        let visibleClipRight = clipInPanel.maxX
        let docWidth   = scrollView.documentView?.frame.width ?? 0
        let tableFrame = tableView.frame
        let visibleSum = visibleColumnWidthSum()
        let durHidden  = tableView.tableColumn(withIdentifier: Self.colDur)?.isHidden  ?? true
        let sizeHidden = tableView.tableColumn(withIdentifier: Self.colSize)?.isHidden ?? true
        let footerRight = totalDurationRightEdgeInPanel()
        // Diagnostic-only: `guarded` is always 1 here (we only log from inside
        // applyColumnLayout); kept as an explicit field so future readers can
        // grep for it next to outcome.
        let guarded = isApplyingColumnLayout ? 1 : 0
        let message = String(format:
            "reason=%@ outcome=%@ guarded=%d clipX=%.3f clipW=%.3f docW=%.3f" +
            " tableX=%.3f tableW=%.3f visibleColumnSum=%.3f" +
            " fileRect=%@ durationRect=%@ sizeRect=%@" +
            " durationHidden=%@ sizeHidden=%@" +
            " footerRight=%.3f visibleClipRight=%.3f",
            reason, outcome, guarded,
            clip.bounds.origin.x, clip.bounds.width, docWidth,
            tableFrame.origin.x, tableFrame.size.width, visibleSum,
            columnRectDescription(Self.colName),
            columnRectDescription(Self.colDur),
            columnRectDescription(Self.colSize),
            String(durHidden), String(sizeHidden),
            footerRight, visibleClipRight)
        DebugConsoleController.log("queue-geometry", message)
        NSLog("dwb queueGeometry %@", message)

        #if DEBUG
        // Gate geometry invariant checks on clipReady. When the clip has not yet
        // received real AppKit dimensions (e.g. during initial view setup), the
        // values are meaningless and must not trigger diagnostic stops.
        // Warnings remain useful once the clip is ready; they are warning-only —
        // assertionFailure has been removed to allow DEBUG launches to proceed
        // normally through transient startup geometry states.
        let clipReady = window != nil
            && bounds.width > 1
            && bounds.height > 1
            && clip.bounds.width > 1
        if clipReady {
            let tolerance: CGFloat = 0.5
            var warnings: [String] = []
            if abs(clip.bounds.origin.x) > tolerance {
                warnings.append(String(format: "clip.bounds.origin.x %.3f exceeds tolerance",
                                       clip.bounds.origin.x))
            }
            if docWidth > clip.bounds.width + tolerance {
                warnings.append(String(format: "documentView.frame.width %.3f exceeds clip %.3f",
                                       docWidth, clip.bounds.width))
            }
            if tableFrame.size.width > clip.bounds.width + tolerance {
                warnings.append(String(format: "tableView.frame.width %.3f exceeds clip %.3f",
                                       tableFrame.size.width, clip.bounds.width))
            }
            if visibleSum > clip.bounds.width + tolerance {
                warnings.append(String(format: "visible column sum %.3f exceeds clip %.3f",
                                       visibleSum, clip.bounds.width))
            }
            if footerRight > visibleClipRight + tolerance {
                warnings.append(String(format: "footer right edge %.3f exceeds visible clip right %.3f",
                                       footerRight, visibleClipRight))
            }
            if !warnings.isEmpty {
                let warningText = "reason=\(reason) outcome=\(outcome) " + warnings.joined(separator: "; ")
                DebugConsoleController.log(level: .warning, category: "queue-geometry",
                                           message: warningText)
                NSLog("dwb queueGeometryWarning %@", warningText)
                // Warning-only: no assertionFailure until layout has stabilized
                // across startup, queue reload, resize, and column-toggle sequences.
            }
        }
        #endif
    }

    private func centeredY(height: CGFloat, in containerHeight: CGFloat) -> CGFloat {
        floor((containerHeight - height) / 2)
    }

    /// Right edge for the bottom-bar total-duration label, in QueuePageView
    /// coordinates.
    ///
    /// Geometry is derived from the real `NSTableView.rect(ofColumn:)` converted
    /// into this view's coordinate space — no manual panel-coordinate construction
    /// from `scrollView.frame.minX - clipView.bounds.origin.x`. Preference order is
    /// Size → Duration → File so the footer aligns with the rightmost visible
    /// column's text right edge.
    ///
    /// The result is clamped to a footer-safe right limit: visibleClipRight minus
    /// `totalDurationTrailingInset` (72 pt). This intentionally moves the label
    /// left so it sits under the metadata columns rather than hugging the panel
    /// edge. The inset is a footer-only boundary — it does not affect column,
    /// header, or row geometry. The label is additionally bounded by the column
    /// text rect, so it never exceeds the Size column's right text edge.
    private func totalDurationRightEdgeInPanel() -> CGFloat {
        let clipView = scrollView.contentView
        let clipInPanel = clipView.convert(clipView.bounds, to: self)
        let visibleClipRight = clipInPanel.maxX
        // Footer-safe right boundary: keeps the total label visually inside the
        // metadata area rather than at the raw panel edge.
        let footerRightLimit = max(0, visibleClipRight - Self.totalDurationTrailingInset)

        let preferred: [NSUserInterfaceItemIdentifier] = [Self.colSize, Self.colDur, Self.colName]
        for identifier in preferred {
            guard let column = tableView.tableColumn(withIdentifier: identifier),
                  !column.isHidden else { continue }
            let columnIndex = tableView.column(withIdentifier: identifier)
            guard columnIndex >= 0 else { continue }
            let columnRectInTable = tableView.rect(ofColumn: columnIndex)
            guard columnRectInTable.width > 0 else { continue }
            let columnRectInPanel = tableView.convert(columnRectInTable, to: self)
            let textRect = QueueColumnGeometry.textRect(in: columnRectInPanel,
                                                        textHeight: columnRectInPanel.height)
            return min(textRect.maxX, footerRightLimit)
        }
        return footerRightLimit
    }

    private func selectedRowsOrCurrentRowDescending() -> [Int] {
        let selected = tableView.selectedRowIndexes
        if !selected.isEmpty {
            return selected.compactMap { displayIndex(forVisibleRow: $0) }.sorted(by: >)
        }
        return currentDisplayIndexIfVisible().map { [$0] } ?? []
    }

    private var currentSearchQuery: String {
        searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func visibleItem(at row: Int) -> Item? {
        guard row >= 0, row < visibleRows.count else { return nil }
        return visibleRows[row].item
    }

    private func displayIndex(forVisibleRow row: Int) -> Int? {
        guard row >= 0, row < visibleRows.count else { return nil }
        return visibleRows[row].displayIndex
    }

    private func visibleRow(forDisplayIndex displayIndex: Int) -> Int? {
        visibleRows.firstIndex { $0.displayIndex == displayIndex }
    }

    private func currentDisplayIndexIfVisible() -> Int? {
        guard currentDisplayIndex >= 0,
              visibleRow(forDisplayIndex: currentDisplayIndex) != nil else { return nil }
        return currentDisplayIndex
    }

    var selectedItemIDs: Set<String> {
        Set(tableView.selectedRowIndexes.compactMap { visibleItem(at: $0)?.id })
    }

    private func applySearchFilter(preservingSelectedItemIDs selectedItemIDs: Set<String>) {
        let query = currentSearchQuery
        let bookmarkedPaths = BookmarkStore.shared.bookmarkedPaths()
        let pairs = QueueDisplayProjection.filteredPairs(
            from: items,
            displayName: { $0.displayName },
            urlPath: { $0.url.standardizedFileURL.path },
            query: query,
            bookmarkedPaths: bookmarkedPaths,
            bookmarkFilterEnabled: bookmarkFilterEnabled
        )
        visibleToDisplayIndices = pairs.map(\.0)
        visibleItems = pairs.map(\.1)
        rebuildVisibleRows(from: pairs)
        allowsManualReorder = QueueDisplayProjection.allowsManualReorder(
            isManualSort: currentSortMode == .manual,
            query: query,
            bookmarkFilterEnabled: bookmarkFilterEnabled
        )
        updateTotalDurationLabel()
        tableView.reloadData()
        if !selectedItemIDs.isEmpty {
            let remapped = IndexSet(visibleRows.indices.filter { row in
                selectedItemIDs.contains(visibleRows[row].item.id)
            })
            if !remapped.isEmpty {
                tableView.selectRowIndexes(remapped, byExtendingSelection: false)
            } else {
                tableView.deselectAll(nil)
            }
        }
        updateEmptyState()
        updateMarkerChips()
        needsLayout = true
    }

    private func rebuildVisibleRows(from pairs: [(Int, Item)]) {
        visibleRows = pairs.map { VisibleRow(displayIndex: $0.0, item: $0.1) }
    }

    private func updateTotalDurationLabel() {
        totalDurationLabel.stringValue = QueueFooterPresentation.totalText(
            duration: totalDurationText,
            itemCount: items.count,
            visibleCount: visibleItems.count,
            isFiltered: !currentSearchQuery.isEmpty || bookmarkFilterEnabled)
    }

    /// The empty or filtered-empty state in effect, or `nil` while rows are visible.
    private var currentEmptyState: QueueEmptyState? {
        QueueEmptyState.resolve(itemCount: items.count,
                                visibleCount: visibleItems.count,
                                query: currentSearchQuery,
                                bookmarkFilterEnabled: bookmarkFilterEnabled)
    }

    private func updateEmptyState() {
        if let state = currentEmptyState {
            emptyStateLabel.stringValue = state.title
            emptyStateDetailLabel.stringValue = state.detail
            emptyStateActionButton.title = state.actionTitle
            emptyStateActionButton.setAccessibilityLabel(state.actionTitle)
            emptyStateActionButton.toolTip = state == .emptyQueue ? "Add media to the queue" : nil
            emptyGlyphCircle.symbolName = state.glyphName
            emptyStateView.isHidden = false
            scrollView.isHidden = true
        } else {
            emptyStateView.isHidden = true
            scrollView.isHidden = false
        }
        layoutEmptyState()
    }

    @objc private func emptyStateActionTapped() {
        switch currentEmptyState {
        case .emptyQueue:
            delegate?.queuePageDidRequestAddMedia(self)
        case .noMatches:
            clearSearch()
        case .noBookmarks:
            showAllMedia()
        case nil:
            break
        }
    }

    private func clearSearch() {
        searchField.stringValue = ""
        searchFieldChanged()
        window?.makeFirstResponder(self)
    }

    private func showAllMedia() {
        guard bookmarkFilterEnabled else { return }
        bookmarkFilterTapped()
    }

    // MARK: - Actions

    @objc private func closeTapped()  { delegate?.queuePageDidRequestClose(self) }

    @objc private func bookmarkFilterTapped() {
        bookmarkFilterEnabled.toggle()
        updateBookmarkFilterButton()
        let selectedItemIDs = Set(tableView.selectedRowIndexes.compactMap { row -> String? in
            guard let item = visibleItem(at: row) else { return nil }
            return item.id
        })
        applySearchFilter(preservingSelectedItemIDs: selectedItemIDs)
    }

    @objc private func rowClicked() {
        // Single-click selection is handled by NSTableView so Command-click,
        // Shift-click, and keyboard selection extension keep normal AppKit behavior.
    }

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard let displayIndex = displayIndex(forVisibleRow: row) else { return }
        delegate?.queuePage(self, didSelectDisplayIndex: displayIndex)
    }

    @objc private func deleteTapped() {
        let selectedRows = tableView.selectedRowIndexes
        let minRow = selectedRows.min()
        let rows = selectedRowsOrCurrentRowDescending()
        guard !rows.isEmpty else { return }
        if rows.count == 1 {
            delegate?.queuePage(self, didRequestDeleteAt: rows[0])
        } else {
            delegate?.queuePage(self, didRequestDeleteRows: rows)
        }
        if let minRow {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let count = self.tableView.numberOfRows
                guard count > 0 else { return }
                let newRow = min(minRow, count - 1)
                self.tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
                self.tableView.scrollRowToVisible(newRow)
            }
        }
    }

    @objc fileprivate func markerUndoTapped() {
        delegate?.queuePageDidRequestMarkerRenameUndo(self)
    }

    /// Applies a prefix to the selected rows, or to the current item when nothing is selected.
    /// The footer chips and the `N`/`M` keys (while the panel is showing) both call this, so
    /// they always act on the same files.
    func applyPrefix(_ kind: QueueMarkerChip.Kind) {
        guard !items.isEmpty else { return }
        let selected = tableView.selectedRowIndexes
        let displayIndices: [Int]
        if !selected.isEmpty {
            displayIndices = selected.sorted().compactMap { displayIndex(forVisibleRow: $0) }
        } else {
            guard let row = currentDisplayIndexIfVisible() else { return }
            displayIndices = [row]
        }
        guard !displayIndices.isEmpty else { return }
        switch kind {
        case .primary: delegate?.queuePage(self, didRequestCustomPrefixRenameAt: displayIndices)
        case .secondary: delegate?.queuePage(self, didRequestSecondaryCustomPrefixRenameAt: displayIndices)
        }
    }

    @objc private func handleCustomPrefixValueChanged() {
        updateMarkerChips()
    }

    /// The filenames the marker chips act on: the selected rows, or the current item
    /// when nothing is selected.
    private func chipTargetNames() -> [String] {
        let selected = tableView.selectedRowIndexes
        if !selected.isEmpty {
            return selected.compactMap { visibleItem(at: $0)?.displayName }
        }
        guard let current = currentDisplayIndexIfVisible(),
              let name = visibleRow(forDisplayIndex: current).flatMap({ visibleItem(at: $0)?.displayName }) else {
            return []
        }
        return [name]
    }

    private func updateMarkerChips() {
        chipGroup.update(chips: QueueMarkerChip.chips(
            primaryPrefix: SettingsWindowController.customPrefixValue(),
            secondaryPrefix: SettingsWindowController.customPrefixSecondaryValue(),
            targetNames: chipTargetNames(),
            queueHasItems: !items.isEmpty))
        needsLayout = true
    }

    @objc private func rescanTapped() {
        delegate?.queuePageDidRequestRescan(self)
    }

    @objc private func removeAllTapped() {
        delegate?.queuePageDidRequestRemoveAll(self)
    }

    @objc private func sortModeChanged() {
        guard !isUpdatingSortControl,
              let mode = QueueSortMode(rawValue: sortPopUpButton.selectedTag()) else { return }
        delegate?.queuePage(self, didChangeSortMode: mode)
    }

    @objc private func searchFieldChanged() {
        let selectedItemIDs = Set(tableView.selectedRowIndexes.compactMap { row -> String? in
            guard let item = visibleItem(at: row) else { return nil }
            return item.id
        })
        applySearchFilter(preservingSelectedItemIDs: selectedItemIDs)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        searchFieldChanged()
    }

    private func updateBookmarkFilterButton() {
        let symbol = bookmarkFilterEnabled ? "bookmark.fill" : "bookmark"
        bookmarkFilterButton.symbolName = symbol
        bookmarkFilterButton.contentTintColor = bookmarkFilterEnabled ? theme.accentText : DWBAccessibility.textSecondary
        bookmarkFilterButton.state = bookmarkFilterEnabled ? .on : .off
        bookmarkFilterButton.toolTip = bookmarkFilterEnabled ? "Showing bookmarked queue files" : "Show bookmarked queue files"
        bookmarkFilterButton.setAccessibilityValue(bookmarkFilterEnabled ? "on" : "off")
    }

    private func updateSortControlSelection() {
        isUpdatingSortControl = true
        sortPopUpButton.selectItem(withTag: currentSortMode.rawValue)
        sortTitleView.stringValue = sortPopUpButton.titleOfSelectedItem ?? "Sort: \(currentSortMode.title)"
        isUpdatingSortControl = false
    }

    private func updateHeaderSortIndicators() {
        tableView.tableColumn(withIdentifier: Self.colName)?.headerCell.stringValue = headerTitle("File",
                                                                                                  ascendingMode: .filenameAscending,
                                                                                                  descendingMode: .filenameDescending)
        tableView.tableColumn(withIdentifier: Self.colDur)?.headerCell.stringValue = headerTitle("Duration",
                                                                                                 ascendingMode: .durationAscending,
                                                                                                 descendingMode: .durationDescending)
        tableView.tableColumn(withIdentifier: Self.colSize)?.headerCell.stringValue = headerTitle("Size",
                                                                                                  ascendingMode: .fileSizeAscending,
                                                                                                  descendingMode: .fileSizeDescending)
        tableView.headerView?.needsDisplay = true
    }

    private func headerTitle(_ base: String,
                             ascendingMode: QueueSortMode,
                             descendingMode: QueueSortMode) -> String {
        if currentSortMode == ascendingMode {
            return "\(base) ^"
        }
        if currentSortMode == descendingMode {
            return "\(base) v"
        }
        return base
    }

    private func nextHeaderSortMode(for column: NSTableColumn) -> QueueSortMode? {
        switch column.identifier {
        case Self.colName:
            return currentSortMode == .filenameAscending ? .filenameDescending : .filenameAscending
        case Self.colDur:
            return currentSortMode == .durationAscending ? .durationDescending : .durationAscending
        case Self.colSize:
            return currentSortMode == .fileSizeAscending ? .fileSizeDescending : .fileSizeAscending
        default:
            return nil
        }
    }

    // MARK: - Column visibility menu

    private func makeColumnVisibilityMenu() -> NSMenu {
        let menu = NSMenu()
        menu.title = "Columns"

        let durCol  = tableView.tableColumn(withIdentifier: Self.colDur)
        let sizeCol = tableView.tableColumn(withIdentifier: Self.colSize)

        let durItem = NSMenuItem(title: "Duration",
                                 action: #selector(toggleDurationColumn),
                                 keyEquivalent: "")
        durItem.target = self
        durItem.state = (durCol?.isHidden == false) ? .on : .off
        menu.addItem(durItem)

        let sizeItem = NSMenuItem(title: "Size",
                                  action: #selector(toggleSizeColumn),
                                  keyEquivalent: "")
        sizeItem.target = self
        sizeItem.state = (sizeCol?.isHidden == false) ? .on : .off
        menu.addItem(sizeItem)

        return menu
    }

    @objc private func toggleDurationColumn() {
        guard let col = tableView.tableColumn(withIdentifier: Self.colDur) else { return }
        let nowVisible = !col.isHidden
        col.isHidden = nowVisible
        if !col.isHidden { col.width = Self.durationColumnDefaultWidth }
        UserDefaults.standard.set(!nowVisible, forKey: Self.durationColumnVisibleKey)
        applyColumnLayout(reason: "toggle-duration", forceDiagnostic: true)
        needsLayout = true
    }

    @objc private func toggleSizeColumn() {
        guard let col = tableView.tableColumn(withIdentifier: Self.colSize) else { return }
        let nowVisible = !col.isHidden
        col.isHidden = nowVisible
        if !col.isHidden { col.width = Self.sizeColumnDefaultWidth }
        UserDefaults.standard.set(!nowVisible, forKey: Self.sizeColumnVisibleKey)
        applyColumnLayout(reason: "toggle-size", forceDiagnostic: true)
        needsLayout = true
    }

    private func makeContextMenu(for row: Int) -> NSMenu {
        guard displayIndex(forVisibleRow: row) != nil else { return NSMenu() }
        let menu = NSMenu()
        addContextItem("Play", action: #selector(contextPlay(_:)), row: row, to: menu)
        menu.addItem(.separator())
        addContextItem("Reveal in Finder", action: #selector(contextReveal(_:)), row: row, to: menu)
        addContextItem("Rename...", action: #selector(contextRename(_:)), row: row, to: menu)
        menu.addItem(.separator())
        addContextItem(QueueRemovalPresentation.contextMenuItemTitle, action: #selector(contextDelete(_:)), row: row, to: menu)
        return menu
    }

    private func addContextItem(_ title: String, action: Selector, row: Int, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = displayIndex(forVisibleRow: row)
        menu.addItem(item)
    }

    @objc private func contextPlay(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        delegate?.queuePage(self, didSelectDisplayIndex: row)
    }

    @objc private func contextReveal(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        delegate?.queuePage(self, didRequestRevealAt: row)
    }

    @objc private func contextRename(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        delegate?.queuePage(self, didRequestRenameAt: row)
    }

    @objc private func contextDelete(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        delegate?.queuePage(self, didRequestDeleteAt: row)
    }
}

final class QueuePageTableView: NSTableView {
    var contextMenuProvider: ((Int) -> NSMenu?)?
    /// Called when Delete or Backspace is pressed with one or more selected rows.
    /// Indices are sorted descending so the caller can remove them safely.
    var deleteRowsHandler: (([Int]) -> Void)?

    // MARK: Drop line (design system 9.7)

    private let dropIndicator = QueueDropIndicatorView()

    /// Shows the 2 pt `accentText` drop line, with its ring, in the gap above `row`
    /// (or below the last row), inset 4 pt on each side.
    func showDropIndicator(beforeRow row: Int) {
        guard numberOfRows > 0 else {
            hideDropIndicator()
            return
        }
        let boundaryY = row < numberOfRows ? rect(ofRow: row).minY : rect(ofRow: numberOfRows - 1).maxY
        let side = DWBMetrics.queueRowInset
        dropIndicator.frame = NSRect(x: side,
                                     y: boundaryY - DWBMetrics.dropRing / 2,
                                     width: max(0, bounds.width - side * 2),
                                     height: DWBMetrics.dropRing)
        if dropIndicator.superview == nil { addSubview(dropIndicator) }
        dropIndicator.isHidden = false
    }

    func hideDropIndicator() {
        dropIndicator.isHidden = true
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        hideDropIndicator()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        super.draggingEnded(sender)
        hideDropIndicator()
    }

    // Select on mouseDown so the highlight appears immediately, before drag detection
    // and before the action fires on mouseUp. Without this, selectionHighlightStyle = .none
    // means the system never automatically selects, and the visual update can lag or miss.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .shift, .option]).isEmpty {
            let point = convert(event.locationInWindow, from: nil)
            let r = row(at: point)
            if r >= 0 { selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false) }
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return contextMenuProvider?(row)
    }

    override func keyDown(with event: NSEvent) {
        // keyCode 51 = Delete (backspace), keyCode 117 = Forward Delete
        if event.keyCode == 51 || event.keyCode == 117 {
            let rows = selectedRowIndexes
            guard !rows.isEmpty else { return }
            let minRow = rows.min() ?? 0
            deleteRowsHandler?(rows.sorted(by: >))
            // Re-select the nearest row after the table reloads.
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let count = self.numberOfRows
                guard count > 0 else { return }
                let newRow = min(minRow, count - 1)
                self.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
                self.scrollRowToVisible(newRow)
            }
            return
        }

        super.keyDown(with: event)
    }
}

// MARK: - NSTableViewDataSource

extension QueuePageView: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int { visibleRows.count }

    // MARK: Drag source — write dragged row index to pasteboard

    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard allowsManualReorder else { return nil }
        guard let displayIndex = displayIndex(forVisibleRow: row) else { return nil }
        // This view preserves the pre-existing single-row reorder model. Multi-row
        // selection is supported, but multi-row drag reorder is intentionally not.
        guard tableView.selectedRowIndexes.count <= 1 else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(displayIndex), forType: Self.draggedRowType)
        return item
    }

    // MARK: Drop target — accept only same-table moves, inserting between rows

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard allowsManualReorder else {
            (tableView as? QueuePageTableView)?.hideDropIndicator()
            return []
        }
        // Only accept drops that insert between rows (not on top of a row)
        if dropOperation != .above {
            tableView.setDropRow(row, dropOperation: .above)
        }
        (tableView as? QueuePageTableView)?.showDropIndicator(beforeRow: row)
        return .move
    }

    // The dragged row stays in place at 0.4 alpha until the drag ends.
    func tableView(_ tableView: NSTableView,
                   draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint,
                   forRowIndexes rowIndexes: IndexSet) {
        for row in rowIndexes {
            tableView.rowView(atRow: row, makeIfNecessary: false)?.alphaValue = 0.4
        }
    }

    func tableView(_ tableView: NSTableView,
                   draggingSession session: NSDraggingSession,
                   endedAt screenPoint: NSPoint,
                   operation: NSDragOperation) {
        tableView.enumerateAvailableRowViews { rowView, _ in rowView.alphaValue = 1 }
        (tableView as? QueuePageTableView)?.hideDropIndicator()
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard allowsManualReorder else { return false }
        guard let str = info.draggingPasteboard.string(forType: Self.draggedRowType),
              let from = Int(str) else { return false }
        let to = displayInsertionIndex(forVisibleRow: row)
        // No-op: drop on same position or the position immediately below the source
        guard from != to, from != to - 1 else { return false }
        delegate?.queuePage(self, didReorderFromIndex: from, toIndex: to)
        return true
    }

    private func displayInsertionIndex(forVisibleRow row: Int) -> Int {
        guard row < visibleRows.count else { return items.count }
        if let displayIndex = displayIndex(forVisibleRow: row) {
            return displayIndex
        }
        var nextRow = row + 1
        while nextRow < visibleRows.count {
            if let displayIndex = displayIndex(forVisibleRow: nextRow) {
                return displayIndex
            }
            nextRow += 1
        }
        return items.count
    }
}

// MARK: - NSTableViewDelegate

extension QueuePageView: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard let mode = nextHeaderSortMode(for: tableColumn) else { return }
        delegate?.queuePage(self, didChangeSortMode: mode)
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard row < visibleRows.count, let colID = tableColumn?.identifier else { return nil }
        guard colID == Self.colName else { return nil }

        guard let item = visibleItem(at: row), let displayIndex = displayIndex(forVisibleRow: row) else { return nil }
        let isCurrent = displayIndex == currentDisplayIndex

        let reuseID = NSUserInterfaceItemIdentifier("qpMediaCell")
        var cell = tableView.makeView(withIdentifier: reuseID, owner: nil) as? QueuePageCell
        if cell == nil {
            cell = QueuePageCell(reuseID: reuseID)
        }

        cell?.configure(item: item,
                        isCurrent: isCurrent,
                        searchQuery: currentSearchQuery,
                        primaryPrefix: SettingsWindowController.customPrefixValue(),
                        secondaryPrefix: SettingsWindowController.customPrefixSecondaryValue())
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Self.rowPitch
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row >= 0, row < visibleRows.count else { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rv = QueuePageRowView()
        guard row >= 0, row < visibleRows.count else { return rv }
        if let displayIndex = displayIndex(forVisibleRow: row) {
            rv.isCurrent = displayIndex == currentDisplayIndex
        } else {
            rv.isCurrent = false
        }
        return rv
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateMarkerChips()
    }
}

// MARK: - QueuePageCell

fileprivate struct QueueColumnGeometry {
    let identifier: NSUserInterfaceItemIdentifier
    let title: String
    let alignment: NSTextAlignment
    let columnRect: NSRect
    let textRect: NSRect

    static func textRect(in rect: NSRect, textHeight: CGFloat) -> NSRect {
        NSRect(x: rect.minX + QueuePageView.cellLeadingPadding,
               y: rect.minY + floor((rect.height - textHeight) / 2),
               width: max(0, rect.width - QueuePageView.cellLeadingPadding - QueuePageView.cellTrailingPadding),
               height: textHeight)
    }
}

// MARK: - Native Queue Table Header

private final class QueueSearchSortPillView: NSView {
    weak var searchField: NSSearchField?
    var searchFocusRect: NSRect = .zero

    /// `surfaceElevated` ground with a 1 pt `border` (strong under Increase Contrast), radius 12.
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusPill, yRadius: DWBMetrics.radiusPill)
        DWBColor.surfaceElevated.setFill()
        path.fill()
        DWBAccessibility.border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if searchFocusRect.contains(point),
           let searchField = searchField,
           !searchField.isHidden,
           searchField.frame.width > 0 {
            window?.makeFirstResponder(searchField)
            return
        }
        super.mouseDown(with: event)
    }
}

private final class QueuePassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class QueueSearchFieldCell: NSSearchFieldCell {
    private let textLeading: CGFloat = 0
    private let textTrailing: CGFloat = 6
    private let cancelButtonSize: CGFloat = 14
    private let cancelButtonTrailing: CGFloat = 3
    private let cancelButtonGap: CGFloat = 4

    override init(textCell string: String) {
        super.init(textCell: string)
        // NSCell.init(textCell:) creates a non-editable label cell; restore editability.
        isEditable = true
        usesSingleLineMode = true
        isScrollable = true
        lineBreakMode = .byClipping
    }

    required init(coder: NSCoder) { fatalError() }

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        .zero
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        guard !stringValue.isEmpty else { return .zero }
        return NSRect(x: rect.maxX - cancelButtonTrailing - cancelButtonSize,
                      y: rect.minY + floor((rect.height - cancelButtonSize) / 2),
                      width: cancelButtonSize,
                      height: cancelButtonSize)
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        let cancelRect = cancelButtonRect(forBounds: rect)
        let rightEdge = cancelRect.isEmpty ? rect.maxX : cancelRect.minX - cancelButtonGap
        let x = rect.minX + textLeading
        let width = max(0, rightEdge - x - textTrailing)
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textHeight = ceil(font.ascender - font.descender + font.leading)
        return NSRect(x: x,
                      y: rect.minY + floor((rect.height - textHeight) / 2),
                      width: width,
                      height: textHeight)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        searchTextRect(forBounds: rect)
    }

    override func edit(withFrame rect: NSRect,
                       in controlView: NSView,
                       editor textObj: NSText,
                       delegate: Any?,
                       event: NSEvent?) {
        super.edit(withFrame: searchTextRect(forBounds: rect),
                   in: controlView,
                   editor: textObj,
                   delegate: delegate,
                   event: event)
    }

    override func select(withFrame rect: NSRect,
                         in controlView: NSView,
                         editor textObj: NSText,
                         delegate: Any?,
                         start selStart: Int,
                         length selLength: Int) {
        super.select(withFrame: searchTextRect(forBounds: rect),
                     in: controlView,
                     editor: textObj,
                     delegate: delegate,
                     start: selStart,
                     length: selLength)
    }
}

private final class QueueTransparentPopUpButtonCell: NSPopUpButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {}
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {}
}

private final class QueueHeaderSymbolButton: NSButton {
    private let symbolView = QueueCenteredSymbolView()

    /// Toggled on: `accentTintStrong` fill, 1 pt `accentFill` edge, `accentText` glyph.
    var isOn = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isOn else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusControl, yRadius: DWBMetrics.radiusControl)
        theme.accentTintStrong.setFill()
        path.fill()
        theme.accentFill.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    var symbolName: String? {
        get { symbolView.symbolName }
        set { symbolView.symbolName = newValue }
    }

    var symbolPointSize: CGFloat {
        get { symbolView.pointSize }
        set { symbolView.pointSize = newValue }
    }

    var symbolWeight: NSFont.Weight {
        get { symbolView.weight }
        set { symbolView.weight = newValue }
    }

    override var contentTintColor: NSColor? {
        didSet {
            symbolView.color = contentTintColor ?? DWBAccessibility.textSecondary
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        image = nil
        symbolView.color = contentTintColor ?? DWBAccessibility.textSecondary
        addSubview(symbolView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        symbolView.frame = bounds
    }
}

private final class QueueCenteredSymbolView: NSView {
    var symbolName: String? {
        didSet { rebuildImage() }
    }
    var pointSize: CGFloat = 13 {
        didSet { rebuildImage() }
    }
    var weight: NSFont.Weight = .regular {
        didSet { rebuildImage() }
    }
    var color: NSColor = DWBColor.textPrimary {
        didSet { needsDisplay = true }
    }
    private var symbolImage: NSImage?

    func configure(symbolName: String,
                   pointSize: CGFloat,
                   weight: NSFont.Weight,
                   color: NSColor,
                   accessibilityDescription: String?) {
        self.pointSize = pointSize
        self.weight = weight
        self.color = color
        self.symbolName = symbolName
        setAccessibilityElement(accessibilityDescription != nil)
        if let accessibilityDescription {
            setAccessibilityLabel(accessibilityDescription)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let symbolImage else { return }
        let alignmentRect = symbolImage.alignmentRect
        let drawOrigin = NSPoint(x: bounds.midX - alignmentRect.midX,
                                 y: bounds.midY - alignmentRect.midY)
        let drawRect = NSRect(origin: drawOrigin, size: symbolImage.size)
        symbolImage.draw(in: drawRect,
                         from: .zero,
                         operation: .sourceOver,
                         fraction: 1.0,
                         respectFlipped: true,
                         hints: nil)
        color.setFill()
        drawRect.fill(using: .sourceAtop)
    }

    private func rebuildImage() {
        guard let symbolName,
              let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            symbolImage = nil
            needsDisplay = true
            return
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        symbolImage = image.withSymbolConfiguration(configuration) ?? image
        symbolImage?.isTemplate = true
        needsDisplay = true
    }
}

private final class QueueCenteredTextView: NSView {
    var stringValue: String = "" {
        didSet { needsDisplay = true }
    }
    var font: NSFont = .systemFont(ofSize: 10.5, weight: .regular) {
        didSet { needsDisplay = true }
    }
    var textColor: NSColor = DWBColor.textPrimary {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .left
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let textHeight = ceil(font.ascender - font.descender + font.leading)
        let textRect = NSRect(x: 0,
                              y: bounds.minY + floor((bounds.height - textHeight) / 2),
                              width: bounds.width,
                              height: textHeight)
        (stringValue as NSString).draw(in: textRect, withAttributes: attrs)
    }
}

private final class LockedHorizontalClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        rect.origin.x = 0
        return rect
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(NSPoint(x: 0, y: newOrigin.y))
    }
}

private final class QueueTableHeaderView: NSTableHeaderView {
    var menuProvider: (() -> NSMenu?)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = DWBColor.surfaceElevated.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        DWBColor.surfaceElevated.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }
}

private final class QueueColumnHeaderCell: NSTableHeaderCell {
    private let textAlignment: NSTextAlignment

    init(title: String, alignment: NSTextAlignment) {
        self.textAlignment = alignment
        super.init(textCell: title)
        self.stringValue = title
        self.alignment = alignment
    }

    required init(coder: NSCoder) { fatalError() }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        paragraph.alignment = textAlignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: DWBAccessibility.textTertiary,
            .paragraphStyle: paragraph
        ]
        let labelRect = QueueColumnGeometry.textRect(in: cellFrame, textHeight: 11)
        stringValue.draw(in: labelRect, withAttributes: attrs)

        DWBColor.gridLine.setFill()
        NSRect(x: floor(cellFrame.maxX), y: cellFrame.minY + 3, width: 1, height: max(0, cellFrame.height - 6)).fill()
    }

    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        draw(withFrame: cellFrame, in: controlView)
    }
}
