import Foundation

enum SettingsDefaultsRegistry {
    enum Keys {
        static let autoHideTransportWindowed = "autoHideTransportWindowed"
        static let persistedVolume = "lastEffectiveVolume"
        static let autoHideTitlebar = "autoHideTitlebar"
        static let completeVideoWindowMode = "completeVideoWindowMode"
        static let imageDurationSeconds = "imageDurationSeconds"
        static let gifLoopCount = "gifLoopCount"
        static let videoAudioNormalizationEnabled = "videoAudioNormalizationEnabled"
        static let acceptVideoMedia = "acceptVideoMedia"
        static let acceptImageMedia = "acceptImageMedia"
        static let acceptGIFMedia = "acceptGIFMedia"
        static let showTitleOverlay = "showTitleOverlay"
        static let customPrefixValue = "customPrefixValue"
        static let customPrefixSecondaryValue = "customPrefixValue2"
        static let debugConsoleEnabled = "debugConsoleEnabled"
        static let verboseAutoplayTrace = "verboseAutoplayTrace"
        static let chromeAutohideThreshold = "chromeAutohideThreshold"
        static let chromeReducedMotion = "chromeReducedMotion"
        static let queuePanelOpenAtLaunch = "queuePanelOpenAtLaunch"
        static let playerWindowOpacity = "playerWindowOpacity"
        static let clipDurationSeconds = "clipDurationSeconds"
        static let skimEnabled = "skimEnabled"
        static let previewDurationMode = "previewDurationMode"
        static let randomPreviewMinimumSeconds = "randomPreviewMinimumSeconds"
        static let randomPreviewMaximumSeconds = "randomPreviewMaximumSeconds"
        static let startPositionMode = "startPositionMode"
        static let skipIntroSeconds = "skipIntroSeconds"
        static let queueOrderMode = "queueOrderMode"
        static let loopQueueEnabled = "loopQueueEnabled"
        static let backgroundAudioBookmark = "backgroundAudioBookmark"
        static let backgroundAudioDisplayName = "backgroundAudioDisplayName"
        static let backgroundAudioMixMode = "backgroundAudioMixMode"
        static let backgroundAudioVolume = "backgroundAudioVolume"
    }

    enum Defaults {
        static let imageDurationSeconds = 3.0
        static let gifLoopCount = 1
        static let videoAudioNormalizationEnabled = false
        static let imageDurationMinimumSeconds = 0.25
        static let imageDurationMaximumSeconds = 3_600.0
        static let gifLoopCountMaximum = 1_000
        static let chromeAutohideThreshold = 3.0
        static let playerWindowOpacityMin = 0.35
        static let playerWindowOpacityMax = 1.0
        static let playerWindowOpacity = 1.0
        static let clipDurationSeconds = 10
        static let skimEnabled = true
        static let previewDurationModeFixed = "fixed"
        static let previewDurationModeRandom = "random"
        static let previewDurationMode = previewDurationModeFixed
        static let randomPreviewMinimumSeconds = 5
        static let randomPreviewMaximumSeconds = 15
        static let startPositionModeBeginning = "beginning"
        static let startPositionModeRandom = "random"
        static let startPositionMode = startPositionModeRandom
        static let skipIntroSeconds = 5
        static let queueOrderModeSequential = "sequential"
        static let queueOrderModeShuffle = "shuffle"
        static let queueOrderModeWeighted = "weighted"
        static let queueOrderMode = queueOrderModeSequential
        static let loopQueueEnabled = false
        static let backgroundAudioMixMode = "uploadedOnly"
        static let backgroundAudioVolume = 0.75
    }

    /// Removed legacy keys are deleted once during registration rather than
    /// retained as hidden compatibility behavior.
    static let obsoleteKeys: Set<String> = [
        "skipDurationSeconds",
        "deletePrefixRenameEnabled",
        "videoPageDButtonEnabled",
        "customPrefixQueuePageEnabled",
        "customPrefixVideoPageEnabled",
        "bottomRailShowXButton",
        "bottomRailShowShuffleButton",
        "bottomRailShowReplayButton",
        "bottomRailShowVolumeButton",
        "bottomRailShowBookmarkButton",
        "showStopButton",
        "showVolumeButton",
        "showShuffleButton",
        "showRepeatButton",
        "repeatOneEnabled",
        "replayEnabled",
    ]

    static func defaultValues(reduceMotionDefault: Bool) -> [String: Any] {
        [
            Keys.autoHideTransportWindowed: false,
            Keys.imageDurationSeconds: Defaults.imageDurationSeconds,
            Keys.gifLoopCount: Defaults.gifLoopCount,
            Keys.videoAudioNormalizationEnabled: Defaults.videoAudioNormalizationEnabled,
            Keys.acceptVideoMedia: true,
            Keys.acceptImageMedia: true,
            Keys.acceptGIFMedia: true,
            Keys.autoHideTitlebar: false,
            Keys.completeVideoWindowMode: false,
            Keys.showTitleOverlay: true,
            Keys.customPrefixValue: "",
            Keys.customPrefixSecondaryValue: "",
            Keys.debugConsoleEnabled: false,
            Keys.verboseAutoplayTrace: false,
            Keys.chromeAutohideThreshold: Defaults.chromeAutohideThreshold,
            Keys.chromeReducedMotion: reduceMotionDefault,
            Keys.queuePanelOpenAtLaunch: false,
            Keys.playerWindowOpacity: Defaults.playerWindowOpacity,
            Keys.clipDurationSeconds: Defaults.clipDurationSeconds,
            Keys.skimEnabled: Defaults.skimEnabled,
            Keys.previewDurationMode: Defaults.previewDurationMode,
            Keys.randomPreviewMinimumSeconds: Defaults.randomPreviewMinimumSeconds,
            Keys.randomPreviewMaximumSeconds: Defaults.randomPreviewMaximumSeconds,
            Keys.startPositionMode: Defaults.startPositionMode,
            Keys.skipIntroSeconds: Defaults.skipIntroSeconds,
            Keys.queueOrderMode: Defaults.queueOrderMode,
            Keys.loopQueueEnabled: Defaults.loopQueueEnabled,
            Keys.backgroundAudioMixMode: Defaults.backgroundAudioMixMode,
            Keys.backgroundAudioVolume: Defaults.backgroundAudioVolume,
        ]
    }

    static func register(defaults: UserDefaults = .standard, reduceMotionDefault: Bool) {
        defaults.register(defaults: defaultValues(reduceMotionDefault: reduceMotionDefault))
        obsoleteKeys.forEach(defaults.removeObject(forKey:))
    }

    static func validatedClipDurationSeconds(_ value: Int) -> Int {
        max(0, value)
    }

    static func validatedImageDurationSeconds(_ value: Double) -> Double {
        guard value.isFinite else { return Defaults.imageDurationSeconds }
        return min(Defaults.imageDurationMaximumSeconds,
                   max(Defaults.imageDurationMinimumSeconds, value))
    }

    static func validatedGIFLoopCount(_ value: Int) -> Int {
        min(Defaults.gifLoopCountMaximum, max(1, value))
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
        let minimum = validatedRandomPreviewMinimumSeconds(minimum)
        return minimum...validatedRandomPreviewMaximumSeconds(minimum: minimum, maximum: maximum)
    }

    static func validatedSkipIntroSeconds(_ value: Int) -> Int {
        max(0, value)
    }

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

    static func validatedBackgroundAudioVolume(_ value: Double) -> Double {
        guard value.isFinite else { return Defaults.backgroundAudioVolume }
        return min(1, max(0, value))
    }
}
