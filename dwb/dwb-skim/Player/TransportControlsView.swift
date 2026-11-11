import Cocoa
import VLCKitSPM

/// Playback overlay used in both windowed and fullscreen modes: a `backingChrome` rail with a
/// top hairline, opaque under Increase Contrast.
final class TransportControlsView: NSView {
    weak var player: VLCMediaPlayer? { didSet { bottomRail.player = player } }
    weak var controller: PlayerWindowController? { didSet { bottomRail.controller = controller } }

    private let backingView = NSView()
    private let hairlineView = NSView()
    private let bottomRail = BottomRailView()
    private var hideWorkItem: DispatchWorkItem?
    private(set) var isFullscreenStyle = false
    private(set) var chromeVisibilityState = PlaybackChromeVisibilityState(
        autoHideEnabled: UserDefaults.standard.bool(forKey: SettingsWindowController.autoHideKey)
    )

    var chromeVisibilityDidChange: ((PlaybackChromeVisibilityState, Bool) -> Void)?
    var chromeVisibilityHoldProvider: (() -> Bool)?

    var isUsingUnifiedBottomRail: Bool { true }
    var isImageMode: Bool = false { didSet { bottomRail.isImageMode = isImageMode } }
    var imageModeElapsed: Double = 0 { didSet { bottomRail.imageModeElapsed = imageModeElapsed } }
    var imageModeDuration: Double = 0 { didSet { bottomRail.imageModeDuration = imageModeDuration } }
    var imageModeIsPlaying: Bool = true { didSet { bottomRail.imageModeIsPlaying = imageModeIsPlaying } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        backingView.wantsLayer = true
        addSubview(backingView)
        hairlineView.wantsLayer = true
        addSubview(hairlineView)
        applyBackingColors()

        bottomRail.scrubDidBegin = { [weak self] in
            self?.hideWorkItem?.cancel()
            self?.showChromeFromHost(animated: true)
        }
        bottomRail.scrubDidEnd = { [weak self] in self?.scheduleChromeHideFromHost() }
        addSubview(bottomRail)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(accessibilityOptionsChanged),
                                               name: DWBAccessibility.didChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(visibilitySettingsChanged),
                                               name: .transportVisibilityChanged,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(visibilitySettingsChanged),
                                               name: .autoHideSettingChanged,
                                               object: nil)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit {
        hideWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        backingView.frame = bounds
        hairlineView.frame = NSRect(x: 0, y: max(0, bounds.height - 1), width: bounds.width, height: 1)
        bottomRail.frame = bounds
    }

    private func applyBackingColors() {
        backingView.layer?.backgroundColor = DWBAccessibility.backingChrome.cgColor
        hairlineView.layer?.backgroundColor = DWBColor.hairline.cgColor
    }

    @objc private func accessibilityOptionsChanged() { applyBackingColors() }

    func update() {
        bottomRail.player = player
        bottomRail.controller = controller
        bottomRail.isImageMode = isImageMode
        bottomRail.imageModeElapsed = imageModeElapsed
        bottomRail.imageModeDuration = imageModeDuration
        bottomRail.imageModeIsPlaying = imageModeIsPlaying
        bottomRail.update()
    }

    func invalidateCachedDisplayState() { bottomRail.invalidateCachedDisplayState() }
    func notifySeek(to position: Float) { bottomRail.notifySeek(to: position) }

    func setFullscreenStyle(_ fullscreen: Bool) {
        isFullscreenStyle = fullscreen
    }

    /// Takes the faded-out overlay out of hit-testing, the key view loop, and the
    /// accessibility tree. Fading `alphaValue` alone leaves fully invisible
    /// controls clickable over the video and reachable by VoiceOver and Tab.
    private func retireChrome() {
        chromeVisibilityState.completeHide()
        isHidden = true
        chromeVisibilityDidChange?(chromeVisibilityState, false)
    }

    func applyVisibilitySettings() {
        let enabled = UserDefaults.standard.bool(forKey: SettingsWindowController.autoHideKey)
        chromeVisibilityState.setAutoHideEnabled(enabled)
        if enabled {
            scheduleChromeHideFromHost()
        } else {
            hideWorkItem?.cancel()
            showChromeFromHost(animated: false)
        }
    }

    func noteChromeActivity() {
        showChromeFromHost(animated: true)
        scheduleChromeHideFromHost()
    }

    func showChromeFromHost(animated: Bool) {
        hideWorkItem?.cancel()
        chromeVisibilityState.reveal()
        isHidden = false
        let shouldAnimate = animated && !DWBAccessibility.reduceMotion
        chromeVisibilityDidChange?(chromeVisibilityState, shouldAnimate)
        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DWBAccessibility.duration(DWBMotion.rail)
                animator().alphaValue = 1
            }
        } else {
            alphaValue = 1
        }
    }

    func scheduleChromeHideFromHost() {
        hideWorkItem?.cancel()
        guard UserDefaults.standard.bool(forKey: SettingsWindowController.autoHideKey) else { return }
        let configured = UserDefaults.standard.double(forKey: SettingsWindowController.chromeAutohideThresholdKey)
        let delay = configured > 0 ? configured : 3
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.chromeVisibilityHoldProvider?() == true {
                self.scheduleChromeHideFromHost()
                return
            }
            if self.isImageMode, !self.imageModeIsPlaying { return }
            if self.player?.isPlaying == false, !self.isImageMode { return }
            let reduceMotion = DWBAccessibility.reduceMotion
            self.chromeVisibilityState.requestHide(reduceMotion: reduceMotion)
            self.chromeVisibilityDidChange?(self.chromeVisibilityState, !reduceMotion)
            if !reduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = DWBAccessibility.duration(DWBMotion.rail)
                    self.animator().alphaValue = 0
                } completionHandler: {
                    // A re-show during the fade resets alpha to 1; only retire the
                    // overlay if it actually finished hiding.
                    if self.alphaValue == 0, self.chromeVisibilityState.phase == .fading {
                        self.retireChrome()
                    }
                }
            } else {
                self.alphaValue = 0
                self.retireChrome()
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @objc private func visibilitySettingsChanged() { applyVisibilitySettings() }
}
