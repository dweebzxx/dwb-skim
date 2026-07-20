import Cocoa
import VLCKitSPM

/// Thin translucent playback overlay used in both windowed and fullscreen modes.
final class TransportControlsView: NSView {
    weak var player: VLCMediaPlayer? { didSet { bottomRail.player = player } }
    weak var controller: PlayerWindowController? { didSet { bottomRail.controller = controller } }

    private let effectView = NSVisualEffectView()
    private let bottomRail = BottomRailView()
    private var hideWorkItem: DispatchWorkItem?
    private(set) var isFullscreenStyle = false

    var isUsingUnifiedBottomRail: Bool { true }
    var isImageMode: Bool = false { didSet { bottomRail.isImageMode = isImageMode } }
    var imageModeElapsed: Double = 0 { didSet { bottomRail.imageModeElapsed = imageModeElapsed } }
    var imageModeDuration: Double = 0 { didSet { bottomRail.imageModeDuration = imageModeDuration } }
    var imageModeIsPlaying: Bool = true { didSet { bottomRail.imageModeIsPlaying = imageModeIsPlaying } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.alphaValue = 0.46
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 6
        effectView.layer?.masksToBounds = true
        addSubview(effectView)

        bottomRail.scrubDidBegin = { [weak self] in
            self?.hideWorkItem?.cancel()
            self?.showChromeFromHost(animated: true)
        }
        bottomRail.scrubDidEnd = { [weak self] in self?.scheduleChromeHideFromHost() }
        addSubview(bottomRail)

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
        effectView.frame = bounds
        bottomRail.frame = bounds
    }

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
        effectView.alphaValue = fullscreen ? 0.38 : 0.46
    }

    func setBackdropActive(_ active: Bool) { effectView.state = active ? .active : .inactive }

    func applyVisibilitySettings() {
        if UserDefaults.standard.bool(forKey: SettingsWindowController.autoHideKey) {
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
        isHidden = false
        setBackdropActive(true)
        if animated, !UserDefaults.standard.bool(forKey: SettingsWindowController.chromeReducedMotionKey) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
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
            if self.isImageMode, !self.imageModeIsPlaying { return }
            if self.player?.isPlaying == false, !self.isImageMode { return }
            let animated = !UserDefaults.standard.bool(forKey: SettingsWindowController.chromeReducedMotionKey)
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    self.animator().alphaValue = 0
                } completionHandler: {
                    if self.alphaValue == 0 { self.setBackdropActive(false) }
                }
            } else {
                self.alphaValue = 0
                self.setBackdropActive(false)
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @objc private func visibilitySettingsChanged() { applyVisibilitySettings() }
}
