import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {

    private let maxPlayerWindowCount = 5

    var windowControllers: [PlayerWindowController] = []
    private var hasReceivedOpenEventDuringLaunch = false
    private var optionDoubleTapCoordinator: OptionDoubleTapCoordinator?
    /// Player windows in most-recently-key-first order. Drives Dock reopen when
    /// no player window is currently key.
    private var playerActivationOrder: [ObjectIdentifier] = []
    private var playerActivationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        DWBAccessibility.install()
        SettingsWindowController.registerDefaults()
        _ = DebugConsoleController.shared   // eagerly init so it observes settings from launch
        buildMainMenu()
        installShortcutObserver()
        installOptionDoubleTapCoordinator()
        installPlayerActivationTracking()
        openInitialPlayerWindowIfNeeded()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        DebugConsoleController.log("app", "launched: version=\(version) build=\(build) pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        optionDoubleTapCoordinator?.stop()
        optionDoubleTapCoordinator = nil
        (NSApp as? SkimApplication)?.optionDoubleTapCoordinator = nil
        if let playerActivationObserver {
            NotificationCenter.default.removeObserver(playerActivationObserver)
            self.playerActivationObserver = nil
        }
        DebugConsoleController.log("app", "terminating")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        openSubmittedURLs(urls, source: "openFiles")
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openSubmittedURLs([URL(fileURLWithPath: filename)], source: "openFile")
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openSubmittedURLs(urls, source: "openURLs")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        pruneClosedPlayerWindowControllers()

        // A player window still "exists" while minimized or ordered out, even
        // though NSWindow.isVisible reports false for both. Membership here is
        // having a live window object, so a Dock click on a minimized player
        // raises it instead of building a duplicate.
        let controllersByIdentifier = Dictionary(
            windowControllers.compactMap { wc in wc.window.map { _ in (wc.debugIdentity, wc) } },
            uniquingKeysWith: { first, _ in first }
        )
        let candidates = windowControllers.compactMap { wc -> PlayerWindowReactivationCandidate? in
            guard let window = wc.window else { return nil }
            return PlayerWindowReactivationCandidate(
                identifier: wc.debugIdentity,
                isKeyWindow: window.isKeyWindow,
                isMiniaturized: window.isMiniaturized,
                isOnScreen: window.isVisible,
                activationRank: activationRank(of: wc)
            )
        }

        switch PlayerWindowReactivationPlanner.plan(candidates: candidates) {
        case .createNewPlayerWindow:
            DebugConsoleController.log("window", "reopen: noExistingPlayer -> openNewPlayerWindow")
            _ = openNewPlayerWindow()
        case .raiseExisting(let identifier, let needsDeminiaturize, let needsOrderFront):
            guard let wc = controllersByIdentifier[identifier], let window = wc.window else { break }
            if needsDeminiaturize { window.deminiaturize(nil) }
            if needsOrderFront { window.makeKeyAndOrderFront(nil) }
            noteWindowActivated(wc)
            DebugConsoleController.log("window", "reopen: raised=\(identifier) deminiaturize=\(needsDeminiaturize) orderFront=\(needsOrderFront)")
        }

        sender.activate(ignoringOtherApps: true)
        return false
    }

    // MARK: - Player activation recency

    private func installPlayerActivationTracking() {
        guard playerActivationObserver == nil else { return }
        playerActivationObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let wc = (note.object as? NSWindow)?.windowController as? PlayerWindowController else { return }
            self.noteWindowActivated(wc)
        }
    }

    private func noteWindowActivated(_ wc: PlayerWindowController) {
        let id = ObjectIdentifier(wc)
        playerActivationOrder.removeAll { $0 == id }
        playerActivationOrder.insert(id, at: 0)
        pruneActivationOrder()
    }

    /// 0 == most recently key. Never-activated windows sort after every
    /// window that has been key at least once.
    private func activationRank(of wc: PlayerWindowController) -> Int {
        playerActivationOrder.firstIndex(of: ObjectIdentifier(wc)) ?? playerActivationOrder.count
    }

    private func pruneActivationOrder() {
        let live = Set(windowControllers.map(ObjectIdentifier.init))
        playerActivationOrder.removeAll { !live.contains($0) }
    }

    // MARK: - Window management

    @discardableResult
    func openNewPlayerWindow() -> PlayerWindowController? {
        pruneClosedPlayerWindowControllers()
        guard windowControllers.count < maxPlayerWindowCount else {
            presentWindowCapDenial(context: "new-window")
            return nil
        }
        let wc = PlayerWindowController()
        // Cascade from the most recently opened window so new windows don't
        // stack exactly on top of existing ones.  cascadeTopLeft(from:) uses
        // AppKit's standard bottom-left origin screen coordinates; the "top-left"
        // of a window is (frame.minX, frame.maxY).
        if let prevWindow = windowControllers.last?.window {
            wc.window?.cascadeTopLeft(from: NSPoint(x: prevWindow.frame.minX,
                                                    y: prevWindow.frame.maxY))
        }
        wc.showWindow(nil)
        windowControllers.append(wc)
        return wc
    }

    private func openInitialPlayerWindowIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  !self.hasReceivedOpenEventDuringLaunch,
                  self.usablePlayerWindowController() == nil else { return }
            _ = self.openNewPlayerWindow()
        }
    }

    private func openSubmittedURLs(_ urls: [URL], source: String) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }

        hasReceivedOpenEventDuringLaunch = true

        guard let wc = usablePlayerWindowController() ?? openNewPlayerWindow() else { return }
        wc.window?.deminiaturize(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSLog("[dwb-open] source=%@ count=%d files=%@",
              source,
              fileURLs.count,
              fileURLs.map(\.lastPathComponent).joined(separator: ","))

        // Native Finder/Dock open events are explicit external submissions, so
        // use the same queue-top insertion semantics as an explicit file drop.
        wc.handleDroppedURLs(fileURLs, appendingExplicitFiles: true)
        noteRecentDocumentURLs(from: fileURLs)
    }

    private func usablePlayerWindowController() -> PlayerWindowController? {
        if let wc = NSApp.keyWindow?.windowController as? PlayerWindowController,
           wc.window?.isVisible == true {
            return wc
        }
        if let wc = NSApp.mainWindow?.windowController as? PlayerWindowController,
           wc.window?.isVisible == true {
            return wc
        }
        for window in NSApp.orderedWindows {
            if let wc = window.windowController as? PlayerWindowController,
               window.isVisible {
                return wc
            }
        }
        return windowControllers.last { $0.window?.isVisible == true }
    }

    private func installOptionDoubleTapCoordinator() {
        guard optionDoubleTapCoordinator == nil else { return }
        let coordinator = OptionDoubleTapCoordinator(
            targetIsEligible: { [weak self] in
                self?.optionDoubleTapTarget() != nil
            },
            onToggle: { [weak self] in
                self?.optionDoubleTapTarget()?.toggleSkimEnabled(source: "double-option")
            }
        )
        coordinator.start()
        optionDoubleTapCoordinator = coordinator

        guard let application = NSApp as? SkimApplication else {
            // Without the subclass nothing feeds the coordinator, so the
            // shortcut is silently dead. Make that loud rather than mysterious.
            DebugConsoleController.log(level: .warning,
                                       category: "app",
                                       message: "optionDoubleTap: NSApp is \(type(of: NSApp!)), expected SkimApplication; shortcut disabled")
            assertionFailure("NSApp must be SkimApplication for Double-tap Option interception")
            return
        }
        application.optionDoubleTapCoordinator = coordinator
        DebugConsoleController.log("app", "optionDoubleTap: installed on \(SkimApplicationConfiguration.principalClassName)")
    }

    private func optionDoubleTapTarget() -> PlayerWindowController? {
        guard let window = NSApp.keyWindow,
              let controller = window.windowController as? PlayerWindowController,
              windowControllers.contains(where: { $0 === controller }) else { return nil }
        let target = OptionDoubleTapTargetDescriptor(
            identifier: controller.debugIdentity,
            isPlayerWindow: true,
            isKeyWindow: window.isKeyWindow,
            isTextEntryFocused: controller.isTextEntryFocused
        )
        guard OptionDoubleTapTargetDescriptor.keyPlayerIdentifier(
            applicationIsActive: NSApp.isActive,
            targets: [target]
        ) == controller.debugIdentity else { return nil }
        return controller
    }

    private func pruneClosedPlayerWindowControllers() {
        windowControllers.removeAll { $0.window == nil }
    }

    private func presentWindowCapDenial(context: String) {
        DebugConsoleController.log(level: .warning,
                                   category: "window",
                                   message: "windowCapDenied: context=\(context) cap=\(maxPlayerWindowCount) current=\(windowControllers.count)")
        // A non-modal status HUD on the key player window. The alert remains only for
        // the case where no player window is visible to show it on.
        let hudWindow = (NSApp.keyWindow?.windowController as? PlayerWindowController)
            ?? orderedPlayerWindowControllers().first(where: { $0.window?.isVisible == true })
        if let hudWindow, hudWindow.window?.isVisible == true {
            hudWindow.showWindowLimitHUD(maxPlayerWindows: maxPlayerWindowCount)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Window limit reached"
        alert.informativeText = "dwb skim supports up to \(maxPlayerWindowCount) player windows."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if let sheetWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: sheetWindow)
        } else {
            alert.runModal()
        }
    }

    private func orderedPlayerWindowControllers() -> [PlayerWindowController] {
        pruneClosedPlayerWindowControllers()
        var ordered: [PlayerWindowController] = []
        if let front = usablePlayerWindowController() {
            ordered.append(front)
        }
        for window in NSApp.orderedWindows {
            guard let wc = window.windowController as? PlayerWindowController,
                  !ordered.contains(where: { $0 === wc }) else { continue }
            ordered.append(wc)
        }
        for wc in windowControllers where !ordered.contains(where: { $0 === wc }) {
            ordered.append(wc)
        }
        return ordered
    }

    private func gridTargetScreen(from selected: [PlayerWindowController]) -> NSScreen? {
        if let front = usablePlayerWindowController(),
           let screen = front.window?.screen {
            return screen
        }
        return selected.first(where: { $0.window?.isKeyWindow == true })?.window?.screen
            ?? selected.first(where: { $0.window?.isMainWindow == true })?.window?.screen
            ?? NSScreen.main
    }

    private func arrangeFourWindowGrid() {
        var selected = orderedPlayerWindowControllers()
        let initialCount = selected.count
        let needed = max(0, 4 - selected.count)

        for _ in 0..<needed {
            guard let wc = openNewPlayerWindow() else {
                DebugConsoleController.log(level: .warning,
                                           category: "window",
                                           message: "fourWindowGrid: deniedByCap initial=\(initialCount) selected=\(selected.count) cap=\(maxPlayerWindowCount)")
                return
            }
            selected.append(wc)
        }

        selected = Array(selected.prefix(4))
        guard selected.count == 4 else {
            presentWindowCapDenial(context: "four-window-grid")
            return
        }

        guard let screen = gridTargetScreen(from: selected) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let halfW = floor(visibleFrame.width / 2)
        let halfH = floor(visibleFrame.height / 2)
        let frames = [
            NSRect(x: visibleFrame.minX, y: visibleFrame.minY + halfH, width: halfW, height: visibleFrame.height - halfH),
            NSRect(x: visibleFrame.minX + halfW, y: visibleFrame.minY + halfH, width: visibleFrame.width - halfW, height: visibleFrame.height - halfH),
            NSRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfW, height: halfH),
            NSRect(x: visibleFrame.minX + halfW, y: visibleFrame.minY, width: visibleFrame.width - halfW, height: halfH)
        ]

        for (wc, frame) in zip(selected, frames) {
            wc.window?.setFrame(frame, display: true, animate: false)
            wc.window?.deminiaturize(nil)
            wc.showWindow(nil)
        }
        selected.first?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DebugConsoleController.log("window", "fourWindowGrid: initial=\(initialCount) opened=\(needed) arranged=\(selected.map(\.debugIdentity).joined(separator: ",")) screen=\(screen.localizedName) frame=\(Int(visibleFrame.width))x\(Int(visibleFrame.height))")
    }

    private func noteRecentDocumentURLs(from urls: [URL]) {
        for url in urls where shouldAddToRecentDocuments(url) {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
    }

    private func shouldAddToRecentDocuments(_ url: URL) -> Bool {
        guard url.isFileURL,
              MediaFileSupport.isSupported(url) else { return false }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }

        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        if isDescendant(resolvedURL, of: FileManager.default.temporaryDirectory) {
            return false
        }
        if isDescendant(resolvedURL, of: Bundle.main.bundleURL) {
            return false
        }
        return true
    }

    private func isDescendant(_ url: URL, of ancestor: URL) -> Bool {
        let childPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let ancestorPath = ancestor.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = ancestorPath.hasSuffix("/") ? ancestorPath : ancestorPath + "/"
        return childPath == ancestorPath || childPath.hasPrefix(prefix)
    }

    // MARK: - Menu actions

    @objc func openFile(_ sender: Any) {
        guard let wc = NSApp.keyWindow?.windowController as? PlayerWindowController else {
            guard let wc = openNewPlayerWindow() else { return }
            wc.openFile()
            return
        }
        wc.openFile()
    }

    @objc func revealInFinder(_ sender: Any) {
        frontPlayerWindowController?.revealInFinder()
    }

    @objc func renameCurrentFile(_ sender: Any) {
        frontPlayerWindowController?.showRenameSheet()
    }

    @objc func removeCurrentQueueItem(_ sender: Any) {
        frontPlayerWindowController?.removeCurrentQueueItem()
    }

    @objc func deleteAllQueueItems(_ sender: Any) {
        frontPlayerWindowController?.removeAllQueueItems(source: "menu")
    }

    @objc func newWindow(_ sender: Any) {
        _ = openNewPlayerWindow()
    }

    @objc func fourWindowGrid(_ sender: Any) {
        arrangeFourWindowGrid()
    }

    @objc func playPause(_ sender: Any) {
        frontPlayerWindowController?.togglePlayPause()
    }

    @objc func stop(_ sender: Any) {
        frontPlayerWindowController?.stopPlayback()
    }

    @objc func volumeUp(_ sender: Any) {
        frontPlayerWindowController?.volumeUp()
    }

    @objc func volumeDown(_ sender: Any) {
        frontPlayerWindowController?.volumeDown()
    }

    @objc func toggleLoopQueue(_ sender: Any) {
        let current = SkimSettingsStore.shared.snapshot().loopQueueEnabled
        SkimSettingsStore.shared.setLoopQueueEnabled(!current)
    }

    @objc func setPlaybackSpeedFromMenu(_ sender: NSMenuItem) {
        guard let option = PlaybackSpeedOption.option(forTag: sender.tag - 1000) else { return }
        frontPlayerWindowController?.setPlaybackSpeed(option.rate, source: "playback-menu")
    }

    @objc func setScaleFit(_ sender: Any) {
        frontPlayerWindowController?.setScaleMode(.fit)
    }

    @objc func setScaleFill(_ sender: Any) {
        frontPlayerWindowController?.setScaleMode(.fill)
    }

    @objc func setScaleStretch(_ sender: Any) {
        frontPlayerWindowController?.setScaleMode(.stretch)
    }

    @objc func openSettings(_ sender: Any) {
        SettingsWindowController.shared.openSettings()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.tag {
        case 40: // Redo typing
            guard let window = NSApp.keyWindow, window.firstResponder is NSTextView else { return false }
            return window.undoManager?.canRedo ?? false
        case 1:
            menuItem.state = frontPlayerWindowController?.scaleMode == .fit     ? .on : .off
        case 2:
            menuItem.state = frontPlayerWindowController?.scaleMode == .fill    ? .on : .off
        case 3:
            menuItem.state = frontPlayerWindowController?.scaleMode == .stretch ? .on : .off
        case 10: // Reveal in Finder
            return frontPlayerWindowController?.currentMediaURL != nil
        case 11: // Rename
            return frontPlayerWindowController?.canRenameCurrentMedia == true
        case 12: // Remove from Queue
            return frontPlayerWindowController?.currentMediaURL != nil
        case 13: // Clear Queue
            return frontPlayerWindowController != nil
        case 21: // Loop Queue
            menuItem.state = SkimSettingsStore.shared.snapshot().loopQueueEnabled ? .on : .off
            return (frontPlayerWindowController?.playbackSet.count ?? 0) > 0
        case 30: // Keep Window On Top
            menuItem.state = frontPlayerWindowController?.isKeepAtTop == true ? .on : .off
        case 31: // Auto-hide Titlebar
            menuItem.state = SettingsWindowController.isAutoHideTitlebarEnabled() ? .on : .off
        default:
            if menuItem.tag >= 1000,
               let option = PlaybackSpeedOption.option(forTag: menuItem.tag - 1000) {
                let current = frontPlayerWindowController?.currentPlaybackSpeed ?? PlaybackSpeedOption.normalRate
                menuItem.state = PlaybackSpeedOption.validated(current) == option ? .on : .off
                return frontPlayerWindowController != nil
            }
            break
        }
        return true
    }

    private var frontPlayerWindowController: PlayerWindowController? {
        return usablePlayerWindowController()
    }

    // MARK: - Menu key equivalents

    /// Menu items that carry a command's key. Their key equivalents come from `ShortcutStore`
    /// (the table's defaults plus the user's overrides), never from a literal here.
    private var shortcutMenuItems: [(id: ShortcutCommandID, item: NSMenuItem)] = []
    private var extraShortcutMenuItems: [ShortcutCommandID: [NSMenuItem]] = [:]
    private var shortcutObserver: NSObjectProtocol?

    private func bindShortcut(_ id: ShortcutCommandID, to item: NSMenuItem) {
        shortcutMenuItems.append((id, item))
        applyShortcut(id, to: item)
    }

    /// Gives `item` the command's first key that uses ⌘, ⌃, or ⌥, or no key when it has none.
    /// Keys without those modifiers belong to the player window's key handler, so a menu item
    /// never holds a key the handler also receives.
    private func applyShortcut(_ id: ShortcutCommandID, to item: NSMenuItem) {
        if let key = ShortcutStore.shared.menuKeys(for: id).first {
            item.keyEquivalent = key.key
            item.keyEquivalentModifierMask = key.modifiers.eventFlags
        } else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
        }
    }

    private func refreshShortcutMenuKeys() {
        for items in extraShortcutMenuItems.values {
            for item in items { item.menu?.removeItem(item) }
        }
        extraShortcutMenuItems.removeAll()
        for (id, item) in shortcutMenuItems {
            applyShortcut(id, to: item)
            guard let menu = item.menu else { continue }
            let extras = ShortcutStore.shared.menuKeys(for: id).dropFirst()
            extraShortcutMenuItems[id] = extras.map { key in
                let hidden = NSMenuItem(title: item.title, action: item.action, keyEquivalent: key.key)
                hidden.target = item.target
                hidden.tag = item.tag
                hidden.keyEquivalentModifierMask = key.modifiers.eventFlags
                hidden.isHidden = true
                hidden.allowsKeyEquivalentWhenHidden = true
                menu.addItem(hidden)
                return hidden
            }
        }
    }

    /// Run a menu-backed action assigned an unmodified player-window key.
    func performKeyHandlerMenuAction(_ id: ShortcutCommandID) -> Bool {
        guard let item = shortcutMenuItems.first(where: { $0.id == id })?.item,
              let action = item.action, validateMenuItem(item) else { return false }
        return NSApp.sendAction(action, to: item.target, from: item)
    }

    @objc private func redoTyping(_ sender: Any?) {
        guard let window = NSApp.keyWindow, window.firstResponder is NSTextView else { return }
        window.undoManager?.redo()
    }

    private func installShortcutObserver() {
        guard shortcutObserver == nil else { return }
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: .shortcutsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshShortcutMenuKeys() }
    }

    // MARK: - Main menu (programmatic)

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // ── App menu ────────────────────────────────────────────────────────
        let appItem = NSMenuItem()
        appItem.title = "dwb skim"
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "dwb skim")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About dwb skim",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings\u{2026}",
                                      action: #selector(openSettings(_:)),
                                      keyEquivalent: "")
        settingsItem.target = self
        bindShortcut(.openSettings, to: settingsItem)
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(withTitle: "Quit dwb skim",
                                       action: #selector(NSApplication.terminate(_:)),
                                       keyEquivalent: "")
        bindShortcut(.quit, to: quitItem)

        // ── File menu ───────────────────────────────────────────────────────
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu

        let openItem = NSMenuItem(title: "Open\u{2026}",
                                  action: #selector(openFile(_:)),
                                  keyEquivalent: "")
        openItem.target = self
        bindShortcut(.openFile, to: openItem)
        fileMenu.addItem(openItem)

        fileMenu.addItem(.separator())

        let revealItem = NSMenuItem(title: "Reveal in Finder",
                                    action: #selector(revealInFinder(_:)),
                                    keyEquivalent: "")
        revealItem.target = self
        bindShortcut(.revealInFinder, to: revealItem)
        revealItem.tag    = 10
        fileMenu.addItem(revealItem)

        let renameItem = NSMenuItem(title: "Rename\u{2026}",
                                    action: #selector(renameCurrentFile(_:)),
                                    keyEquivalent: "")
        renameItem.target = self
        renameItem.tag    = 11
        bindShortcut(.renameFile, to: renameItem)
        fileMenu.addItem(renameItem)

        let removeItem = NSMenuItem(title: QueueRemovalPresentation.menuItemTitle,
                                    action: #selector(removeCurrentQueueItem(_:)),
                                    keyEquivalent: "")
        removeItem.target = self
        removeItem.tag    = 12
        fileMenu.addItem(removeItem)

        // AppKit represents Delete as NSDeleteCharacter for menu shortcuts (`ShortcutKey.delete`).
        let deleteAllItem = NSMenuItem(title: "Clear Queue",
                                       action: #selector(deleteAllQueueItems(_:)),
                                       keyEquivalent: "")
        deleteAllItem.target = self
        bindShortcut(.clearQueue, to: deleteAllItem)
        deleteAllItem.tag    = 13
        fileMenu.addItem(deleteAllItem)

        fileMenu.addItem(.separator())

        let newWindowItem = NSMenuItem(title: "New Window",
                                       action: #selector(newWindow(_:)),
                                       keyEquivalent: "")
        newWindowItem.target = self
        bindShortcut(.newWindow, to: newWindowItem)
        fileMenu.addItem(newWindowItem)

        // ── Edit menu ───────────────────────────────────────────────────────
        // `undo:` travels the responder chain: a player window turns it into
        // "Undo Prefix Change" (or typing undo while a field is being edited).
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.delegate = self
        editItem.submenu = editMenu
        let undoItem = editMenu.addItem(withTitle: "Undo",
                                        action: Selector(("undo:")),
                                        keyEquivalent: "")
        bindShortcut(.undoPrefixChange, to: undoItem)
        let redoItem = editMenu.addItem(withTitle: "Redo", action: #selector(redoTyping(_:)), keyEquivalent: "")
        redoItem.target = self
        redoItem.tag = 40
        bindShortcut(.redoTyping, to: redoItem)
        editMenu.addItem(.separator())
        let cutItem = editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "")
        bindShortcut(.cut, to: cutItem)
        let copyItem = editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        bindShortcut(.copy, to: copyItem)
        let pasteItem = editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
        bindShortcut(.paste, to: pasteItem)
        let selectAllItem = editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
        bindShortcut(.selectAll, to: selectAllItem)

        // ── Playback menu ───────────────────────────────────────────────────
        let playbackItem = NSMenuItem()
        mainMenu.addItem(playbackItem)
        let playbackMenu = NSMenu(title: "Playback")
        playbackItem.submenu = playbackMenu

        let playPauseItem = NSMenuItem(title: "Play / Pause",
                                       action: #selector(playPause(_:)),
                                       keyEquivalent: "")
        playPauseItem.target = self
        bindShortcut(.playPause, to: playPauseItem)
        playbackMenu.addItem(playPauseItem)

        let stopItem = NSMenuItem(title: "Stop",
                                  action: #selector(stop(_:)),
                                  keyEquivalent: "")
        stopItem.target = self
        playbackMenu.addItem(stopItem)

        playbackMenu.addItem(.separator())

        let volUpItem = NSMenuItem(title: "Volume Up",
                                   action: #selector(volumeUp(_:)),
                                   keyEquivalent: "")
        volUpItem.target = self
        bindShortcut(.volumeUp, to: volUpItem)
        playbackMenu.addItem(volUpItem)

        let volDownItem = NSMenuItem(title: "Volume Down",
                                     action: #selector(volumeDown(_:)),
                                     keyEquivalent: "")
        volDownItem.target = self
        bindShortcut(.volumeDown, to: volDownItem)
        playbackMenu.addItem(volDownItem)

        playbackMenu.addItem(.separator())

        let loopQueueItem = NSMenuItem(title: "Loop Queue",
                                       action: #selector(toggleLoopQueue(_:)),
                                       keyEquivalent: "")
        loopQueueItem.target = self
        loopQueueItem.tag = 21
        playbackMenu.addItem(loopQueueItem)

        playbackMenu.addItem(.separator())

        let speedItem = NSMenuItem(title: "Playback Speed", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu(title: "Playback Speed")
        for option in PlaybackSpeedOption.all {
            let item = NSMenuItem(title: option.title,
                                  action: #selector(setPlaybackSpeedFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = 1000 + option.tag
            speedMenu.addItem(item)
        }
        speedItem.submenu = speedMenu
        playbackMenu.addItem(speedItem)

        // ── Video menu ──────────────────────────────────────────────────────
        let videoItem = NSMenuItem()
        mainMenu.addItem(videoItem)
        let videoMenu = NSMenu(title: "Video")
        videoItem.submenu = videoMenu

        let fitItem = NSMenuItem(title: "Fit",
                                 action: #selector(setScaleFit(_:)),
                                 keyEquivalent: "")
        fitItem.target = self
        bindShortcut(.fitVideo, to: fitItem)
        fitItem.tag = 1
        videoMenu.addItem(fitItem)

        let fillItem = NSMenuItem(title: "Fill",
                                  action: #selector(setScaleFill(_:)),
                                  keyEquivalent: "")
        fillItem.target = self
        bindShortcut(.fillVideo, to: fillItem)
        fillItem.tag = 2
        videoMenu.addItem(fillItem)

        let stretchItem = NSMenuItem(title: "Stretch",
                                     action: #selector(setScaleStretch(_:)),
                                     keyEquivalent: "")
        stretchItem.target = self
        bindShortcut(.stretchVideo, to: stretchItem)
        stretchItem.tag = 3
        videoMenu.addItem(stretchItem)

        // ── Window menu ─────────────────────────────────────────────────────
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        let minimizeItem = windowMenu.addItem(withTitle: "Minimize",
                                              action: #selector(NSWindow.performMiniaturize(_:)),
                                              keyEquivalent: "")
        bindShortcut(.minimizeWindow, to: minimizeItem)
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        let closeItem = windowMenu.addItem(withTitle: "Close",
                                           action: #selector(NSWindow.performClose(_:)),
                                           keyEquivalent: "")
        bindShortcut(.closeWindow, to: closeItem)

        windowMenu.addItem(.separator())

        let gridItem = NSMenuItem(title: "Four Window Grid",
                                  action: #selector(fourWindowGrid(_:)),
                                  keyEquivalent: "")
        gridItem.target = self
        bindShortcut(.fourWindowGrid, to: gridItem)
        windowMenu.addItem(gridItem)

        windowMenu.addItem(.separator())

        let keepAtTopItem = NSMenuItem(title: "Keep Window On Top",
                                       action: #selector(toggleKeepAtTop(_:)),
                                       keyEquivalent: "")
        keepAtTopItem.target = self
        keepAtTopItem.tag    = 30
        windowMenu.addItem(keepAtTopItem)

        let autoHideTitlebarItem = NSMenuItem(title: "Auto-hide Titlebar",
                                              action: #selector(toggleAutoHideTitlebar(_:)),
                                              keyEquivalent: "")
        autoHideTitlebarItem.target = self
        autoHideTitlebarItem.tag    = 31
        windowMenu.addItem(autoHideTitlebarItem)

        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
        refreshShortcutMenuKeys()
    }

    /// Resets the Undo title before validation, so a window that does not
    /// handle `undo:` never shows a stale "Undo Prefix Change".
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.action == Selector(("undo:")) {
            item.title = "Undo"
        }
    }

    @objc func toggleKeepAtTop(_ sender: Any) {
        frontPlayerWindowController?.toggleKeepAtTop()
    }

    @objc func toggleAutoHideTitlebar(_ sender: Any) {
        let current = SettingsWindowController.isAutoHideTitlebarEnabled()
        UserDefaults.standard.set(!current, forKey: SettingsWindowController.autoHideTitlebarKey)
        NotificationCenter.default.post(name: .autoHideTitlebarChanged, object: nil)
    }
}
