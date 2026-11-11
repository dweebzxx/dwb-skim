import Foundation

/// One editable setting in the top Skim strip, with its plain name and the way its stored value reads.
enum SkimStripSetting: CaseIterable, Equatable {
    case clipDuration
    case startPosition
    case skipIntro
    case imageDuration
    case gifLoops
    case queueOrder
    case loopQueue
    case progressiveSkim

    var name: String {
        switch self {
        case .clipDuration: return "Clip duration"
        case .startPosition: return "Start position"
        case .skipIntro: return "Skip intro"
        case .imageDuration: return "Image duration"
        case .gifLoops: return "GIF loops"
        case .queueOrder: return "Queue order"
        case .loopQueue: return "Loop queue"
        case .progressiveSkim: return "Progressive skim"
        }
    }

    /// The stored value as the user reads it, from a snapshot taken after the store validated it.
    func value(in snapshot: SkimSettingsSnapshot, locale: Locale = .current) -> String {
        switch self {
        case .clipDuration:
            if snapshot.previewDurationMode == SettingsDefaultsRegistry.Defaults.previewDurationModeRandom {
                let range = snapshot.randomDurationRange
                return "Random \(range.lowerBound)–\(range.upperBound) s"
            }
            return "Fixed \(snapshot.fixedDurationSeconds) s"
        case .startPosition:
            return snapshot.startPositionMode == SettingsDefaultsRegistry.Defaults.startPositionModeBeginning
                ? "Beginning" : "Random"
        case .skipIntro:
            return "\(snapshot.skipIntroSeconds) s"
        case .imageDuration:
            return "\(Self.seconds(snapshot.imageDurationSeconds, locale: locale)) s"
        case .gifLoops:
            return snapshot.gifLoopCount == 1 ? "1 loop" : "\(snapshot.gifLoopCount) loops"
        case .queueOrder:
            return snapshot.queueOrderMode.rawValue.capitalized
        case .loopQueue:
            return snapshot.loopQueueEnabled ? "On" : "Off"
        case .progressiveSkim:
            return snapshot.progressiveRandomSkimEnabled ? "On" : "Off"
        }
    }

    /// True when the stored values behind this setting differ between two snapshots.
    func differs(_ before: SkimSettingsSnapshot, _ after: SkimSettingsSnapshot) -> Bool {
        switch self {
        case .clipDuration:
            return before.previewDurationMode != after.previewDurationMode
                || before.fixedDurationSeconds != after.fixedDurationSeconds
                || before.randomDurationRange != after.randomDurationRange
        case .startPosition: return before.startPositionMode != after.startPositionMode
        case .skipIntro: return before.skipIntroSeconds != after.skipIntroSeconds
        case .imageDuration: return before.imageDurationSeconds != after.imageDurationSeconds
        case .gifLoops: return before.gifLoopCount != after.gifLoopCount
        case .queueOrder: return before.queueOrderMode != after.queueOrderMode
        case .loopQueue: return before.loopQueueEnabled != after.loopQueueEnabled
        case .progressiveSkim: return before.progressiveRandomSkimEnabled != after.progressiveRandomSkimEnabled
        }
    }

    /// "Saved: Random 7–15 s" for tooltips and accessibility help, which keep the value after the HUD is gone.
    func savedDescription(in snapshot: SkimSettingsSnapshot, locale: Locale = .current) -> String {
        "Saved: \(value(in: snapshot, locale: locale))"
    }

    /// Whole numbers read plain ("3"); fractions keep up to two digits ("2.5", "0.25").
    private static func seconds(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// Which strip groups currently apply. Skim off greys Clip duration and Start position; an
/// unaccepted media type (Settings > Playback > Accepted media) greys its own group.
struct SkimStripActivity: Equatable {
    var skimEnabled: Bool
    var acceptsImages: Bool
    var acceptsGIFs: Bool

    func isActive(_ setting: SkimStripSetting) -> Bool { inactiveReason(setting) == nil }

    /// Why a group is inactive, for tooltips and accessibility help; nil when it applies.
    func inactiveReason(_ setting: SkimStripSetting) -> String? {
        switch setting {
        case .clipDuration, .startPosition:
            return skimEnabled ? nil : "Unavailable while Skim is off."
        case .imageDuration:
            return acceptsImages ? nil : "Unavailable while Images are off in Settings > Playback."
        case .gifLoops:
            return acceptsGIFs ? nil : "Unavailable while GIF is off in Settings > Playback."
        case .skipIntro, .queueOrder, .loopQueue, .progressiveSkim:
            return nil
        }
    }
}

/// The whole Skim rule in force, as one short line: "Progressive skim · random 7–15 s clips ·
/// skip 4 s · shuffle · loop queue". Progressive segments are spread across the video, so Start
/// Position is left out when it is on; Skip Intro applies in both modes.
enum SkimStripRuleSummary {
    static func make(_ snapshot: SkimSettingsSnapshot) -> String {
        var parts: [String] = []
        if snapshot.skimEnabled {
            parts.append(snapshot.progressiveRandomSkimEnabled ? "Progressive skim" : "Skim")
            if snapshot.previewDurationMode == SettingsDefaultsRegistry.Defaults.previewDurationModeRandom {
                let range = snapshot.randomDurationRange
                parts.append("random \(range.lowerBound)–\(range.upperBound) s clips")
            } else {
                parts.append("\(snapshot.fixedDurationSeconds) s clips")
            }
            if !snapshot.progressiveRandomSkimEnabled {
                parts.append(snapshot.startPositionMode == SettingsDefaultsRegistry.Defaults.startPositionModeBeginning
                    ? "from start" : "random start")
            }
            if snapshot.skipIntroSeconds > 0 { parts.append("skip \(snapshot.skipIntroSeconds) s") }
        } else {
            parts.append("Skim off")
            parts.append("plays in full")
        }
        switch snapshot.queueOrderMode {
        case .sequential: parts.append("in order")
        case .shuffle: parts.append("shuffle")
        case .weighted: parts.append("weighted")
        }
        if snapshot.loopQueueEnabled { parts.append("loop queue") }
        return parts.joined(separator: " · ")
    }
}

/// The confirmation the initiating window shows after a top-strip edit is committed.
struct SkimStripConfirmation: Equatable {
    let setting: SkimStripSetting
    let name: String
    let value: String
    /// The full rule in force after the edit (`SkimStripRuleSummary`).
    let rule: String

    /// "Clip duration · Random 7–15 s"
    var text: String { "\(name) · \(value)" }

    /// The same two lines read aloud, without the "·" separators.
    var spoken: String {
        "\(name), \(value). " + rule.replacingOccurrences(of: " · ", with: ", ")
    }

    /// `after` is the snapshot read back from the store once the edit was committed, so a clipped,
    /// rejected or normalized entry shows what persisted. Nothing is returned when nothing changed.
    static func make(for setting: SkimStripSetting,
                     before: SkimSettingsSnapshot,
                     after: SkimSettingsSnapshot,
                     locale: Locale = .current) -> SkimStripConfirmation? {
        guard setting.differs(before, after) else { return nil }
        return SkimStripConfirmation(setting: setting,
                                     name: setting.name,
                                     value: setting.value(in: after, locale: locale),
                                     rule: SkimStripRuleSummary.make(after))
    }
}
