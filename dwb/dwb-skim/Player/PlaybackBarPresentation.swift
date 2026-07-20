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

enum PlaybackBarPresentation {
    static let controlOrder = ["Queue", "Skim", "Previous", "Play/Pause", "Next", "Volume", "Fullscreen"]

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
        let edgeInset = max(8, min(18, width * 0.025))
        let minimumGap: CGFloat = 2
        let preferredGap: CGFloat = 8
        let middleWidth = buttonSize * 4 + playSize
        let availableGap = max(minimumGap, min(preferredGap, (width - middleWidth) / 4))
        let centeredWidth = middleWidth + availableGap * 4
        let railWidth = max(0, width - edgeInset * 2)
        let cellWidth = railWidth / 4
        let markerCells = (0..<4).map {
            CGRect(x: edgeInset + CGFloat($0) * cellWidth, y: 42, width: cellWidth, height: 14)
        }
        return PlaybackBarLayout(edgeInset: edgeInset, gap: availableGap, centeredWidth: centeredWidth,
                                 markerCells: markerCells)
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
}

struct PlaybackBarLayout: Equatable {
    let edgeInset: CGFloat
    let gap: CGFloat
    let centeredWidth: CGFloat
    let markerCells: [CGRect]

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
