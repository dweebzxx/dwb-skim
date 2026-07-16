import Foundation

enum SettingsDefaultsRegistry {
    enum Keys {
        static let autoHideTransportWindowed = "autoHideTransportWindowed"
        static let persistedVolume = "lastEffectiveVolume"
        static let skipDurationSeconds = "skipDurationSeconds"
        static let autoHideTitlebar = "autoHideTitlebar"
        static let completeVideoWindowMode = "completeVideoWindowMode"
        static let imageDurationSeconds = "imageDurationSeconds"
        static let gifLoopCount = "gifLoopCount"
        static let acceptVideoMedia = "acceptVideoMedia"
        static let acceptImageMedia = "acceptImageMedia"
        static let acceptGIFMedia = "acceptGIFMedia"
        static let showTitleOverlay = "showTitleOverlay"
        static let deletePrefixRenameEnabled = "deletePrefixRenameEnabled"
        static let videoPageDButtonEnabled = "videoPageDButtonEnabled"
        static let customPrefixValue = "customPrefixValue"
        static let customPrefixQueuePageEnabled = "customPrefixQueuePageEnabled"
        static let customPrefixVideoPageEnabled = "customPrefixVideoPageEnabled"
        static let customPrefixSecondaryValue = "customPrefixValue2"
        static let debugConsoleEnabled = "debugConsoleEnabled"
        static let verboseAutoplayTrace = "verboseAutoplayTrace"
        static let chromeAutohideThreshold = "chromeAutohideThreshold"
        static let chromeReducedMotion = "chromeReducedMotion"
        static let queuePanelOpenAtLaunch = "queuePanelOpenAtLaunch"
        static let bottomRailShowXButton = "bottomRailShowXButton"
        static let bottomRailShowShuffleButton = "bottomRailShowShuffleButton"
        static let bottomRailShowReplayButton = "bottomRailShowReplayButton"
        static let bottomRailShowVolumeButton = "bottomRailShowVolumeButton"
        static let bottomRailShowBookmarkButton = "bottomRailShowBookmarkButton"
        static let playerWindowOpacity = "playerWindowOpacity"
        static let clipDurationSeconds = "clipDurationSeconds"
        static let previewDurationMode = "previewDurationMode"
        static let randomPreviewMinimumSeconds = "randomPreviewMinimumSeconds"
        static let randomPreviewMaximumSeconds = "randomPreviewMaximumSeconds"
        static let startPositionMode = "startPositionMode"
        static let skipIntroSeconds = "skipIntroSeconds"
        static let queueOrderMode = "queueOrderMode"
        static let loopQueueEnabled = "loopQueueEnabled"

        enum OptionalTransportControl: CaseIterable {
            case stop, volume, shuffle, repeatOne

            var defaultsKey: String {
                switch self {
                case .stop:      return "showStopButton"
                case .volume:    return "showVolumeButton"
                case .shuffle:   return "showShuffleButton"
                case .repeatOne: return "showRepeatButton"
                }
            }
        }

        enum QueueColumn {
            static let durationVisible = "com.dwb.queueColumnDurationVisible"
            static let sizeVisible = "com.dwb.queueColumnSizeVisible"
            static let durationWidth = "com.dwb.queueColumnDurationWidth"
            static let sizeWidth = "com.dwb.queueColumnSizeWidth"
        }
    }

    enum Defaults {
        static let skipDurationSeconds = 10
        static let imageDurationSeconds = 3
        static let gifLoopCount = 1
        static let chromeAutohideThreshold = 3.0
        static let queueDurationColumnWidth = 92.0
        static let queueSizeColumnWidth = 104.0
        static let playerWindowOpacityMin = 0.35
        static let playerWindowOpacityMax = 1.0
        static let playerWindowOpacity = 1.0
        static let clipDurationSeconds = 10
        static let previewDurationModeFixed = "fixed"
        static let previewDurationModeRandom = "random"
        static let previewDurationMode = previewDurationModeFixed
        static let randomPreviewMinimumSeconds = 5
        static let randomPreviewMaximumSeconds = 30
        static let startPositionModeBeginning = "beginning"
        static let startPositionModeRandom = "random"
        static let startPositionMode = startPositionModeRandom
        static let skipIntroSeconds = 5
        static let queueOrderModeSequential = "sequential"
        static let queueOrderModeShuffle = "shuffle"
        static let queueOrderModeWeighted = "weighted"
        static let queueOrderMode = queueOrderModeSequential
        static let loopQueueEnabled = false
    }

