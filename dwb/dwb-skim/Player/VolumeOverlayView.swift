import Cocoa

/// Focused, non-interactive video-volume HUD (0–200%). It owns only transient presentation;
/// the player controller remains the source of video volume and mute state.
final class VolumeOverlayView: HUDSurfaceView {
    private enum Metrics {
        static let height: CGFloat = 56
        static let sidePadding: CGFloat = 22
        static let gap: CGFloat = 18
        static let icon: CGFloat = 18
        static let valueWidth: CGFloat = 62
    }

    static var size: NSSize {
        NSSize(width: Metrics.sidePadding * 2 + Metrics.icon + Metrics.gap + VolumeSegmentsView.width
                    + Metrics.gap + Metrics.valueWidth,
               height: Metrics.height)
    }

    private let iconView = HUDText.symbol("speaker.wave.2.fill", size: 18, tint: DWBColor.textPrimary)
    private let valueLabel = NSTextField(labelWithString: "100%")
    private let segmentsView = VolumeSegmentsView()

    init() {
        super.init(backing: { DWBAccessibility.backingHUD }, edge: { DWBColor.hairline }, hasShadow: true)
        addSubview(iconView)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        valueLabel.textColor = DWBColor.textPrimary
        valueLabel.alignment = .right
        valueLabel.setAccessibilityElement(false)
        addSubview(valueLabel)

        addSubview(segmentsView)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func layout() {
        super.layout()
        let midY = bounds.height / 2
        var x = Metrics.sidePadding
        iconView.frame = NSRect(x: x, y: midY - Metrics.icon / 2, width: Metrics.icon, height: Metrics.icon)
        x += Metrics.icon + Metrics.gap
        segmentsView.frame = NSRect(x: x, y: midY - VolumeSegmentsView.segment / 2,
                                    width: VolumeSegmentsView.width, height: VolumeSegmentsView.segment)
        x += VolumeSegmentsView.width + Metrics.gap
        valueLabel.frame = NSRect(x: x, y: midY - 14, width: Metrics.valueWidth, height: 28)
    }

    func show(_ presentation: VideoVolumeMeterPresentation) {
        iconView.image = NSImage(systemSymbolName: presentation.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .regular))
        valueLabel.stringValue = presentation.percentageText
        segmentsView.presentation = presentation
        setAccessibilityLabel(presentation.isMuted ? "Video volume muted" : "Video volume")
        setAccessibilityValue(presentation.percentageText)
        present(hold: VolumeOverlayTiming.dismissalDelay)
    }
}

/// The 7 + 4 volume segments: 11 pt squares, radius 2.5, gap 4, 12 pt between the groups.
/// Unlit segments are the same color at 24%; from 150% every segment blends toward `errorFill`.
private final class VolumeSegmentsView: NSView {
    static let segment: CGFloat = 11
    static let radius: CGFloat = 2.5
    static let gap: CGFloat = 4
    static let groupGap: CGFloat = 12
    static let unlitAlpha: CGFloat = 0.24
    static let width: CGFloat = {
        let regular = CGFloat(VideoVolumeMeterPresentation.regularSegmentCount)
        let boost = CGFloat(VideoVolumeMeterPresentation.boostSegmentCount)
        return (regular + boost) * segment + (regular - 1 + boost - 1) * gap + groupGap
    }()

    var presentation = VideoVolumeMeterPresentation(volume: 100, muted: false) {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let heat = presentation.heatFraction
        let primary = VideoVolumeMeterPresentation.heatedColor(theme.markerPrimary, heatFraction: heat)
        let secondary = VideoVolumeMeterPresentation.heatedColor(theme.markerSecondary, heatFraction: heat)
        var x: CGFloat = 0
        drawGroup(count: VideoVolumeMeterPresentation.regularSegmentCount,
                  lit: presentation.litRegularSegments, color: primary, x: &x)
        x += Self.groupGap - Self.gap
        drawGroup(count: VideoVolumeMeterPresentation.boostSegmentCount,
                  lit: presentation.litBoostSegments, color: secondary, x: &x)
    }

    private func drawGroup(count: Int, lit: Int, color: NSColor, x: inout CGFloat) {
        for index in 0..<count {
            let rect = NSRect(x: x, y: (bounds.height - Self.segment) / 2, width: Self.segment, height: Self.segment)
            (index < lit ? color : color.withAlphaComponent(Self.unlitAlpha)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: Self.radius, yRadius: Self.radius).fill()
            x += Self.segment + Self.gap
        }
    }
}
