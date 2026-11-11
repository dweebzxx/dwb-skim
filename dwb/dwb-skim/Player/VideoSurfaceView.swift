import Cocoa

private enum MediaDropRouting {
    static func readDroppedURLs(from sender: NSDraggingInfo) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard
                .readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return nil }
        return urls
    }

    static func isValidDrop(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = readDroppedURLs(from: sender) else { return false }
        return urls.contains { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue || MediaFileSupport.isSupported(url)
        }
    }

    /// How many dragged items the drop zone says will be added: the supported media files and
    /// folders. A folder among them makes the count "items" rather than "files".
    static func dropSummary(from sender: NSDraggingInfo) -> DropZonePresentation {
        let urls = readDroppedURLs(from: sender) ?? []
        var count = 0
        var containsFolder = false
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                containsFolder = true
                count += 1
            } else if MediaFileSupport.isSupported(url) {
                count += 1
            }
        }
        return DropZonePresentation(itemCount: max(1, count), containsFolder: containsFolder)
    }

    static func performDrop(_ sender: NSDraggingInfo, in window: NSWindow?) -> Bool {
        guard let urls = readDroppedURLs(from: sender),
              let wc = window?.windowController as? PlayerWindowController else { return false }
        wc.handleDroppedURLs(urls, appendingExplicitFiles: true, isDragAndDrop: true)
        return true
    }
}

/// The NSView into which VLCMediaPlayer renders its video output.
/// Background is black. Scroll wheel adjusts volume (0–200), clamped.
/// Double-click toggles fullscreen. Accepts file/folder drops (single or multi).
/// Player-window shortcuts are routed centrally so they also work from the queue table.
class VideoSurfaceView: NSView {

    private var isDragHighlighted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used – UI is programmatic")
    }

    override var acceptsFirstResponder: Bool { true }
    // L1: full-bleed black/video host — no transparency needed.
    override var isOpaque: Bool { true }

    override func flagsChanged(with event: NSEvent) {
        (window?.windowController as? PlayerWindowController)?.noteChromeActivity()
        super.flagsChanged(with: event)
    }

    // MARK: - Scroll / Volume

    /// Vertical scroll adjusts volume. Scroll down = louder, scroll up = quieter
    /// (reversed from natural direction per user preference).
    override func scrollWheel(with event: NSEvent) {
        guard let wc = window?.windowController as? PlayerWindowController else {
            super.scrollWheel(with: event)
            return
        }
        // Negate deltaY: scroll up (positive deltaY with natural scrolling) → quieter
        let delta = Int(-event.deltaY * 5.0)
        wc.adjustVolume(by: delta)
    }

    // MARK: - Double-click fullscreen

    override func mouseDown(with event: NSEvent) {
        // Clicking the video area makes it first responder so keyboard events land here
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            window?.toggleFullScreen(nil)
        }
        super.mouseDown(with: event)
    }

    // MARK: - Drag highlight

    /// Shows or hides the player window's drop zone over the stage.
    private func setDragHighlight(_ on: Bool, for sender: NSDraggingInfo? = nil) {
        guard isDragHighlighted != on else { return }
        isDragHighlighted = on
        let controller = window?.windowController as? PlayerWindowController
        if on, let sender {
            controller?.showDropZone(MediaDropRouting.dropSummary(from: sender))
        } else {
            controller?.hideDropZone()
        }
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isValidDrop(sender) else { return [] }
        setDragHighlight(true, for: sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isValidDrop(sender) else {
            setDragHighlight(false)
            return []
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDragHighlight(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDragHighlight(false)
        return MediaDropRouting.performDrop(sender, in: window)
    }

    private func isValidDrop(_ sender: NSDraggingInfo) -> Bool {
        MediaDropRouting.isValidDrop(sender)
    }
}

final class ImageSurfaceView: NSImageView {
    private var isDragHighlighted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used – UI is programmatic")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.toggleFullScreen(nil)
        }
        super.mouseDown(with: event)
    }

    /// Shows or hides the player window's drop zone over the stage.
    private func setDragHighlight(_ on: Bool, for sender: NSDraggingInfo? = nil) {
        guard isDragHighlighted != on else { return }
        isDragHighlighted = on
        let controller = window?.windowController as? PlayerWindowController
        if on, let sender {
            controller?.showDropZone(MediaDropRouting.dropSummary(from: sender))
        } else {
            controller?.hideDropZone()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard MediaDropRouting.isValidDrop(sender) else { return [] }
        setDragHighlight(true, for: sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard MediaDropRouting.isValidDrop(sender) else {
            setDragHighlight(false)
            return []
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDragHighlight(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDragHighlight(false)
        return MediaDropRouting.performDrop(sender, in: window)
    }
}