    static func defaultValues(reduceMotionDefault: Bool) -> [String: Any] {
        var defaults: [String: Any] = [
            Keys.autoHideTransportWindowed: false,
            Keys.skipDurationSeconds: Defaults.skipDurationSeconds,
            Keys.imageDurationSeconds: Defaults.imageDurationSeconds,
            Keys.gifLoopCount: Defaults.gifLoopCount,
            Keys.acceptVideoMedia: true,
            Keys.acceptImageMedia: true,
            Keys.acceptGIFMedia: true,
            Keys.autoHideTitlebar: false,
            Keys.completeVideoWindowMode: false,
            Keys.showTitleOverlay: true,
            Keys.deletePrefixRenameEnabled: false,
            Keys.videoPageDButtonEnabled: false,
            Keys.customPrefixValue: "",
            Keys.customPrefixSecondaryValue: "",
            Keys.debugConsoleEnabled: false,
            Keys.verboseAutoplayTrace: false,
            Keys.chromeAutohideThreshold: Defaults.chromeAutohideThreshold,
            Keys.chromeReducedMotion: reduceMotionDefault,
            Keys.queuePanelOpenAtLaunch: false,
            Keys.bottomRailShowXButton: true,
            Keys.bottomRailShowShuffleButton: true,
            Keys.bottomRailShowReplayButton: true,
            Keys.bottomRailShowVolumeButton: true,
            Keys.bottomRailShowBookmarkButton: true,
            Keys.playerWindowOpacity: Defaults.playerWindowOpacity,
            Keys.clipDurationSeconds: Defaults.clipDurationSeconds,
            Keys.previewDurationMode: Defaults.previewDurationMode,
            Keys.randomPreviewMinimumSeconds: Defaults.randomPreviewMinimumSeconds,
            Keys.randomPreviewMaximumSeconds: Defaults.randomPreviewMaximumSeconds,
            Keys.startPositionMode: Defaults.startPositionMode,
            Keys.skipIntroSeconds: Defaults.skipIntroSeconds,
            Keys.queueOrderMode: Defaults.queueOrderMode,
            Keys.loopQueueEnabled: Defaults.loopQueueEnabled,
        ]

        for control in Keys.OptionalTransportControl.allCases {
            defaults[control.defaultsKey] = false
        }

        defaults[Keys.QueueColumn.durationVisible] = true
        defaults[Keys.QueueColumn.sizeVisible] = true
        defaults[Keys.QueueColumn.durationWidth] = Defaults.queueDurationColumnWidth
        defaults[Keys.QueueColumn.sizeWidth] = Defaults.queueSizeColumnWidth

        return defaults
    }

    static func register(defaults: UserDefaults = .standard, reduceMotionDefault: Bool) {
        defaults.register(defaults: defaultValues(reduceMotionDefault: reduceMotionDefault))
    }

    // MARK: - Skim preview settings validation (pure; no UserDefaults dependency)

    /// Clip duration cannot be negative. Zero preserves full-file playback behavior.
    static func validatedClipDurationSeconds(_ value: Int) -> Int {
        max(0, value)
    }

    static func validatedPreviewDurationMode(_ value: String) -> String {
        value == Defaults.previewDurationModeRandom ? Defaults.previewDurationModeRandom : Defaults.previewDurationModeFixed
    }

    static func validatedRandomPreviewMinimumSeconds(_ value: Int) -> Int {
        max(1, value)
    }

    static func validatedRandomPreviewMaximumSeconds(minimum: Int, maximum: Int) -> Int {
        max(validatedRandomPreviewMinimumSeconds(minimum), maximum)
    }

    static func validatedRandomPreviewDurationRange(minimum: Int, maximum: Int) -> ClosedRange<Int> {
        let minValue = validatedRandomPreviewMinimumSeconds(minimum)
        let maxValue = validatedRandomPreviewMaximumSeconds(minimum: minValue, maximum: maximum)
        return minValue...maxValue
    }

    /// Skip-intro seconds cannot be negative. Zero means no intro is skipped.
    static func validatedSkipIntroSeconds(_ value: Int) -> Int {
        max(0, value)
    }

    /// Any value other than the "beginning" mode string is treated as "random".
    static func validatedStartPositionMode(_ value: String) -> String {
        value == Defaults.startPositionModeBeginning ? Defaults.startPositionModeBeginning : Defaults.startPositionModeRandom
    }

    static func validatedQueueOrderMode(_ value: String) -> String {
        switch value {
        case Defaults.queueOrderModeSequential,
             Defaults.queueOrderModeShuffle,
             Defaults.queueOrderModeWeighted:
            return value
        default:
            return Defaults.queueOrderModeSequential
        }
    }
}
