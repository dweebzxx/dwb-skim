import Cocoa

/// Focused, non-interactive video-volume HUD. It owns only transient presentation;
/// the player controller remains the source of video volume and mute state.
final class VolumeOverlayView: NSVisualEffectView {
    private let iconView = NSImageView()
    private let percentageLabel = NSTextField(labelWithString: "100%")
    private let levelView = VolumeLevelView()
    private var dismissalWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        appearance = NSAppearance(named: .darkAqua)
        alphaValue = 0
        isHidden = true

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .white
        addSubview(iconView)

        percentageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        percentageLabel.textColor = .white
        percentageLabel.alignment = .right
        addSubview(percentageLabel)

        addSubview(levelView)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { dismissalWorkItem?.cancel() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 12, y: 13, width: 18, height: 18)
        levelView.frame = NSRect(x: 40, y: 13, width: max(40, bounds.width - 98), height: 18)
        percentageLabel.frame = NSRect(x: bounds.width - 54, y: 13, width: 44, height: 18)
    }

    func show(_ presentation: VideoVolumeMeterPresentation) {
        dismissalWorkItem?.cancel()
        iconView.image = NSImage(systemSymbolName: presentation.symbolName,
                                 accessibilityDescription: presentation.isMuted ? "Muted" : "Video volume")
        percentageLabel.stringValue = presentation.percentageText
        levelView.regularLevel = presentation.regularLevel
        levelView.overdriveLevel = presentation.overdriveLevel
        levelView.isMuted = presentation.isMuted
        setAccessibilityLabel(presentation.isMuted ? "Video volume muted" : "Video volume")
        setAccessibilityValue(presentation.percentageText)
        isHidden = false
        alphaValue = 1

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if reduceMotion {
                self.alphaValue = 0
                self.isHidden = true
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = VolumeOverlayTiming.fadeDuration
                    self.animator().alphaValue = 0
                } completionHandler: {
                    if self.alphaValue == 0 { self.isHidden = true }
                }
            }
        }
        dismissalWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + VolumeOverlayTiming.dismissalDelay,
                                      execute: work)
    }
}

private final class VolumeLevelView: NSView {
    var regularLevel = 0.0 { didSet { needsDisplay = true } }
    var overdriveLevel = 0.0 { didSet { needsDisplay = true } }
    var isMuted = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let regularSegments = 8
        let overdriveSegments = 4
        let gap: CGFloat = 2
        let sectionGap: CGFloat = 7
        let totalGaps = CGFloat(regularSegments + overdriveSegments - 2) * gap + sectionGap
        let width = max(1, (bounds.width - totalGaps) / CGFloat(regularSegments + overdriveSegments))
        let regularActiveCount = activeSegmentCount(for: regularLevel, segments: regularSegments)
        let overdriveActiveCount = activeSegmentCount(for: overdriveLevel, segments: overdriveSegments)

        drawSegments(count: regularSegments,
                     activeCount: regularActiveCount,
                     startX: 0,
                     width: width,
                     gap: gap,
                     activeColor: SkimColors.darkTeal)

        let overdriveStartX = CGFloat(regularSegments) * (width + gap) - gap + sectionGap
        drawSegments(count: overdriveSegments,
                     activeCount: overdriveActiveCount,
                     startX: overdriveStartX,
                     width: width,
                     gap: gap,
                     activeColor: SkimColors.burntOrange)
    }

    private func activeSegmentCount(for level: Double, segments: Int) -> Int {
        Int((min(1, max(0, level)) * Double(segments)).rounded(.up))
    }

    private func drawSegments(count: Int,
                              activeCount: Int,
                              startX: CGFloat,
                              width: CGFloat,
                              gap: CGFloat,
                              activeColor: NSColor) {
        for index in 0..<count {
            let rect = NSRect(x: startX + CGFloat(index) * (width + gap),
                              y: 5,
                              width: width,
                              height: 8)
            let color = index < activeCount
                ? (isMuted ? NSColor.white.withAlphaComponent(0.28) : activeColor.withAlphaComponent(0.95))
                : NSColor.white.withAlphaComponent(0.13)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
