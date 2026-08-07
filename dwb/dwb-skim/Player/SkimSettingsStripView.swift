import Cocoa

/// Compact, persistent skim controls shared by every player window.
final class SkimSettingsStripView: NSVisualEffectView, NSTextFieldDelegate {
    var onCollapse: (() -> Void)?
    private let store: SkimSettingsStore
    private let durationMode = NSSegmentedControl(labels: ["Fixed", "Random"], trackingMode: .selectOne, target: nil, action: nil)
    private let fixedDuration = NSTextField()
    private let randomMinimum = NSTextField()
    private let randomMaximum = NSTextField()
    private let randomRangeSeparator = NSTextField(labelWithString: "-")
    private let startPosition = NSSegmentedControl(labels: ["Beginning", "Random"], trackingMode: .selectOne, target: nil, action: nil)
    private let skipIntro = NSTextField()
    private let imageDuration = NSTextField()
    private let imageDurationStepper = NSStepper()
    private let gifLoops = NSTextField()
    private let gifLoopsStepper = NSStepper()
    private let queueOrder = NSPopUpButton()
    private let loopQueue = NSSwitch()
    private let settingsButton = NSButton()
    private let collapseButton = NSButton()
    private var isSynchronizing = false

    init(store: SkimSettingsStore = .shared) {
        self.store = store
        super.init(frame: .zero)
        configure()
        syncFromStore()
        for name in [Notification.Name.skimPreviewSettingsChanged,
                     .queueBehaviorSettingsChanged,
                     .playbackSettingsChanged] {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(settingsDidChange),
                                                   name: name,
                                                   object: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func configure() {
        material = .headerView
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.borderWidth = 1

        configureSegmented(durationMode, action: #selector(durationModeChanged(_:)))
        configureSegmented(startPosition, action: #selector(startPositionChanged(_:)))
        durationMode.setAccessibilityLabel("Clip duration mode")
        startPosition.setAccessibilityLabel("Start position")
        durationMode.identifier = NSUserInterfaceItemIdentifier(SkimControlAccessibility.clipDurationIdentifier)
        startPosition.identifier = NSUserInterfaceItemIdentifier(SkimControlAccessibility.startPositionIdentifier)

        [fixedDuration, randomMinimum, randomMaximum, skipIntro].forEach {
            configureNumberField($0, allowsFloats: false, minimum: 0, width: 34)
        }
        fixedDuration.setAccessibilityLabel("Fixed clip duration in seconds")
        randomMinimum.setAccessibilityLabel("Minimum random clip duration in seconds")
        randomMaximum.setAccessibilityLabel("Maximum random clip duration in seconds")
        skipIntro.setAccessibilityLabel("Skip intro in seconds")
        configureNumberField(imageDuration,
                             allowsFloats: true,
                             minimum: SettingsDefaultsRegistry.Defaults.imageDurationMinimumSeconds,
                             maximum: SettingsDefaultsRegistry.Defaults.imageDurationMaximumSeconds,
                             width: 44)
        imageDuration.setAccessibilityLabel("Image duration in seconds")
        configureNumberField(gifLoops,
                             allowsFloats: false,
                             minimum: 1,
                             maximum: Double(SettingsDefaultsRegistry.Defaults.gifLoopCountMaximum),
                             width: 38)
        gifLoops.setAccessibilityLabel("GIF loop count")
        configureStepper(imageDurationStepper,
                         minimum: SettingsDefaultsRegistry.Defaults.imageDurationMinimumSeconds,
                         maximum: SettingsDefaultsRegistry.Defaults.imageDurationMaximumSeconds,
                         increment: 0.25,
                         action: #selector(imageDurationStepperChanged(_:)))
        imageDurationStepper.setAccessibilityLabel("Adjust image duration")
        configureStepper(gifLoopsStepper,
                         minimum: 1,
                         maximum: Double(SettingsDefaultsRegistry.Defaults.gifLoopCountMaximum),
                         increment: 1,
                         action: #selector(gifLoopsStepperChanged(_:)))
        gifLoopsStepper.setAccessibilityLabel("Adjust GIF loop count")

        QueueOrderMode.allCases.forEach { mode in
            queueOrder.addItem(withTitle: mode.rawValue.capitalized)
            queueOrder.lastItem?.representedObject = mode.rawValue
        }
        queueOrder.controlSize = .small
        queueOrder.target = self
        queueOrder.action = #selector(queueOrderChanged(_:))
        queueOrder.setAccessibilityLabel("Queue Order")

        loopQueue.controlSize = .small
        loopQueue.target = self
        loopQueue.action = #selector(loopQueueChanged(_:))
        loopQueue.setAccessibilityLabel("Loop Queue")
        loopQueue.toolTip = "Loop queue"

        settingsButton.isBordered = false
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.imageScaling = .scaleProportionallyDown
        settingsButton.contentTintColor = .labelColor
        settingsButton.target = self
        settingsButton.action = #selector(openSettings(_:))
        settingsButton.toolTip = "Open Settings"
        settingsButton.setAccessibilityLabel("Open Settings")
        settingsButton.widthAnchor.constraint(equalToConstant: 28).isActive = true

        collapseButton.isBordered = false
        collapseButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Hide Skim controls")
        collapseButton.imageScaling = .scaleProportionallyDown
        collapseButton.contentTintColor = .secondaryLabelColor
        collapseButton.target = self
        collapseButton.action = #selector(collapseTapped(_:))
        collapseButton.toolTip = "Hide Skim controls"
        collapseButton.setAccessibilityLabel("Hide Skim controls")
        collapseButton.widthAnchor.constraint(equalToConstant: 24).isActive = true

        randomRangeSeparator.font = .systemFont(ofSize: 10)
        randomRangeSeparator.textColor = .secondaryLabelColor
        randomRangeSeparator.setAccessibilityElement(false)

        let durationValues = horizontal(durationMode,
                                        fixedDuration,
                                        randomMinimum,
                                        randomRangeSeparator,
                                        randomMaximum,
                                        suffixLabel("s"))
        let groups: [NSView] = [
            group("Clip duration", durationValues),
            group("Start position", startPosition),
            group("Skip intro", horizontal(skipIntro, suffixLabel("s"))),
            group("Image duration", horizontal(imageDuration, imageDurationStepper, suffixLabel("s"))),
            group("GIF loops", horizontal(gifLoops, gifLoopsStepper)),
            group("Queue order", queueOrder),
            group("Loop queue", loopQueue),
            group("Settings", horizontal(settingsButton, collapseButton)),
        ]
        let stack = NSStackView(views: groups)
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.distribution = .equalSpacing
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 14, bottom: 6, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func configureSegmented(_ control: NSSegmentedControl, action: Selector) {
        control.target = self
        control.action = action
        control.segmentStyle = .smallSquare
        control.controlSize = .small
    }

    private func configureNumberField(_ field: NSTextField,
                                      allowsFloats: Bool,
                                      minimum: Double,
                                      maximum: Double? = nil,
                                      width: CGFloat) {
        field.delegate = self
        field.alignment = .right
        field.controlSize = .small
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = allowsFloats
        formatter.minimum = NSNumber(value: minimum)
        if let maximum { formatter.maximum = NSNumber(value: maximum) }
        formatter.maximumFractionDigits = allowsFloats ? 2 : 0
        formatter.minimumFractionDigits = 0
        field.formatter = formatter
    }

    private func configureStepper(_ stepper: NSStepper,
                                  minimum: Double,
                                  maximum: Double,
                                  increment: Double,
                                  action: Selector) {
        stepper.controlSize = .small
        stepper.minValue = minimum
        stepper.maxValue = maximum
        stepper.increment = increment
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = action
    }

    private func group(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.setAccessibilityElement(false)
        let stack = NSStackView(views: [label, control])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        return stack
    }

    private func horizontal(_ views: NSView...) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 3
        return stack
    }

    private func suffixLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        return label
    }

    @objc private func settingsDidChange() { syncFromStore() }

    private func syncFromStore() {
        isSynchronizing = true
        defer { isSynchronizing = false }
        let settings = store.snapshot()
        applySkimEnabled(settings.skimEnabled)
        let random = settings.previewDurationMode == SettingsDefaultsRegistry.Defaults.previewDurationModeRandom
        durationMode.selectedSegment = random ? 1 : 0
        fixedDuration.stringValue = String(settings.fixedDurationSeconds)
        randomMinimum.stringValue = String(settings.randomDurationRange.lowerBound)
        randomMaximum.stringValue = String(settings.randomDurationRange.upperBound)
        fixedDuration.isHidden = random
        randomMinimum.isHidden = !random
        randomMaximum.isHidden = !random
        randomRangeSeparator.isHidden = !random
        startPosition.selectedSegment = settings.startPositionMode == SettingsDefaultsRegistry.Defaults.startPositionModeBeginning ? 0 : 1
        skipIntro.stringValue = String(settings.skipIntroSeconds)
        imageDuration.doubleValue = settings.imageDurationSeconds
        imageDurationStepper.doubleValue = settings.imageDurationSeconds
        gifLoops.integerValue = settings.gifLoopCount
        gifLoopsStepper.integerValue = settings.gifLoopCount
        queueOrder.selectItem(withTitle: settings.queueOrderMode.rawValue.capitalized)
        loopQueue.state = settings.loopQueueEnabled ? .on : .off
    }

    private func applySkimEnabled(_ enabled: Bool) {
        let durationControls: [NSControl] = [durationMode, fixedDuration, randomMinimum, randomMaximum]
        durationControls.forEach { $0.isEnabled = enabled }
        startPosition.isEnabled = enabled
        durationControls.forEach { $0.alphaValue = enabled ? 1 : 0.42 }
        startPosition.alphaValue = enabled ? 1 : 0.42
        durationMode.setAccessibilityHelp(enabled
            ? "Choose fixed or random Skim clip duration."
            : "Unavailable while Skim is off.")
        startPosition.setAccessibilityHelp(enabled
            ? "Choose the Skim playback start position."
            : "Unavailable while Skim is off.")
    }

    @objc private func durationModeChanged(_ sender: NSSegmentedControl) {
        guard !isSynchronizing else { return }
        store.setPreviewDurationMode(sender.selectedSegment == 0
            ? SettingsDefaultsRegistry.Defaults.previewDurationModeFixed
            : SettingsDefaultsRegistry.Defaults.previewDurationModeRandom)
    }

    @objc private func startPositionChanged(_ sender: NSSegmentedControl) {
        guard !isSynchronizing else { return }
        store.setStartPositionMode(sender.selectedSegment == 0
            ? SettingsDefaultsRegistry.Defaults.startPositionModeBeginning
            : SettingsDefaultsRegistry.Defaults.startPositionModeRandom)
    }

    @objc private func imageDurationStepperChanged(_ sender: NSStepper) {
        guard !isSynchronizing else { return }
        store.setImageDurationSeconds(sender.doubleValue)
    }

    @objc private func gifLoopsStepperChanged(_ sender: NSStepper) {
        guard !isSynchronizing else { return }
        store.setGIFLoopCount(sender.integerValue)
    }

    @objc private func queueOrderChanged(_ sender: NSPopUpButton) {
        guard !isSynchronizing,
              let raw = sender.selectedItem?.representedObject as? String,
              let mode = QueueOrderMode(rawValue: raw) else { return }
        store.setQueueOrderMode(mode)
    }

    @objc private func loopQueueChanged(_ sender: NSSwitch) {
        guard !isSynchronizing else { return }
        store.setLoopQueueEnabled(sender.state == .on)
    }

    @objc private func openSettings(_ sender: NSButton) {
        SettingsWindowController.shared.openSettings()
    }

    @objc private func collapseTapped(_ sender: NSButton) { onCollapse?() }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard !isSynchronizing, let field = notification.object as? NSTextField else { return }
        switch field {
        case fixedDuration: store.setFixedDurationSeconds(field.integerValue)
        case randomMinimum: store.setRandomMinimumSeconds(field.integerValue)
        case randomMaximum: store.setRandomMaximumSeconds(field.integerValue)
        case skipIntro: store.setSkipIntroSeconds(field.integerValue)
        case imageDuration: store.setImageDurationSeconds(field.doubleValue)
        case gifLoops: store.setGIFLoopCount(field.integerValue)
        default: return
        }
        syncFromStore()
    }
}
