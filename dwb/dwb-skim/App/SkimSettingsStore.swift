import Foundation

extension Notification.Name {
    static let playbackSettingsChanged = Notification.Name("dwb.playbackSettingsChanged")
    static let skimPreviewSettingsChanged = Notification.Name("dwb.skimPreviewSettingsChanged")
    static let queueBehaviorSettingsChanged = Notification.Name("dwb.queueBehaviorSettingsChanged")
    static let skimPlusSettingsChanged = Notification.Name("dwb.skimPlusSettingsChanged")
}

struct SkimSettingsSnapshot: Equatable {
    let skimEnabled: Bool
    let imageDurationSeconds: Double
    let gifLoopCount: Int
    let videoAudioNormalizationEnabled: Bool
    let previewDurationMode: String
    let fixedDurationSeconds: Int
    let randomDurationRange: ClosedRange<Int>
    let startPositionMode: String
    let skipIntroSeconds: Int
    let queueOrderMode: QueueOrderMode
    let loopQueueEnabled: Bool
}

/// Shared persistent source for the inline strip, Settings, and every player
/// window. Views observe notifications and re-read snapshots; they never own a
/// second mutable copy of these values.
final class SkimSettingsStore {
    static let shared = SkimSettingsStore()

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter

    init(defaults: UserDefaults = .standard,
         notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    func snapshot() -> SkimSettingsSnapshot {
        let imageDuration = SettingsDefaultsRegistry.validatedImageDurationSeconds(
            defaults.double(forKey: SettingsDefaultsRegistry.Keys.imageDurationSeconds)
        )
        let gifLoops = SettingsDefaultsRegistry.validatedGIFLoopCount(
            defaults.integer(forKey: SettingsDefaultsRegistry.Keys.gifLoopCount)
        )
        let mode = SettingsDefaultsRegistry.validatedPreviewDurationMode(
            defaults.string(forKey: SettingsDefaultsRegistry.Keys.previewDurationMode)
                ?? SettingsDefaultsRegistry.Defaults.previewDurationMode
        )
        let fixed = SettingsDefaultsRegistry.validatedClipDurationSeconds(
            defaults.integer(forKey: SettingsDefaultsRegistry.Keys.clipDurationSeconds)
        )
        let range = SettingsDefaultsRegistry.validatedRandomPreviewDurationRange(
            minimum: defaults.integer(forKey: SettingsDefaultsRegistry.Keys.randomPreviewMinimumSeconds),
            maximum: defaults.integer(forKey: SettingsDefaultsRegistry.Keys.randomPreviewMaximumSeconds)
        )
        let start = SettingsDefaultsRegistry.validatedStartPositionMode(
            defaults.string(forKey: SettingsDefaultsRegistry.Keys.startPositionMode)
                ?? SettingsDefaultsRegistry.Defaults.startPositionMode
        )
        let skip = SettingsDefaultsRegistry.validatedSkipIntroSeconds(
            defaults.integer(forKey: SettingsDefaultsRegistry.Keys.skipIntroSeconds)
        )
        let queueRaw = SettingsDefaultsRegistry.validatedQueueOrderMode(
            defaults.string(forKey: SettingsDefaultsRegistry.Keys.queueOrderMode)
                ?? SettingsDefaultsRegistry.Defaults.queueOrderMode
        )
        let queueMode = QueueOrderMode(rawValue: queueRaw) ?? .sequential

        persistNormalized(imageDuration: imageDuration,
                          gifLoops: gifLoops,
                          mode: mode,
                          fixed: fixed,
                          range: range,
                          start: start,
                          skip: skip,
                          queueMode: queueMode)

        return SkimSettingsSnapshot(skimEnabled: defaults.bool(forKey: SettingsDefaultsRegistry.Keys.skimEnabled),
                                    imageDurationSeconds: imageDuration,
                                    gifLoopCount: gifLoops,
                                    videoAudioNormalizationEnabled: defaults.bool(forKey: SettingsDefaultsRegistry.Keys.videoAudioNormalizationEnabled),
                                    previewDurationMode: mode,
                                    fixedDurationSeconds: fixed,
                                    randomDurationRange: range,
                                    startPositionMode: start,
                                    skipIntroSeconds: skip,
                                    queueOrderMode: queueMode,
                                    loopQueueEnabled: defaults.bool(forKey: SettingsDefaultsRegistry.Keys.loopQueueEnabled))
    }

    func setPreviewDurationMode(_ value: String) {
        setPreviewValue(SettingsDefaultsRegistry.validatedPreviewDurationMode(value),
                        forKey: SettingsDefaultsRegistry.Keys.previewDurationMode)
    }

    func setSkimEnabled(_ enabled: Bool) {
        setPreviewValue(enabled, forKey: SettingsDefaultsRegistry.Keys.skimEnabled)
    }

    func setImageDurationSeconds(_ value: Double) {
        setPlaybackValue(SettingsDefaultsRegistry.validatedImageDurationSeconds(value),
                         forKey: SettingsDefaultsRegistry.Keys.imageDurationSeconds)
    }

    func setGIFLoopCount(_ value: Int) {
        setPlaybackValue(SettingsDefaultsRegistry.validatedGIFLoopCount(value),
                         forKey: SettingsDefaultsRegistry.Keys.gifLoopCount)
    }

    func setVideoAudioNormalizationEnabled(_ enabled: Bool) {
        setPlaybackValue(enabled,
                         forKey: SettingsDefaultsRegistry.Keys.videoAudioNormalizationEnabled)
    }

    func setFixedDurationSeconds(_ value: Int) {
        setPreviewValue(SettingsDefaultsRegistry.validatedClipDurationSeconds(value),
                        forKey: SettingsDefaultsRegistry.Keys.clipDurationSeconds)
    }

    func setRandomDurationRange(minimum: Int, maximum: Int) {
        let range = SettingsDefaultsRegistry.validatedRandomPreviewDurationRange(minimum: minimum, maximum: maximum)
        let oldMinimum = defaults.integer(forKey: SettingsDefaultsRegistry.Keys.randomPreviewMinimumSeconds)
        let oldMaximum = defaults.integer(forKey: SettingsDefaultsRegistry.Keys.randomPreviewMaximumSeconds)
        guard oldMinimum != range.lowerBound || oldMaximum != range.upperBound else { return }
        defaults.set(range.lowerBound, forKey: SettingsDefaultsRegistry.Keys.randomPreviewMinimumSeconds)
        defaults.set(range.upperBound, forKey: SettingsDefaultsRegistry.Keys.randomPreviewMaximumSeconds)
        notificationCenter.post(name: .skimPreviewSettingsChanged, object: self)
    }

    func setRandomMinimumSeconds(_ value: Int) {
        let current = snapshot().randomDurationRange
        setRandomDurationRange(minimum: value, maximum: current.upperBound)
    }

    func setRandomMaximumSeconds(_ value: Int) {
        let current = snapshot().randomDurationRange
        setRandomDurationRange(minimum: current.lowerBound, maximum: value)
    }

    func setStartPositionMode(_ value: String) {
        setPreviewValue(SettingsDefaultsRegistry.validatedStartPositionMode(value),
                        forKey: SettingsDefaultsRegistry.Keys.startPositionMode)
    }

    func setSkipIntroSeconds(_ value: Int) {
        setPreviewValue(SettingsDefaultsRegistry.validatedSkipIntroSeconds(value),
                        forKey: SettingsDefaultsRegistry.Keys.skipIntroSeconds)
    }

    func setQueueOrderMode(_ mode: QueueOrderMode) {
        let key = SettingsDefaultsRegistry.Keys.queueOrderMode
        guard defaults.string(forKey: key) != mode.rawValue else { return }
        defaults.set(mode.rawValue, forKey: key)
        notificationCenter.post(name: .queueBehaviorSettingsChanged, object: self)
    }

    func setLoopQueueEnabled(_ enabled: Bool) {
        let key = SettingsDefaultsRegistry.Keys.loopQueueEnabled
        guard defaults.bool(forKey: key) != enabled else { return }
        defaults.set(enabled, forKey: key)
        notificationCenter.post(name: .queueBehaviorSettingsChanged, object: self)
    }

    private func setPreviewValue<T: Equatable>(_ value: T, forKey key: String) {
        if let old = defaults.object(forKey: key) as? T, old == value { return }
        defaults.set(value, forKey: key)
        notificationCenter.post(name: .skimPreviewSettingsChanged, object: self)
    }

    private func setPlaybackValue<T: Equatable>(_ value: T, forKey key: String) {
        if let old = defaults.object(forKey: key) as? T, old == value { return }
        defaults.set(value, forKey: key)
        notificationCenter.post(name: .playbackSettingsChanged, object: self)
    }

    private func persistNormalized(imageDuration: Double,
                                   gifLoops: Int,
                                   mode: String,
                                   fixed: Int,
                                   range: ClosedRange<Int>,
                                   start: String,
                                   skip: Int,
                                   queueMode: QueueOrderMode) {
        defaults.set(imageDuration, forKey: SettingsDefaultsRegistry.Keys.imageDurationSeconds)
        defaults.set(gifLoops, forKey: SettingsDefaultsRegistry.Keys.gifLoopCount)
        defaults.set(mode, forKey: SettingsDefaultsRegistry.Keys.previewDurationMode)
        defaults.set(fixed, forKey: SettingsDefaultsRegistry.Keys.clipDurationSeconds)
        defaults.set(range.lowerBound, forKey: SettingsDefaultsRegistry.Keys.randomPreviewMinimumSeconds)
        defaults.set(range.upperBound, forKey: SettingsDefaultsRegistry.Keys.randomPreviewMaximumSeconds)
        defaults.set(start, forKey: SettingsDefaultsRegistry.Keys.startPositionMode)
        defaults.set(skip, forKey: SettingsDefaultsRegistry.Keys.skipIntroSeconds)
        defaults.set(queueMode.rawValue, forKey: SettingsDefaultsRegistry.Keys.queueOrderMode)
    }
}
