import Cocoa

/// The invisible grab zone over the edge the video area shares with the queue panel.
///
/// It handles its own mouse events and never calls `super.mouseDown`, so a press here never
/// reaches the video's fullscreen double-click, a queue row, or the window background.
/// `mouseDownCanMoveWindow` is false so Complete Video Window mode cannot move the window
/// from here. Edge positions are reported in the superview's coordinates.
///
/// While the pointer is over the zone, or a drag is in progress, a 2 pt `accentText` line shows at
/// 0.7 opacity (design system 10.1), fading in over 0.12 s (instantly under Reduce Motion).
/// The keyboard resizes through the same callbacks' clamped routes: ← widens and → narrows by 10 pt,
/// Home resets; VoiceOver gets the same steps as increment / decrement.
final class QueuePanelResizeHandleView: NSView {

    static let accessibilityName = "Queue width. Drag to resize; double-click to reset."

    /// The pointer moved the edge to this x (superview coordinates).
    var onDrag: ((CGFloat) -> Void)?
    /// The press ended after at least one drag event that moved.
    var onDragEnded: (() -> Void)?
    /// Double-click or Home: return to the default width.
    var onReset: (() -> Void)?
    /// The keyboard or VoiceOver asks to change the width by this many points (positive widens).
    var onNudge: ((CGFloat) -> Void)?
    /// The current panel width for VoiceOver, set by the controller after each layout.
    var accessibilityWidthValue: String? {
        didSet { setAccessibilityValue(accessibilityWidthValue) }
    }

    private var isTracking = false
    private var didMove = false
    private var isHovering = false
    private var isFocused = false
    /// Pointer x minus edge x at mouse-down, so the edge does not jump.
    private var pointerOffset: CGFloat = 0
    private var lastEdgeX: CGFloat = 0
    private var trackingAreaReference: NSTrackingArea?
    private let lineLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        lineLayer.opacity = 0
        lineLayer.backgroundColor = theme.accentText.cgColor
        layer?.addSublayer(lineLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel(Self.accessibilityName)
        setAccessibilityOrientation(.vertical)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override var mouseDownCanMoveWindow: Bool { false }
    /// Keyboard focus only: a press on the divider must not take focus from the list or the video.
    override var acceptsFirstResponder: Bool { !QueuePointerEvent.isPointerDownInFlight }

    @objc private func accessibilityDidChange() {
        lineLayer.backgroundColor = theme.accentText.cgColor
    }

    // MARK: Line

    private var showsLine: Bool { isHovering || isTracking || isFocused }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.frame = CGRect(x: floor((bounds.width - DWBMetrics.queueDividerLine) / 2), y: 0,
                                 width: DWBMetrics.queueDividerLine, height: bounds.height)
        CATransaction.commit()
    }

    private func updateLine() {
        let target = Float(showsLine ? DWBMetrics.queueDividerLineAlpha : 0)
        guard lineLayer.opacity != target else { return }
        let duration = DWBAccessibility.duration(DWBMotion.hover)
        CATransaction.begin()
        if duration > 0 {
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        lineLayer.opacity = target
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateLine()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateLine()
    }

    // MARK: Cursor

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            isTracking = false
            onReset?()
            return
        }
        guard let superview else { return }
        let pointerX = superview.convert(event.locationInWindow, from: nil).x
        let edgeX = frame.minX + QueuePanelWidthPolicy.grabZoneHalfWidth
        pointerOffset = pointerX - edgeX
        lastEdgeX = edgeX
        isTracking = true
        didMove = false
        updateLine()
        // Keep the resize cursor for the whole drag, even when the pointer leaves the zone.
        window?.disableCursorRects()
        NSCursor.resizeLeftRight.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTracking, let superview else { return }
        NSCursor.resizeLeftRight.set()
        let edgeX = superview.convert(event.locationInWindow, from: nil).x - pointerOffset
        guard edgeX != lastEdgeX else { return }
        lastEdgeX = edgeX
        didMove = true
        onDrag?(edgeX)
    }

    override func mouseUp(with event: NSEvent) {
        guard isTracking else { return }
        isTracking = false
        if let window {
            window.enableCursorRects()
            window.invalidateCursorRects(for: self)
        }
        if didMove { onDragEnded?() }
        didMove = false
        updateLine()
    }

    // MARK: Keyboard and VoiceOver

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: onNudge?(DWBMetrics.queueDividerKeyStep)      // ← widens
        case 124: onNudge?(-DWBMetrics.queueDividerKeyStep)     // → narrows
        case 115: onReset?()                                    // Home
        default: super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool {
        onNudge?(DWBMetrics.queueDividerKeyStep)
        return onNudge != nil
    }

    override func accessibilityPerformDecrement() -> Bool {
        onNudge?(-DWBMetrics.queueDividerKeyStep)
        return onNudge != nil
    }

    // Keyboard focus shows the same line, so a keyboard user sees which edge the arrows move.
    override func becomeFirstResponder() -> Bool {
        isFocused = true
        updateLine()
        return true
    }

    override func resignFirstResponder() -> Bool {
        isFocused = false
        updateLine()
        return true
    }
}
