import AppKit

// The design system's generic popover (`Popover`, section 5 and 9.8): a `surfaceElevated` panel with a
// 1 pt `border`, radius 10, the popover shadow, a 10 pt arrow to its anchor, and the caller's content
// inside a 14 pt inset. It is transient: a click outside, Esc, a second click on the anchor, or a
// resize of the window it hangs from closes it. It never opens by itself.

private final class DWBPopoverPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

private final class DWBPopoverChromeView: NSView {
    private(set) var placement = DWBPopoverGeometry.Placement(bodyFrame: .zero, arrowCenterX: 0, arrowOnTop: true)
    private var windowOrigin: CGPoint = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.5
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -12)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    /// The panel body in this view's coordinates.
    var bodyRect: NSRect {
        placement.bodyFrame.offsetBy(dx: -windowOrigin.x, dy: -windowOrigin.y)
    }

    /// The body and the arrow, in this view's coordinates; a click here is a click on the popover.
    var hitRect: NSRect {
        let body = bodyRect
        let rise = DWBPopoverGeometry.arrowRise
        return placement.arrowOnTop
            ? NSRect(x: body.minX, y: body.minY, width: body.width, height: body.height + rise)
            : NSRect(x: body.minX, y: body.minY - rise, width: body.width, height: body.height + rise)
    }

    func apply(_ placement: DWBPopoverGeometry.Placement, windowOrigin: CGPoint) {
        self.placement = placement
        self.windowOrigin = windowOrigin
        layer?.shadowPath = CGPath(roundedRect: bodyRect,
                                   cornerWidth: DWBPopoverGeometry.radius,
                                   cornerHeight: DWBPopoverGeometry.radius,
                                   transform: nil)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = bodyRect
        guard body.width > 0 else { return }
        let outline = NSBezierPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5),
                                   xRadius: DWBPopoverGeometry.radius, yRadius: DWBPopoverGeometry.radius)
        DWBColor.surfaceElevated.setFill()
        outline.fill()
        DWBAccessibility.border.setStroke()
        outline.lineWidth = 1
        outline.stroke()

        // The arrow: a triangle in the panel's fill that covers the border under it, with its two
        // slanted edges stroked in the border color.
        let rise = DWBPopoverGeometry.arrowRise
        let edgeY = placement.arrowOnTop ? body.maxY : body.minY
        let direction: CGFloat = placement.arrowOnTop ? 1 : -1
        let centerX = placement.arrowCenterX - windowOrigin.x
        let tip = NSPoint(x: centerX, y: edgeY + direction * rise)
        let left = NSPoint(x: centerX - (rise + 1), y: edgeY - direction)
        let right = NSPoint(x: centerX + (rise + 1), y: edgeY - direction)
        let triangle = NSBezierPath()
        triangle.move(to: left)
        triangle.line(to: tip)
        triangle.line(to: right)
        triangle.close()
        DWBColor.surfaceElevated.setFill()
        triangle.fill()
        let edges = NSBezierPath()
        edges.move(to: left)
        edges.line(to: tip)
        edges.line(to: right)
        edges.lineWidth = 1
        edges.lineJoinStyle = .miter
        DWBAccessibility.border.setStroke()
        edges.stroke()
    }

    @objc private func accessibilityDidChange() { needsDisplay = true }
}

final class DWBPopover: NSObject {
    /// Called when the popover closes, for any reason.
    var onClose: (() -> Void)?
    private(set) var isShown = false

    private let content: NSView
    private let accessibilityName: String
    private let panel: DWBPopoverPanel
    private let chrome = DWBPopoverChromeView(frame: .zero)
    private weak var anchor: NSView?
    private weak var parent: NSWindow?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    /// - Parameter content: laid out at its natural size. It carries its own 14 pt inset.
    init(content: NSView, accessibilityName: String) {
        self.content = content
        self.accessibilityName = accessibilityName
        panel = DWBPopoverPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = chrome
        panel.onCancel = { [weak self] in self?.close() }
        chrome.setAccessibilityRole(.popover)
        chrome.setAccessibilityLabel(accessibilityName)
    }

    deinit { removeMonitors() }

    /// Opens the popover under `anchor` (above it when there is no room below).
    func show(relativeTo anchor: NSView) {
        guard !isShown, let parent = anchor.window else { return }
        self.anchor = anchor
        self.parent = parent

        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = true
        content.layoutSubtreeIfNeeded()
        let size = CGSize(width: ceil(content.fittingSize.width), height: ceil(content.fittingSize.height))
        content.frame = NSRect(origin: .zero, size: size)

        let anchorFrame = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? anchorFrame.insetBy(dx: -2000, dy: -2000)
        let placement = DWBPopoverGeometry.place(anchor: anchorFrame, size: size, visibleFrame: visible)

        let margin = DWBPopoverGeometry.shadowMargin
        let windowFrame = placement.bodyFrame.insetBy(dx: -margin, dy: -margin)
        panel.setFrame(windowFrame, display: false)
        chrome.frame = NSRect(origin: .zero, size: windowFrame.size)
        chrome.apply(placement, windowOrigin: windowFrame.origin)
        chrome.addSubview(content)
        content.frame = chrome.bodyRect

        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        isShown = true
        installMonitors(parent: parent)
    }

    func close() {
        guard isShown else { return }
        isShown = false
        removeMonitors()
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        content.removeFromSuperview()
        let host = parent
        parent = nil
        host?.makeKey()
        onClose?()
    }

    // MARK: Transient closing

    private func installMonitors(parent: NSWindow) {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.isShown else { return event }
            if event.window === self.panel {
                if !self.chrome.hitRect.contains(event.locationInWindow) { self.close() }
                return event
            }
            // A click on the anchor is the anchor's own toggle: it closes the popover itself.
            if let anchor = self.anchor, event.window === anchor.window {
                let point = anchor.convert(event.locationInWindow, from: nil)
                if anchor.bounds.contains(point) { return event }
            }
            self.close()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.close()
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                self?.close()
            })
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.close()
        })
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}
