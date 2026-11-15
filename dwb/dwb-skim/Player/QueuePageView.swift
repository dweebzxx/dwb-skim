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
    /// `origin` says whether the `N` key or a footer chip made the request; only the key may advance (P52).
    func queuePage(_ view: QueuePageView, didRequestCustomPrefixRenameAt indices: [Int], origin: PrefixPressOrigin)
    /// Called when the user triggers the secondary custom prefix rename action (feature-gated).
    /// `indices` is always ascending. Caller must preflight all targets before renaming any.
    /// `origin` says whether the `M` key or a footer chip made the request; only the key may advance (P52).
    func queuePage(_ view: QueuePageView, didRequestSecondaryCustomPrefixRenameAt indices: [Int], origin: PrefixPressOrigin)
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
    private var totalDurationText = MediaFileSupport.formatClockDuration(0)
    private var bookmarkFilterEnabled = false

    /// True while the owning window holds a marker rename undo step; enables
    /// the footer undo button.
    var isMarkerRenameUndoAvailable: Bool = false {
        didSet {
            updateFooterState()
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
        updateHeaderState()
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

    /// The retired source strip's information now lives on Rescan: the full path, or "Individual files",
    /// in its tooltip and accessibility help ("Original source: ...").
    private func updateOriginalRoot(_ url: URL?) {
        footerView.setRescanSource(url?.path ?? "Individual files")
    }

    // MARK: - Subviews

    private let headerView       = QueueHeaderView()
    let scrollView               = NSScrollView()
    let tableView                = QueuePageTableView()
    private let emptyStateView   = QueueEmptyStateView()
    private let footerView       = QueueFooterView()
    private var searchField: QueueSearchTextField { headerView.searchField }

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
        // One 52 pt row: search, sort, bookmark filter, close. No title.
        headerView.searchField.delegate = self
        headerView.searchField.target = self
        headerView.searchField.action = #selector(searchFieldChanged)
        headerView.onClearSearch = { [weak self] in self?.clearSearchKeepingFocus() }
        headerView.onSortModeChosen = { [weak self] mode in
            guard let self else { return }
            self.delegate?.queuePage(self, didChangeSortMode: mode)
        }
        headerView.onBookmarkFilterToggled = { [weak self] in self?.bookmarkFilterTapped() }
        headerView.onCloseRequested = { [weak self] in self?.closeTapped() }
        addSubview(headerView)
        updateHeaderState()

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
        tableView.rowHeight    = DWBMetrics.queueFlatRowHeight
        // Plain rows span the full clip width; each row draws its own card 6 pt in from the left and
        // 10 pt in from the right (`QueueRowMetrics.cardFrame`).
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

        // Enable row reordering via drag-and-drop. The insertion line is drawn by the table
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
        // List padding 0 / 6 / 12: the sides are inside each row; the bottom 12 pt is a content inset.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: DWBMetrics.queueListBottomPadding, right: 0)
        scrollView.hasVerticalScroller     = true
        scrollView.hasHorizontalScroller   = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true
        scrollView.autohidesScrollers      = true
        scrollView.borderType              = .noBorder
        scrollView.backgroundColor         = .clear
        addSubview(scrollView)

        // ── Empty and filtered-empty states ───────────────────────────────
        emptyStateView.onAction = { [weak self] state in self?.emptyStateActionTapped(state) }
        addSubview(emptyStateView)

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

        // ── Footer: two rows, always ──────────────────────────────────────
        // Remove · primary prefix · secondary prefix · Undo over Rescan · total · Clear queue.
        // The footer buttons call the same routes the old footer did; `.footerChip` never advances (P52).
        footerView.onRemove = { [weak self] in self?.deleteTapped() }
        footerView.onPrefix = { [weak self] kind in self?.applyPrefix(kind, origin: .footerChip) }
        footerView.onUndo = { [weak self] in self?.markerUndoTapped() }
        footerView.onRescan = { [weak self] in self?.rescanTapped() }
        footerView.onClearQueue = { [weak self] in self?.removeAllTapped() }
        addSubview(footerView)

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

        DispatchQueue.main.async { [weak self] in
            self?.applyColumnLayout(reason: "queue-setup", forceDiagnostic: true)
        }
        updateEmptyState()
        updateFooterState()
        updateFooterTotal()
    }

    @objc private func accessibilityDidChange() {
        tableView.reloadData()
    }

    // MARK: - Layout

    /// The panel's geometry, top to bottom: the 52 pt header (its own 1 pt gridLine rule inside it), the list, and the
    /// 78 pt two-row footer. Compact below 390 pt, which is every supported panel width.
    override func layout() {
        super.layout()
        let b = bounds
        let footerH = QueueFooterLayout.height
        let headerH = QueueHeaderLayout.height

        footerView.frame = NSRect(x: 0, y: 0, width: b.width, height: footerH)
        headerView.frame = NSRect(x: 0, y: max(0, b.height - headerH), width: b.width, height: headerH)

        let listHeight = max(0, b.height - headerH - footerH)
        scrollView.frame = NSRect(x: 0, y: footerH, width: b.width, height: listHeight)
        emptyStateView.frame = scrollView.frame
        scrollView.layoutSubtreeIfNeeded()
        // Do not manually set tableView.headerView.frame here — tile() owns header width,
        // and writing it inside a layout pass posts a frame-change notification that fed
        // back into the P43.6 recursive layout storm.
        applyColumnLayout(reason: "layout", forceDiagnostic: false)
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

    /// Right edge of the footer's total cell, in QueuePageView coordinates (queue-geometry diagnostics only).
    private func totalDurationRightEdgeInPanel() -> CGFloat {
        footerView.convert(NSPoint(x: footerView.totalRightEdge, y: 0), to: self).x
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
        updateFooterTotal()
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
        updateFooterState()
        needsLayout = true
    }

    private func rebuildVisibleRows(from pairs: [(Int, Item)]) {
        visibleRows = pairs.map { VisibleRow(displayIndex: $0.0, item: $0.1) }
    }

    /// The status row's total: the window's whole-queue duration, with the visible count while a search or
    /// bookmark filter is active. The footer fits it to its center cell by measurement.
    private func updateFooterTotal() {
        footerView.setTotal(durationText: totalDurationText,
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
            emptyStateView.configure(state: state)
            emptyStateView.isHidden = false
            scrollView.isHidden = true
        } else {
            emptyStateView.isHidden = true
            scrollView.isHidden = false
        }
    }

    private func emptyStateActionTapped(_ state: QueueEmptyState) {
        switch state {
        case .emptyQueue:
            delegate?.queuePageDidRequestAddMedia(self)
        case .noMatches:
            clearSearch()
        case .noBookmarks:
            showAllMedia()
        }
    }

    private func clearSearch() {
        searchField.stringValue = ""
        searchFieldChanged()
        window?.makeFirstResponder(self)
    }

    /// The header's clear button: removes only the query, and keeps the field ready for typing.
    private func clearSearchKeepingFocus() {
        searchField.stringValue = ""
        searchFieldChanged()
        window?.makeFirstResponder(searchField)
    }

    private func showAllMedia() {
        guard bookmarkFilterEnabled else { return }
        bookmarkFilterTapped()
    }

    // MARK: - Actions

    @objc private func closeTapped()  { delegate?.queuePageDidRequestClose(self) }

    @objc private func bookmarkFilterTapped() {
        bookmarkFilterEnabled.toggle()
        updateHeaderState()
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
    /// they always act on the same files. `origin` tells them apart for the advance-after-prefix
    /// rule: the chips pass `.footerChip` and never advance; the keys pass `.key`.
    func applyPrefix(_ kind: QueueMarkerChip.Kind, origin: PrefixPressOrigin) {
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
        case .primary: delegate?.queuePage(self, didRequestCustomPrefixRenameAt: displayIndices, origin: origin)
        case .secondary: delegate?.queuePage(self, didRequestSecondaryCustomPrefixRenameAt: displayIndices, origin: origin)
        }
    }

    @objc private func handleCustomPrefixValueChanged() {
        updateFooterState()
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

    /// Refreshes the footer's marker cells, Remove and Undo from the same targets the actions use: the selected
    /// rows, or the visible current item when nothing is selected. The applied dot and mixed ring describe exactly
    /// these files (`QueueMarkerChip` classifies them with `SkimReviewStatusDescriptor`, like the renamer).
    private func updateFooterState() {
        let targets = chipTargetNames()
        footerView.update(chips: QueueMarkerChip.chips(
                              primaryPrefix: SettingsWindowController.customPrefixValue(),
                              secondaryPrefix: SettingsWindowController.customPrefixSecondaryValue(),
                              targetNames: targets,
                              queueHasItems: !items.isEmpty,
                              hasTargets: !targets.isEmpty),
                          canRemove: !targets.isEmpty,
                          canUndo: isMarkerRenameUndoAvailable,
                          hasItems: !items.isEmpty)
        needsLayout = true
    }

    @objc private func rescanTapped() {
        delegate?.queuePageDidRequestRescan(self)
    }

    @objc private func removeAllTapped() {
        delegate?.queuePageDidRequestRemoveAll(self)
    }

    @objc private func searchFieldChanged() {
        let selectedItemIDs = Set(tableView.selectedRowIndexes.compactMap { row -> String? in
            guard let item = visibleItem(at: row) else { return nil }
            return item.id
        })
        applySearchFilter(preservingSelectedItemIDs: selectedItemIDs)
        headerView.searchTextDidChange()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        searchFieldChanged()
    }

    /// The header's sort button and bookmark filter follow the sort mode and the filter flag.
    private func updateHeaderState() {
        headerView.configure(sortMode: currentSortMode, bookmarkFilterOn: bookmarkFilterEnabled)
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

    // MARK: Insertion line (design system 10.4)

    private let dropIndicator = QueueDropIndicatorView()

    /// Shows the straight 2 pt `accentText` insertion line on the shared edge above `row` (or below the last row),
    /// across the row cards' width. After the playing row it sits on the card's bottom edge, above the 4 pt gap.
    func showDropIndicator(beforeRow row: Int) {
        guard numberOfRows > 0 else {
            hideDropIndicator()
            return
        }
        let previousIndex = min(row, numberOfRows) - 1
        let previous = previousIndex >= 0 ? rect(ofRow: previousIndex) : nil
        let boundaryY = QueueRowMetrics.dropLineBoundaryY(
            rowMinY: row < numberOfRows ? rect(ofRow: row).minY : nil,
            previousRowMaxY: previous?.maxY,
            previousIsCurrent: previous.map { abs($0.height - DWBMetrics.queuePlayingRowHeight) < 0.5 } ?? false)
        let card = QueueRowMetrics.cardFrame(rowWidth: bounds.width, isCurrent: false)
        dropIndicator.frame = NSRect(x: card.minX,
                                     y: boundaryY - DWBMetrics.dropLine / 2,
                                     width: card.width,
                                     height: DWBMetrics.dropLine)
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
            tableView.rowView(atRow: row, makeIfNecessary: false)?.alphaValue = DWBMetrics.queueRowDragAlpha
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

    /// 44 pt for a flat row; 52 pt for the current item's card (48 pt plus its 4 pt gap).
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let displayIndex = displayIndex(forVisibleRow: row) else { return DWBMetrics.queueFlatRowHeight }
        return QueueRowMetrics.height(isCurrent: displayIndex == currentDisplayIndex)
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
        updateFooterState()
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

// MARK: - Table support

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
