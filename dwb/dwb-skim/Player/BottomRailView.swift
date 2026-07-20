import Cocoa
import VLCKitSPM

/// The single player overlay surface. Its control order is intentionally fixed.
final class BottomRailView: NSView {
    weak var player: VLCMediaPlayer?
    weak var controller: PlayerWindowController?

    var isImageMode = false
    var imageModeElapsed: Double = 0
    var imageModeDuration: Double = 0
    var imageModeIsPlaying = true
    var scrubDidBegin: (() -> Void)?
    var scrubDidEnd: (() -> Void)?

    private let scrubber = PreviewRangeSlider()
    private let queueButton = RailButton()
    private let previousButton = RailButton()
    private let skimButton = RailButton()
    private let playPauseButton = RailButton()
    private let nextButton = RailButton()
    private let volumeButton = RailButton()
    private let fullscreenButton = RailButton()
    private var markerLabels: [NSTextField] = []
    private var pendingSeekPosition: Float?
    private var pendingSeekDate: Date?
    private var isScrubbing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private func setupViews() {
        scrubber.minValue = 0
        scrubber.maxValue = 1
        scrubber.isContinuous = true
        scrubber.target = self
        scrubber.action = #selector(scrubberMoved(_:))
        scrubber.scrubDidBegin = { [weak self] in
            self?.isScrubbing = true
            self?.scrubDidBegin?()
            self?.controller?.notifyUserSeek(source: "preview-scrub-begin")
        }
        scrubber.scrubDidEnd = { [weak self] in
            guard let self else { return }
            self.isScrubbing = false
            let position = Float(self.scrubber.doubleValue)
            self.controller?.relocatePreviewRange(toNormalizedPosition: position)
            self.scrubDidEnd?()
        }
        scrubber.setAccessibilityLabel("Preview Position")
        scrubber.toolTip = "Relocate preview and seek"
        addSubview(scrubber)

        configure(queueButton, symbol: "rectangle.righthalf.inset.filled", label: "Queue", help: "Toggle queue panel (Q)", action: #selector(queueTapped))
        configure(previousButton, symbol: "backward.end.fill", label: "Previous", help: "Previous item ([)", action: #selector(previousTapped))
        configure(skimButton, symbol: "bolt.fill", label: "Skim", help: "Skim is on. Double-tap Option to toggle Skim.", action: #selector(skimTapped))
        configure(playPauseButton, symbol: "play.fill", label: "Play or Pause", help: "Play or Pause (Space)", action: #selector(playPauseTapped), emphasized: true)
        configure(nextButton, symbol: "forward.end.fill", label: "Next", help: "Next item (])", action: #selector(nextTapped))
        configure(volumeButton, symbol: "speaker.wave.2.fill", label: "Mute or Unmute", help: "Mute or Unmute (M)", action: #selector(volumeTapped))
        configure(fullscreenButton, symbol: "arrow.up.left.and.arrow.down.right", label: "Fullscreen", help: "Toggle Fullscreen (F)", action: #selector(fullscreenTapped))
        previousButton.identifier = NSUserInterfaceItemIdentifier(SkimControlAccessibility.previousIdentifier)
        skimButton.identifier = NSUserInterfaceItemIdentifier(SkimControlAccessibility.toggleIdentifier)
        queueButton.identifier = NSUserInterfaceItemIdentifier(SkimControlAccessibility.queueIdentifier)
        queueButton.nextKeyView = skimButton
        skimButton.nextKeyView = previousButton
        previousButton.nextKeyView = playPauseButton
        playPauseButton.nextKeyView = nextButton
        nextButton.nextKeyView = volumeButton
        volumeButton.nextKeyView = fullscreenButton

        markerLabels = (0..<4).map { _ in
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setAccessibilityElement(true)
            addSubview(label)
            return label
        }
    }

    private func configure(_ button: RailButton,
                           symbol: String,
                           label: String,
                           help: String,
                           action: Selector,
                           emphasized: Bool = false) {
        button.target = self
        button.action = action
        button.railStyle = emphasized ? .emphasized : .normal
        button.configureSymbol(symbol, pointSize: emphasized ? 15 : 12,
                               accessibilityLabel: label, help: help)
        addSubview(button)
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let geometry = PlaybackBarPresentation.layout(width: width)
        let side = geometry.edgeInset
        let button: CGFloat = 30
        let play: CGFloat = 36
        let gap = geometry.gap
        var x = (width - geometry.centeredWidth) / 2
        let y: CGFloat = 3
        queueButton.frame = NSRect(x: side, y: y + 3, width: button, height: button)
        queueButton.layer?.cornerRadius = button / 2
        fullscreenButton.frame = NSRect(x: max(side, width - side - button), y: y + 3, width: button, height: button)
        fullscreenButton.layer?.cornerRadius = button / 2
        for control in [skimButton, previousButton] {
            control.frame = NSRect(x: x, y: y + 3, width: button, height: button)
            control.layer?.cornerRadius = button / 2
            x += button + gap
        }
        playPauseButton.frame = NSRect(x: x, y: y, width: play, height: play)
        playPauseButton.layer?.cornerRadius = play / 2
        x += play + gap
        for control in [nextButton, volumeButton] {
            control.frame = NSRect(x: x, y: y + 3, width: button, height: button)
            control.layer?.cornerRadius = button / 2
            x += button + gap
        }

        for (label, cell) in zip(markerLabels, geometry.markerCells) {
            label.frame = cell
        }
        scrubber.frame = NSRect(x: side, y: 58, width: max(0, width - side * 2), height: 12)
    }

    func invalidateCachedDisplayState() {
        pendingSeekPosition = nil
        pendingSeekDate = nil
    }

    func notifySeek(to position: Float) {
        pendingSeekPosition = position
        pendingSeekDate = Date()
    }

    func update() {
        queueButton.isEnabled = controller != nil
        queueButton.isToggled = controller?.isQueuePageOpen ?? false
        previousButton.isEnabled = controller?.hasPrevious ?? false
        nextButton.isEnabled = controller?.hasNext ?? false
        updateSkimButton()
        updateMarkers()

        if isImageMode {
            scrubber.isHidden = true
            playPauseButton.isEnabled = true
            setPlaySymbol(isPlaying: imageModeIsPlaying)
            volumeButton.isEnabled = false
            return
        }

        scrubber.isHidden = false
        let hasMedia = player?.media != nil
        playPauseButton.isEnabled = hasMedia
        volumeButton.isEnabled = hasMedia
        setPlaySymbol(isPlaying: player?.isPlaying == true)
        setVolumeSymbol()

        if let range = controller?.activePreviewRange {
            scrubber.activeRange = range
            let description = "Preview range \(formatTime(range.startSeconds)) to \(formatTime(range.endSeconds))"
            scrubber.setAccessibilityValue(description)
            scrubber.toolTip = description
        } else {
            scrubber.activeRange = nil
            scrubber.setAccessibilityValue("Full media duration")
            scrubber.toolTip = "Relocate preview and seek"
        }
        guard !isScrubbing else { return }
        var position = player?.position ?? 0
        if let pending = pendingSeekPosition {
            let age = pendingSeekDate.map { Date().timeIntervalSince($0) } ?? 2
            if abs(position - pending) >= 0.01, age < 1.5 { position = pending }
            else { pendingSeekPosition = nil; pendingSeekDate = nil }
        }
        if position.isFinite { scrubber.doubleValue = Double(max(0, min(1, position))) }
    }

    private func updateMarkers() {
        let markers = PlaybackBarPresentation.markers(settings: SkimSettingsStore.shared.snapshot())
        let geometry = PlaybackBarPresentation.layout(width: bounds.width)
        for ((label, marker), cell) in zip(zip(markerLabels, markers), geometry.markerCells) {
            label.stringValue = marker.displayText(at: cell.width)
            label.toolTip = marker.fullText
            label.setAccessibilityLabel(marker.fullText.components(separatedBy: " ").prefix(2).joined(separator: " "))
            label.setAccessibilityValue(marker.accessibilityValue)
            label.textColor = marker.isActive ? .secondaryLabelColor : .tertiaryLabelColor
            label.alphaValue = marker.isActive ? 0.9 : 0.48
        }
    }

    private func setPlaySymbol(isPlaying: Bool) {
        playPauseButton.configureSymbol(isPlaying ? "pause.fill" : "play.fill",
                                        pointSize: 15,
                                        accessibilityLabel: isPlaying ? "Pause" : "Play",
                                        help: "Play or Pause (Space)")
    }

    private func setVolumeSymbol() {
        let muted = (player?.audio?.volume ?? 0) == 0
        volumeButton.configureSymbol(muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                     pointSize: 12,
                                     accessibilityLabel: muted ? "Unmute" : "Mute",
                                     help: "Mute or Unmute (M)")
    }

    private func updateSkimButton() {
        let presentation = SkimControlPresentation(isEnabled: controller?.isSkimEnabled ?? true)
        skimButton.isEnabled = controller != nil
        skimButton.isToggled = presentation.isEnabled
        skimButton.railStyle = presentation.isEnabled ? .skimActive : .skimInactive
        skimButton.configureSymbol(
            presentation.isEnabled ? "bolt.fill" : "bolt.slash",
            pointSize: 12,
            accessibilityLabel: "Skim",
            help: presentation.toggleHelp,
            fallbackNames: presentation.isEnabled ? ["play.fill"] : ["nosign"]
        )
        skimButton.setAccessibilityValue(presentation.toggleAccessibilityValue)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    @objc private func scrubberMoved(_ sender: NSSlider) {
        guard !isImageMode else { return }
        let position = Float(max(0, min(1, sender.doubleValue)))
        player?.position = position
        controller?.notifyUserSeek(targetPosition: position, source: "preview-scrub")
        notifySeek(to: position)
    }

    @objc private func queueTapped() { controller?.toggleQueuePage() }
    @objc private func previousTapped() { controller?.playPrevious() }
    @objc private func skimTapped() { controller?.toggleSkimEnabled(source: "top-bar") }
    @objc private func playPauseTapped() { controller?.togglePlayPause() }
    @objc private func nextTapped() { controller?.playNext() }
    @objc private func volumeTapped() { controller?.toggleMuteFromTransport() }
    @objc private func fullscreenTapped() { window?.toggleFullScreen(nil) }
}

final class PreviewRangeSlider: NSSlider {
    var scrubDidBegin: (() -> Void)?
    var scrubDidEnd: (() -> Void)?
    var activeRange: ActivePreviewRange? {
        didSet {
            (cell as? PreviewRangeSliderCell)?.activeRange = activeRange
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = PreviewRangeSliderCell()
        focusRingType = .default
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func mouseDown(with event: NSEvent) {
        scrubDidBegin?()
        (cell as? PreviewRangeSliderCell)?.emphasizesThumb = true
        needsDisplay = true
        super.mouseDown(with: event)
        (cell as? PreviewRangeSliderCell)?.emphasizesThumb = false
        needsDisplay = true
        scrubDidEnd?()
    }
}

private final class PreviewRangeSliderCell: NSSliderCell {
    var activeRange: ActivePreviewRange?
    var emphasizesThumb = false

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let bar = NSRect(x: rect.minX, y: rect.midY - 1, width: rect.width, height: 2)
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
        guard let range = activeRange, range.totalDurationSeconds > 0 else { return }
        let start = CGFloat(range.normalizedStart)
        let end = CGFloat(range.normalizedEnd)
        let active = NSRect(x: bar.minX + bar.width * start,
                            y: bar.minY - 1,
                            width: max(1, bar.width * (end - start)),
                            height: 4)
        SkimColors.darkTeal.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: active, xRadius: 2, yRadius: 2).fill()

        let progress = CGFloat(max(range.normalizedStart,
                                   min(range.normalizedEnd, doubleValue)))
        let progressed = NSRect(x: active.minX,
                                y: active.minY,
                                width: max(0, bar.width * progress - active.minX + bar.minX),
                                height: active.height)
        SkimColors.periwinkle.setFill()
        NSBezierPath(roundedRect: progressed, xRadius: 2, yRadius: 2).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let size: CGFloat = emphasizesThumb ? 8 : 5
        let rect = NSRect(x: knobRect.midX - size / 2,
                          y: knobRect.midY - size / 2,
                          width: size,
                          height: size)
        NSColor.white.withAlphaComponent(emphasizesThumb ? 0.95 : 0.64).setFill()
        NSBezierPath(ovalIn: rect).fill()
    }
}
