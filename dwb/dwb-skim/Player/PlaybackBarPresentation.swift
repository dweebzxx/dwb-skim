import Foundation

/// Pure presentation data for the compact, non-editing playback-bar markers.
struct PlaybackBarMarker: Equatable {
    let compactText: String
    let fullText: String
    let accessibilityValue: String
    let isActive: Bool

    func displayText(at cellWidth: CGFloat) -> String {
        guard cellWidth < 118 else { return compactText }
        let value = compactText.split(separator: " ").dropFirst().joined(separator: " ")
        switch fullText {
        case let text where text.hasPrefix("Clip Duration"):
            return "Clip \(value)"
        case let text where text.hasPrefix("Start Position"):
            return "Start \(value)"
        case let text where text.hasPrefix("Skip Intro"):
            return "Intro \(value)"
        default:
            let shortValue: String
            switch value {
            case "Sequential": shortValue = "Seq"
            case "Weighted": shortValue = "Wt"
            default: shortValue = value
            }
            return "Order \(shortValue)"
        }
    }
}

/// Pure display state for normal-playback timing in the bottom rail.
struct PlaybackDurationPresentation: Equatable {
    let text: String
    let accessibilityValue: String
}

enum PlaybackBarPresentation {
    /// The rail, left to right (design system 9.8): the left group is Queue; the center group is
    /// Skim, Start From Top, Previous, Play or Pause, Next, Advance Segment, Volume; the right
    /// group is the "dwb+ on" label (when shown), Bookmark, Settings, Fullscreen.
    static let controlOrder = ["Queue",
                               "Skim", "Start From Top", "Previous", "Play/Pause", "Next", "Advance Segment", "Volume",
                               "dwb+ on", "Bookmark", "Settings", "Fullscreen"]

    /// The center group holds six 30 pt buttons and the 36 pt Play button, with six gaps between them.
    static let centerButtonCount = 6

    /// The "dwb+ on" label shows only while this window's background track is playing. It is removed
    /// (not dimmed) when the track is paused, off, or not available.
    static func showsBackgroundAudioLabel(for state: BackgroundAudioPlaybackState) -> Bool {
        if case .playing = state { return true }
        return false
    }

    /// Which right-group items fit. `centerEndX` is where the center group ends, including its trailing
    /// gap. An item hides when it would start left of that point. The label sits left of Bookmark, so it
    /// is the first to hide; Bookmark hides by its own test, and always after the label.
    static func rightGroupVisibility(labelWanted: Bool,
                                     labelX: CGFloat,
                                     bookmarkX: CGFloat,
                                     centerEndX: CGFloat) -> RailRightGroupVisibility {
        RailRightGroupVisibility(showsBackgroundAudioLabel: labelWanted && labelX >= centerEndX && bookmarkX >= centerEndX,
                                 showsBookmark: bookmarkX >= centerEndX)
    }

    static func markers(settings: SkimSettingsSnapshot) -> [PlaybackBarMarker] {
        let clipText: String
        if settings.previewDurationMode == SettingsDefaultsRegistry.Defaults.previewDurationModeRandom {
            clipText = "Random \(settings.randomDurationRange.lowerBound)–\(settings.randomDurationRange.upperBound)s"
        } else {
            clipText = "\(settings.fixedDurationSeconds)s"
        }
        let startText = settings.startPositionMode == SettingsDefaultsRegistry.Defaults.startPositionModeBeginning ? "Beginning" : "Random"
        let introText = settings.skipIntroSeconds == 0 ? "Off" : "\(settings.skipIntroSeconds)s"
        return [
            marker(compact: "Clip \(clipText)", full: "Clip Duration \(clipText)", active: settings.skimEnabled),
            marker(compact: "Start \(startText)", full: "Start Position \(startText)", active: settings.skimEnabled),
            marker(compact: "Intro \(introText)", full: "Skip Intro \(introText)", active: true),
            marker(compact: queueText(settings.queueOrderMode), full: "Queue Order \(queueText(settings.queueOrderMode))", active: true),
        ]
    }

