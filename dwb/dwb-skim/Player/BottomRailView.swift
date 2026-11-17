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
    private let bookmarkButton = RailButton()
    private let settingsButton = RailButton()
    private let manualAdvanceButton = RailButton()
    private let startFromTopButton = RailButton()
    private let backgroundAudioLabel = RailBackgroundAudioLabel()
    private let durationLabel = NSTextField(labelWithString: "")
    private var markerLabels: [NSTextField] = []
    private var pendingSeekPosition: Float?
    private var pendingSeekDate: Date?
    private var isScrubbing = false
    private var bookmarkButtonState: (enabled: Bool, bookmarked: Bool)?
    /// Whether this window's background track is playing. The layout still hides the label when
    /// the rail is too narrow to show it.
    private var wantsBackgroundAudioLabel = false

    static let bookmarkIdentifier = "skim.rail.bookmark"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setupViews()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(accessibilityOptionsChanged),
                                               name: DWBAccessibility.didChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(refreshShortcutHints),
                                               name: .shortcutsChanged,
                                               object: nil)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// A shortcut changed: rewrite the key named in each rail tooltip and help text.
    @objc private func refreshShortcutHints() {
        queueButton.updateHelp(ShortcutHints.help("Toggle queue panel", for: .toggleQueuePanel))
        previousButton.updateHelp(ShortcutHints.help("Previous item", for: .previousItem))
        playPauseButton.updateHelp(ShortcutHints.help("Play or Pause", for: .playPause))
        nextButton.updateHelp(ShortcutHints.help("Next item", for: .nextItem))
        startFromTopButton.updateHelp(ShortcutHints.help("Restart the queue from the top", for: .startQueueFromTop))
        manualAdvanceButton.updateHelp(ShortcutHints.help("Advance to the next Progressive Random Skim segment", for: .nextSkimSegment))
        fullscreenButton.updateHelp(ShortcutHints.help("Toggle Fullscreen", for: .toggleFullScreen))
        bookmarkButton.updateHelp(ShortcutHints.help("Bookmark", for: .toggleBookmark))
    }

    /// Increase Contrast changed: re-resolve the label colors that depend on it.
    @objc private func accessibilityOptionsChanged() {
        durationLabel.textColor = DWBAccessibility.textSecondary
        updateMarkers(isHidden: !durationLabel.isHidden)
    }

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

        configure(queueButton, symbol: "rectangle.righthalf.inset.filled", label: "Queue", help: ShortcutHints.help("Toggle queue panel", for: .toggleQueuePanel), action: #selector(queueTapped))
        configure(previousButton, symbol: "backward.end.fill", label: "Previous", help: ShortcutHints.help("Previous item", for: .previousItem), action: #selector(previousTapped))
        configure(skimButton, symbol: "bolt.fill", label: "Skim", help: "Skim is on. Double-tap Option to toggle Skim.", action: #selector(skimTapped))
        configure(playPauseButton, symbol: "play.fill", label: "Play or Pause", help: ShortcutHints.help("Play or Pause", for: .playPause), action: #selector(playPauseTapped), emphasized: true)
        configure(nextButton, symbol: "forward.end.fill", label: "Next", help: ShortcutHints.help("Next item", for: .nextItem), action: #selector(nextTapped))
        configure(volumeButton, symbol: "speaker.wave.2.fill", label: "Mute or Unmute", help: "Mute or Unmute", action: #selector(volumeTapped))
        configure(fullscreenButton, symbol: "arrow.up.left.and.arrow.down.right", label: "Fullscreen", help: ShortcutHints.help("Toggle Fullscreen", for: .toggleFullScreen), action: #selector(fullscreenTapped))
        configure(bookmarkButton, symbol: "bookmark", label: "Bookmark", help: ShortcutHints.help("Bookmark", for: .toggleBookmark), action: #selector(bookmarkTapped))
        configure(settingsButton, symbol: "gearshape", label: "Settings", help: "Open Settings", action: #selector(settingsTapped))
        configure(manualAdvanceButton, symbol: "forward.frame.fill", label: "Advance Segment",
                 help: ShortcutHints.help("Advance to the next Progressive Random Skim segment", for: .nextSkimSegment),
                 action: #selector(manualAdvanceTapped))
        configure(startFromTopButton, symbol: "backward.frame.fill", label: "Start From Top",
                  help: ShortcutHints.help("Restart the queue from the top", for: .startQueueFromTop),
                  action: #selector(startFromTopTapped))
        previousButton.identifier = NSUserInterfaceItemIdentifier(SkimControlAccessibility.previousIdentifier)
        skimButton.identifier = NSUserInterfaceItemIdentifier(SkimControlAccessibility.toggleIdentifier)
        queueButton.identifier = NSUserInterfaceItemIdentifier(SkimControlAccessibility.queueIdentifier)
        bookmarkButton.identifier = NSUserInterfaceItemIdentifier(Self.bookmarkIdentifier)
        bookmarkButton.railStyle = .bookmark
        // Tab order: Queue, Skim, Start From Top, Previous, Play or Pause, Next, Advance Segment,
        // Volume, then the right group. The "dwb+ on" label is text and is not in the chain.
        queueButton.nextKeyView = skimButton
        skimButton.nextKeyView = startFromTopButton
        startFromTopButton.nextKeyView = previousButton
        previousButton.nextKeyView = playPauseButton
        playPauseButton.nextKeyView = nextButton
        nextButton.nextKeyView = manualAdvanceButton
        manualAdvanceButton.nextKeyView = volumeButton
        volumeButton.nextKeyView = fullscreenButton
        fullscreenButton.nextKeyView = bookmarkButton
        bookmarkButton.nextKeyView = settingsButton

        backgroundAudioLabel.isHidden = true
        addSubview(backgroundAudioLabel)

        durationLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        durationLabel.alignment = .center
        durationLabel.textColor = DWBAccessibility.textSecondary
        durationLabel.maximumNumberOfLines = 1
        durationLabel.isHidden = true
        durationLabel.setAccessibilityElement(true)
        durationLabel.setAccessibilityLabel("Playback Time")
        durationLabel.identifier = NSUserInterfaceItemIdentifier("playbackDurationTimer")
        addSubview(durationLabel)

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
        button.configureSymbol(symbol, accessibilityLabel: label, help: help)
        addSubview(button)
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let geometry = PlaybackBarPresentation.layout(width: width)
        let side = geometry.edgeInset
        let button = DWBMetrics.railButton
        let play = DWBMetrics.railButtonPrimary
        let gap = geometry.gap
        var x = (width - geometry.centeredWidth) / 2
        let y: CGFloat = 3
        queueButton.frame = NSRect(x: side, y: y + 3, width: button, height: button)
        fullscreenButton.frame = NSRect(x: max(side, width - side - button), y: y + 3, width: button, height: button)
        settingsButton.frame = NSRect(x: max(side, fullscreenButton.frame.minX - gap - button), y: y + 3, width: button, height: button)
        for control in [skimButton, startFromTopButton, previousButton] {
            control.frame = NSRect(x: x, y: y + 3, width: button, height: button)
            x += button + gap
        }
        playPauseButton.frame = NSRect(x: x, y: y, width: play, height: play)
        x += play + gap
        for control in [nextButton, manualAdvanceButton, volumeButton] {
            control.frame = NSRect(x: x, y: y + 3, width: button, height: button)
            x += button + gap
        }
        // Bookmark sits immediately before Settings, and the "dwb+ on" label immediately before
        // Bookmark. When the rail is too narrow, an item that would overlap the centered transport
        // group is hidden instead: the label first, then Bookmark.
        let bookmarkX = settingsButton.frame.minX - gap - button
        bookmarkButton.frame = NSRect(x: bookmarkX, y: y + 3, width: button, height: button)
        let labelSize = backgroundAudioLabel.contentSize
        let labelX = bookmarkX - gap - labelSize.width
        backgroundAudioLabel.frame = NSRect(x: labelX,
                                            y: y + 3 + (button - labelSize.height) / 2,
                                            width: labelSize.width,
                                            height: labelSize.height)
        let visibility = PlaybackBarPresentation.rightGroupVisibility(labelWanted: wantsBackgroundAudioLabel,
                                                                      labelX: labelX,
                                                                      bookmarkX: bookmarkX,
                                                                      centerEndX: x)
        bookmarkButton.isHidden = !visibility.showsBookmark
        backgroundAudioLabel.isHidden = !visibility.showsBackgroundAudioLabel

        for (label, cell) in zip(markerLabels, geometry.markerCells) {
            label.frame = cell
        }
        durationLabel.frame = geometry.durationTimerFrame
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
        manualAdvanceButton.isEnabled = controller?.canManuallyAdvanceProgressiveRandomSkimSegment ?? false
        startFromTopButton.isEnabled = controller?.canStartQueueFromTop ?? false
        updateBackgroundAudioLabel()
        updateSkimButton()
        updateBookmarkButton()
        let isShowingDuration = updateDurationLabel()
        updateMarkers(isHidden: isShowingDuration)
        updateSegmentMarkers()

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

    /// Part 4: normalizes `controller.progressiveRandomSkimSegmentPlan` (playback seconds,
    /// always sourced from the live plan — see that property's doc) against the current media
    /// duration for the scrub bar's segment ticks and bars. No segments when there's no known
    /// duration yet, mirroring how `activeRange` position itself only renders once duration is known.
    private func updateSegmentMarkers() {
        let totalDuration = Double(player?.media?.length.intValue ?? 0) / 1000
        guard !isImageMode, totalDuration.isFinite, totalDuration > 0,
              let plan = controller?.progressiveRandomSkimSegmentPlan else {
            scrubber.setSegments([], activeIndex: nil)
            return
        }
        let segments = plan.segments.map { segment in
            ScrubberSegment(start: CGFloat(max(0, min(1, segment.startOffsetSeconds / totalDuration))),
                            end: CGFloat(max(0, min(1, (segment.startOffsetSeconds + segment.durationSeconds) / totalDuration))))
        }
        scrubber.setSegments(segments, activeIndex: plan.activeIndex)
    }

    private func updateMarkers(isHidden: Bool) {
        let markers = PlaybackBarPresentation.markers(settings: SkimSettingsStore.shared.snapshot())
        let geometry = PlaybackBarPresentation.layout(width: bounds.width)
        for ((label, marker), cell) in zip(zip(markerLabels, markers), geometry.markerCells) {
            label.isHidden = isHidden
            label.stringValue = marker.displayText(at: cell.width)
            label.toolTip = marker.fullText
            label.setAccessibilityLabel(marker.fullText.components(separatedBy: " ").prefix(2).joined(separator: " "))
            label.setAccessibilityValue(marker.accessibilityValue)
            label.textColor = marker.isActive ? DWBAccessibility.textSecondary : DWBColor.textDisabled
        }
    }

    private func updateDurationLabel() -> Bool {
        let presentation = PlaybackBarPresentation.duration(
            elapsedMilliseconds: player?.time.intValue ?? 0,
            durationMilliseconds: player?.media?.length.intValue ?? 0,
            isSkimEnabled: controller?.isSkimEnabled ?? true,
            isImageMode: isImageMode
        )
        durationLabel.isHidden = presentation == nil
        durationLabel.stringValue = presentation?.text ?? ""
        durationLabel.setAccessibilityValue(presentation?.accessibilityValue ?? "")
        return presentation != nil
    }

    private func setPlaySymbol(isPlaying: Bool) {
        playPauseButton.configureSymbol(isPlaying ? "pause.fill" : "play.fill",
                                        accessibilityLabel: isPlaying ? "Pause" : "Play",
                                        help: ShortcutHints.help("Play or Pause", for: .playPause))
    }

    private func setVolumeSymbol() {
        let volume = player?.audio?.volume ?? 0
        let muted = volume == 0
        volumeButton.railStyle = volume > Int32(VideoVolumeMeterPresentation.regularVolumeMaximum) ? .warning : .normal
        volumeButton.configureSymbol(muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                     accessibilityLabel: muted ? "Unmute" : "Mute",
                                     help: "Mute or Unmute")
    }

    /// The "dwb+ on" label shows only while this window's background track is playing.
    private func updateBackgroundAudioLabel() {
        let wanted = PlaybackBarPresentation.showsBackgroundAudioLabel(for: controller?.backgroundAudioState ?? .inactive)
        guard wanted != wantsBackgroundAudioLabel else { return }
        wantsBackgroundAudioLabel = wanted
        needsLayout = true
    }

    private func updateBookmarkButton() {
        let url = controller?.currentMediaURL
        let state = (enabled: url != nil,
                     bookmarked: url.map { BookmarkStore.shared.isBookmarked(url: $0) } ?? false)
        guard bookmarkButtonState?.enabled != state.enabled
                || bookmarkButtonState?.bookmarked != state.bookmarked else { return }
        bookmarkButtonState = state
        bookmarkButton.isEnabled = state.enabled
        bookmarkButton.isToggled = state.bookmarked
        bookmarkButton.configureSymbol(state.bookmarked ? "bookmark.fill" : "bookmark",
                                       accessibilityLabel: state.bookmarked ? "Remove Bookmark" : "Bookmark",
                                       help: ShortcutHints.help("Bookmark", for: .toggleBookmark))
        bookmarkButton.setAccessibilityValue(state.bookmarked ? "bookmarked" : "not bookmarked")
    }

    private func updateSkimButton() {
        let presentation = SkimControlPresentation(isEnabled: controller?.isSkimEnabled ?? true)
        skimButton.isEnabled = controller != nil
        skimButton.isToggled = presentation.isEnabled
        skimButton.railStyle = presentation.isEnabled ? .skimActive : .skimInactive
        skimButton.configureSymbol(
            presentation.isEnabled ? "bolt.fill" : "bolt.slash",
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
    @objc private func startFromTopTapped() { controller?.startQueueFromTop() }
    @objc private func volumeTapped() { controller?.toggleMuteFromTransport() }
    @objc private func fullscreenTapped() { window?.toggleFullScreen(nil) }
    @objc private func bookmarkTapped() { controller?.toggleBookmark() }
    @objc private func settingsTapped() { SettingsWindowController.shared.openSettings() }
    @objc private func manualAdvanceTapped() { controller?.manuallyAdvanceProgressiveRandomSkimSegment() }
}

/// The rail's "dwb+ on" label (design system 9.8): plain 11 pt text, "dwb+" semibold `textSecondary`
/// then "on" regular `textTertiary`, 4 pt apart. It is not a button and not in the Tab order. The rail
/// shows it only while this window's background track plays.
final class RailBackgroundAudioLabel: NSView {
    static let spokenText = "dwb+ on"
    private static let gap: CGFloat = 4

    private let brandFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private let stateFont = NSFont.systemFont(ofSize: 11, weight: .regular)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "dwb+ background audio is playing"
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(Self.spokenText)
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    convenience init() { self.init(frame: .zero) }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private func attributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color]
    }

    private var brandAttributes: [NSAttributedString.Key: Any] {
        attributes(font: brandFont, color: DWBAccessibility.textSecondary)
    }

    private var stateAttributes: [NSAttributedString.Key: Any] {
        attributes(font: stateFont, color: DWBAccessibility.textTertiary)
    }

    var contentSize: NSSize {
        let brand = ("dwb+" as NSString).size(withAttributes: [.font: brandFont])
        let state = ("on" as NSString).size(withAttributes: [.font: stateFont])
        return NSSize(width: ceil(brand.width) + Self.gap + ceil(state.width),
                      height: ceil(max(brand.height, state.height)))
    }

    override func draw(_ dirtyRect: NSRect) {
        let brand = ("dwb+" as NSString)
        let brandSize = brand.size(withAttributes: brandAttributes)
        brand.draw(at: NSPoint(x: 0, y: floor((bounds.height - brandSize.height) / 2)), withAttributes: brandAttributes)
        let state = ("on" as NSString)
        let stateSize = state.size(withAttributes: stateAttributes)
        state.draw(at: NSPoint(x: ceil(brandSize.width) + Self.gap, y: floor((bounds.height - stateSize.height) / 2)),
                   withAttributes: stateAttributes)
    }

    @objc private func accessibilityDidChange() { needsDisplay = true }
}

/// One planned Progressive Random Skim segment on the scrub bar, as fractions (0...1) of the media.
struct ScrubberSegment: Equatable {
    let start: CGFloat
    let end: CGFloat
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

    private var scrubberTracking: NSTrackingArea?

    /// Part 4: sets the Progressive Random Skim segments, rendered as ticks plus bars for the segment
    /// now playing and the segments already played. `activeIndex` is the segment now playing;
    /// segments before it are visited. Position-only — no "segment X of Y" text.
    func setSegments(_ segments: [ScrubberSegment], activeIndex: Int?) {
        guard let sliderCell = cell as? PreviewRangeSliderCell,
              sliderCell.segments != segments || sliderCell.activeSegment != activeIndex else { return }
        sliderCell.segments = segments
        sliderCell.activeSegment = activeIndex
        needsDisplay = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = PreviewRangeSliderCell()
        focusRingType = .default
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(accessibilityOptionsChanged),
                                               name: DWBAccessibility.didChange,
                                               object: nil)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func accessibilityOptionsChanged() { needsDisplay = true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let scrubberTracking { removeTrackingArea(scrubberTracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        scrubberTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        (cell as? PreviewRangeSliderCell)?.isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        (cell as? PreviewRangeSliderCell)?.isHovering = false
        needsDisplay = true
    }

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
    var isHovering = false
    var segments: [ScrubberSegment] = []
    var activeSegment: Int?

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let bar = NSRect(x: rect.minX, y: rect.midY - DWBMetrics.scrubberTrack / 2,
                         width: rect.width, height: DWBMetrics.scrubberTrack)
        DWBAccessibility.track.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()

        if segments.isEmpty {
            drawPreviewRange(bar: bar)
        } else {
            drawSegments(bar: bar)
        }

        let knobX = min(bar.maxX, max(bar.minX, knobRect(flipped: flipped).midX))
        let played = NSRect(x: bar.minX, y: bar.minY, width: knobX - bar.minX, height: bar.height)
        theme.accentText.setFill()
        NSBezierPath(roundedRect: played, xRadius: 1, yRadius: 1).fill()
    }

    /// The 4 pt preview range bar, when a range is active and Progressive Random Skim has no plan.
    private func drawPreviewRange(bar: NSRect) {
        guard let range = activeRange, range.totalDurationSeconds > 0 else { return }
        let start = CGFloat(range.normalizedStart)
        let end = CGFloat(range.normalizedEnd)
        let rangeBar = NSRect(x: bar.minX + bar.width * start,
                              y: bar.midY - DWBMetrics.scrubberRange / 2,
                              width: max(1, bar.width * (end - start)),
                              height: DWBMetrics.scrubberRange)
        theme.accentRange.setFill()
        NSBezierPath(roundedRect: rangeBar, xRadius: 2, yRadius: 2).fill()
    }

    /// Progressive scrubber (9.8): unvisited segments get a tick; visited ones a `textSecondary`
    /// tick plus a 4 pt `accentRange` bar; the active one a 4 pt `accentFill` bar with a 1 pt
    /// `accentText` edge and a taller `accentText` tick.
    private func drawSegments(bar: NSRect) {
        for (index, segment) in segments.enumerated() {
            let isActive = index == activeSegment
            let isVisited = activeSegment.map { index < $0 } ?? false
            let startX = bar.minX + bar.width * max(0, min(1, segment.start))
            let endX = bar.minX + bar.width * max(0, min(1, segment.end))
            guard isActive || isVisited else { continue }
            let segmentBar = NSRect(x: startX,
                                    y: bar.midY - DWBMetrics.scrubberRange / 2,
                                    width: max(3, endX - startX),
                                    height: DWBMetrics.scrubberRange)
            let path = NSBezierPath(roundedRect: segmentBar, xRadius: 2, yRadius: 2)
            (isActive ? theme.accentFill : theme.accentRange).setFill()
            path.fill()
            if isActive {
                theme.accentText.setStroke()
                let edge = NSBezierPath(roundedRect: segmentBar.insetBy(dx: -0.5, dy: -0.5), xRadius: 2.5, yRadius: 2.5)
                edge.lineWidth = 1
                edge.stroke()
            }
        }
        for (index, segment) in segments.enumerated() {
            let isActive = index == activeSegment
            let isVisited = activeSegment.map { index < $0 } ?? false
            let x = bar.minX + bar.width * max(0, min(1, segment.start))
            let height: CGFloat = isActive ? 10 : 8
            let tick = NSRect(x: x - 0.75, y: bar.midY - height / 2, width: 1.5, height: height)
            let color: NSColor
            if isActive {
                color = theme.accentText
            } else if isVisited {
                color = DWBAccessibility.textSecondary
            } else {
                color = DWBAccessibility.tick
            }
            color.setFill()
            NSBezierPath(roundedRect: tick, xRadius: 0.75, yRadius: 0.75).fill()
        }
    }

    override func drawKnob(_ knobRect: NSRect) {
        let grows = (emphasizesThumb || isHovering) && !DWBAccessibility.reduceMotion
        let size = grows ? DWBMetrics.knobEmphasized : DWBMetrics.knob
        let rect = NSRect(x: knobRect.midX - size / 2,
                          y: knobRect.midY - size / 2,
                          width: size,
                          height: size)
        DWBColor.textPrimary.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }
}