    static func layout(width: CGFloat, buttonSize: CGFloat = 30, playSize: CGFloat = 36) -> PlaybackBarLayout {
        let edgeInset: CGFloat = 16
        let minimumGap: CGFloat = 2
        let preferredGap: CGFloat = 8
        let buttonCount = CGFloat(centerButtonCount)
        let middleWidth = buttonSize * buttonCount + playSize
        let availableGap = max(minimumGap, min(preferredGap, (width - middleWidth) / buttonCount))
        let centeredWidth = middleWidth + availableGap * buttonCount
        let railWidth = max(0, width - edgeInset * 2)
        let cellWidth = railWidth / 4
        let markerCells = (0..<4).map {
            CGRect(x: edgeInset + CGFloat($0) * cellWidth, y: 42, width: cellWidth, height: 14)
        }
        let durationWidth = min(180, railWidth)
        let durationTimerFrame = CGRect(x: (width - durationWidth) / 2, y: 42,
                                        width: durationWidth, height: 14)
        return PlaybackBarLayout(edgeInset: edgeInset, gap: availableGap, centeredWidth: centeredWidth,
                                 markerCells: markerCells, durationTimerFrame: durationTimerFrame)
    }

    static func duration(elapsedMilliseconds: Int32,
                         durationMilliseconds: Int32,
                         isSkimEnabled: Bool,
                         isImageMode: Bool) -> PlaybackDurationPresentation? {
        guard !isSkimEnabled, !isImageMode, durationMilliseconds > 0 else { return nil }
        let durationSeconds = Int(durationMilliseconds) / 1_000
        let elapsedSeconds = max(0, min(durationSeconds, Int(elapsedMilliseconds) / 1_000))
        let remainingSeconds = durationSeconds - elapsedSeconds
        let elapsed = formatTime(elapsedSeconds)
        let remaining = formatTime(remainingSeconds)
        return PlaybackDurationPresentation(
            text: "\(elapsed)  -\(remaining)",
            accessibilityValue: "Elapsed \(elapsed), remaining \(remaining)"
        )
    }

    private static func marker(compact: String, full: String, active: Bool) -> PlaybackBarMarker {
        PlaybackBarMarker(compactText: compact, fullText: full,
                          accessibilityValue: active ? full : "\(full), inactive while Skim is off",
                          isActive: active)
    }

    private static func queueText(_ mode: QueueOrderMode) -> String {
        switch mode {
        case .sequential: return "Sequential"
        case .shuffle: return "Shuffle"
        case .weighted: return "Weighted"
        }
    }

    private static func formatTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// Start From Top plays the first item in the current display order. An empty queue has none.
enum StartFromTop {
    static func targetDisplayIndex(displayOrderCount: Int) -> Int? {
        displayOrderCount > 0 ? 0 : nil
    }
}

struct RailRightGroupVisibility: Equatable {
    let showsBackgroundAudioLabel: Bool
    let showsBookmark: Bool
}

struct PlaybackBarLayout: Equatable {
    let edgeInset: CGFloat
    let gap: CGFloat
    let centeredWidth: CGFloat
    let markerCells: [CGRect]
    let durationTimerFrame: CGRect

    var markerRail: CGRect {
        guard let first = markerCells.first, let last = markerCells.last else { return .zero }
        return first.union(last)
    }

    var middleOriginX: CGFloat { (markerRail.width + edgeInset * 2 - centeredWidth) / 2 }
}

/// Window-lifetime state for the strip; hiding never changes playback settings.
struct SkimControlsVisibilityState: Equatable {
    private(set) var isVisible = true
    mutating func hide() { isVisible = false }
    mutating func restore() { isVisible = true }
}

enum PlaybackChromePhase: Equatable {
    case visible
    case fading
    case hidden
}

/// One presentation state synchronizes every transient playback-chrome surface.
/// The host owns reveal-zone input; views only project this state.
struct PlaybackChromeVisibilityState: Equatable {
    private(set) var phase: PlaybackChromePhase = .visible
    private(set) var autoHideEnabled: Bool

    init(autoHideEnabled: Bool) {
        self.autoHideEnabled = autoHideEnabled
    }

    var isInteractive: Bool { phase != .hidden }

    func showsSkimRestoreButton(skimControlsExpanded: Bool, isFullscreen: Bool) -> Bool {
        !skimControlsExpanded && !isFullscreen && phase != .hidden
    }

    mutating func setAutoHideEnabled(_ enabled: Bool) {
        autoHideEnabled = enabled
        if !enabled { phase = .visible }
    }

    mutating func reveal() {
        phase = .visible
    }

    mutating func requestHide(reduceMotion: Bool) {
        guard autoHideEnabled else {
            phase = .visible
            return
        }
        phase = reduceMotion ? .hidden : .fading
    }

    mutating func completeHide() {
        guard phase == .fading else { return }
        phase = .hidden
    }
}
