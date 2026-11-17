import Cocoa

/// Compact, persistent skim controls shared by every player window: an opaque `canvas` strip with a
/// 1 pt `gridLine` bottom edge. The row never wraps or scrolls. The collapse chevron sits in a fixed
/// trailing slot; groups that do not fit move, in order, into an overflow popover (`SkimStripLayoutPlan`).
final class SkimSettingsStripView: NSView, NSTextFieldDelegate {
    private enum Metrics {
        static let leadingInset = SkimStripLayoutPlan.Metrics.leadingInset
        static let trailingInset = SkimStripLayoutPlan.Metrics.trailingInset
        static let groupGap = SkimStripLayoutPlan.Metrics.groupGap
        static let separatorInset: CGFloat = 10
        static let labelToControl: CGFloat = 4
        static let controlGap: CGFloat = 6
        static let smallControl: CGFloat = 20
        /// `DWBSegmentedControl` small: 20 pt segments plus its 2 pt frame on each side.
        static let segmentedControl: CGFloat = 24
        static let numberField: CGFloat = 44
        static let numberFieldWithStepper: CGFloat = 58
        static let popUp: CGFloat = 104
        static let collapseButton = SkimStripLayoutPlan.Metrics.collapseControl
        static let overflowButton = SkimStripLayoutPlan.Metrics.overflowControl
    }

    /// One strip group, in row order. `divider` is the rule drawn before it when it starts a cluster.
    private struct StripGroup {
        let setting: SkimStripSetting
        let view: NSView
        let divider: NSView?
    }

    /// A control whose tooltip and accessibility help carry the saved value of its setting.
    private struct DescribedControl {
        let control: NSControl
        let setting: SkimStripSetting
        let hint: () -> String?
    }

    var onCollapse: (() -> Void)?
    /// Called after a commit made in this strip changed a stored setting. Never called for store
    /// notifications that came from Settings or another window.
    var onSettingCommitted: ((SkimStripConfirmation) -> Void)?
    private let store: SkimSettingsStore
    private let durationMode = SkimSettingsStripView.makeSegmented(["Fixed", "Random"])
    private let fixedDuration = SkimNumberField()
    private let randomMinimum = SkimNumberField()
    private let randomMaximum = SkimNumberField()
    private let randomRangeSeparator = NSTextField(labelWithString: "-")
    private let startPosition = SkimSettingsStripView.makeSegmented(["Beginning", "Random"])
    private let skipIntro = SkimNumberField()
    private let imageDuration = SkimNumberField()
    private let imageDurationStepper = NSStepper()
    private let gifLoops = SkimNumberField()
    private let gifLoopsStepper = NSStepper()
    private let queueOrder = NSPopUpButton()
    private let loopQueue = NSSwitch()
    private let progressiveRandomSkim = NSSwitch()
    private let collapseButton = NSButton()
    private let overflowButton = RailButton()
    private var overflowPopover: DWBPopover!
    private let overflowStack = NSStackView()
    private let rowStack = NSStackView()
    private let bottomEdge = NSView()
    private var groups: [StripGroup] = []
    private var describedControls: [DescribedControl] = []
    private var appliedPlan: SkimStripLayoutPlan?
    private var groupLabels: [(setting: SkimStripSetting, label: NSTextField)] = []
    private var imageSuffix: NSView?
    private var activity = SkimStripActivity(skimEnabled: true, acceptsImages: true, acceptsGIFs: true)
    private var isSynchronizing = false

    init(store: SkimSettingsStore = .shared) {
        self.store = store
        super.init(frame: .zero)
        configure()
        syncFromStore()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(accessibilityOptionsChanged),
                                               name: DWBAccessibility.didChange,
                                               object: nil)
        for name in [Notification.Name.skimPreviewSettingsChanged,
                     .queueBehaviorSettingsChanged,
                     .playbackSettingsChanged,
                     .acceptedMediaTypesChanged] {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(settingsDidChange),
                                                   name: name,
                                                   object: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func configure() {
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = DWBColor.canvas.cgColor
        bottomEdge.wantsLayer = true
        bottomEdge.layer?.backgroundColor = StripColor.line.cgColor
        bottomEdge.translatesAutoresizingMaskIntoConstraints = false

        configureSegmented(durationMode, action: #selector(durationModeChanged(_:)))
        configureSegmented(startPosition, action: #selector(startPositionChanged(_:)))
        durationMode.setAccessibilityLabel("Clip duration mode")
        startPosition.setAccessibilityLabel("Start position")
        durationMode.identifier = NSUserInterfaceItemIdentifier(SkimControlAccessibility.clipDurationIdentifier)
        startPosition.identifier = NSUserInterfaceItemIdentifier(SkimControlAccessibility.startPositionIdentifier)

        [fixedDuration, randomMinimum, randomMaximum, skipIntro].forEach {
            configureNumberField($0, allowsFloats: false, minimum: 0, width: Metrics.numberField)
        }
        fixedDuration.setAccessibilityLabel("Fixed clip duration in seconds")
        randomMinimum.setAccessibilityLabel("Minimum random clip duration in seconds")
        randomMaximum.setAccessibilityLabel("Maximum random clip duration in seconds")
        skipIntro.setAccessibilityLabel("Skip intro in seconds")
        configureNumberField(imageDuration,
                             allowsFloats: true,
                             minimum: SettingsDefaultsRegistry.Defaults.imageDurationMinimumSeconds,
                             maximum: SettingsDefaultsRegistry.Defaults.imageDurationMaximumSeconds,
                             width: Metrics.numberField)
        imageDuration.setAccessibilityLabel("Image duration in seconds")
        configureNumberField(gifLoops,
                             allowsFloats: false,
                             minimum: 1,
                             maximum: Double(SettingsDefaultsRegistry.Defaults.gifLoopCountMaximum),
                             width: Metrics.numberField)
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
        queueOrder.widthAnchor.constraint(equalToConstant: Metrics.popUp).isActive = true
        queueOrder.heightAnchor.constraint(equalToConstant: Metrics.smallControl).isActive = true
        queueOrder.target = self
        queueOrder.action = #selector(queueOrderChanged(_:))
        queueOrder.setAccessibilityLabel("Queue Order")

        loopQueue.controlSize = .small
        loopQueue.target = self
        loopQueue.action = #selector(loopQueueChanged(_:))
        loopQueue.setAccessibilityLabel("Loop Queue")

        progressiveRandomSkim.controlSize = .small
        progressiveRandomSkim.target = self
        progressiveRandomSkim.action = #selector(progressiveRandomSkimChanged(_:))
        progressiveRandomSkim.setAccessibilityLabel("Progressive Random Skim")

        collapseButton.isBordered = false
        collapseButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Hide Skim controls")
        collapseButton.imageScaling = .scaleProportionallyDown
        collapseButton.contentTintColor = StripColor.supportingText
        collapseButton.target = self
        collapseButton.action = #selector(collapseTapped(_:))
        collapseButton.toolTip = "Hide Skim controls"
        collapseButton.setAccessibilityLabel("Hide Skim controls")
        collapseButton.image = collapseButton.image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        collapseButton.widthAnchor.constraint(equalToConstant: Metrics.collapseButton).isActive = true
        collapseButton.heightAnchor.constraint(equalToConstant: Metrics.collapseButton).isActive = true

        randomRangeSeparator.font = .systemFont(ofSize: 10)
        randomRangeSeparator.textColor = StripColor.supportingText
        randomRangeSeparator.setAccessibilityElement(false)

        configureOverflowButton()

        let durationValues = horizontal(durationMode,
                                        fixedDuration,
                                        randomMinimum,
                                        randomRangeSeparator,
                                        randomMaximum,
                                        suffixLabel("s"))
        let imageUnit = suffixLabel("s")
        imageSuffix = imageUnit
        groups = [
            StripGroup(setting: .clipDuration, view: group("Clip duration", durationValues, setting: .clipDuration), divider: nil),
            StripGroup(setting: .startPosition, view: group("Start position", startPosition, setting: .startPosition), divider: nil),
            StripGroup(setting: .skipIntro, view: group("Skip intro", horizontal(skipIntro, suffixLabel("s")), setting: .skipIntro), divider: nil),
            StripGroup(setting: .imageDuration,
                       view: group("Image duration", horizontal(numberField(imageDuration, stepper: imageDurationStepper), imageUnit), setting: .imageDuration),
                       divider: divider()),
            StripGroup(setting: .gifLoops, view: group("GIF loops", numberField(gifLoops, stepper: gifLoopsStepper), setting: .gifLoops), divider: nil),
            StripGroup(setting: .queueOrder, view: group("Queue order", queueOrder, setting: .queueOrder), divider: divider()),
            StripGroup(setting: .loopQueue, view: group("Loop queue", loopQueue, setting: .loopQueue), divider: nil),
            StripGroup(setting: .progressiveSkim, view: group("Progressive skim", progressiveRandomSkim, setting: .progressiveSkim), divider: nil),
        ]
        describedControls = [
            DescribedControl(control: durationMode, setting: .clipDuration) { [unowned self] in
                self.activity.inactiveReason(.clipDuration) ?? "Choose fixed or random Skim clip duration."
            },
            DescribedControl(control: fixedDuration, setting: .clipDuration) { [unowned self] in
                self.activity.inactiveReason(.clipDuration) ?? "Controls Progressive segment length in Fixed mode."
            },
            DescribedControl(control: randomMinimum, setting: .clipDuration) { [unowned self] in
                self.activity.inactiveReason(.clipDuration) ?? "Bounds Progressive segment length in Random mode."
            },
            DescribedControl(control: randomMaximum, setting: .clipDuration) { [unowned self] in
                self.activity.inactiveReason(.clipDuration) ?? "Bounds Progressive segment length in Random mode."
            },
            DescribedControl(control: startPosition, setting: .startPosition) { [unowned self] in
                self.activity.inactiveReason(.startPosition) ?? "Choose the Skim playback start position."
            },
            DescribedControl(control: skipIntro, setting: .skipIntro) { nil },
            DescribedControl(control: imageDuration, setting: .imageDuration) { [unowned self] in
                self.activity.inactiveReason(.imageDuration)
            },
            DescribedControl(control: imageDurationStepper, setting: .imageDuration) { [unowned self] in
                self.activity.inactiveReason(.imageDuration)
            },
            DescribedControl(control: gifLoops, setting: .gifLoops) { [unowned self] in
                self.activity.inactiveReason(.gifLoops)
            },
            DescribedControl(control: gifLoopsStepper, setting: .gifLoops) { [unowned self] in
                self.activity.inactiveReason(.gifLoops)
            },
            DescribedControl(control: queueOrder, setting: .queueOrder) { nil },
            DescribedControl(control: loopQueue, setting: .loopQueue) { nil },
            DescribedControl(control: progressiveRandomSkim, setting: .progressiveSkim) { nil },
        ]

        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.distribution = .fill
        rowStack.spacing = Metrics.groupGap
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        for (index, entry) in groups.enumerated() {
            if let divider = entry.divider, index > 0 { rowStack.addArrangedSubview(divider) }
            rowStack.addArrangedSubview(entry.view)
        }

        overflowStack.orientation = .vertical
        overflowStack.alignment = .leading
        overflowStack.spacing = DWBPopoverGeometry.groupGap
        overflowStack.edgeInsets = NSEdgeInsets(top: DWBPopoverGeometry.inset, left: DWBPopoverGeometry.inset,
                                                bottom: DWBPopoverGeometry.inset, right: DWBPopoverGeometry.inset)
        // The design system's popover: a transient `surfaceElevated` panel with an arrow to the button.
        overflowPopover = DWBPopover(content: overflowStack, accessibilityName: "More Skim settings")
        overflowPopover.onClose = { [weak self] in self?.overflowButton.isToggled = false }

        // The chevron and, when needed, the overflow button live in a trailing slot outside the
        // row, so no width the groups need can push them past the visible right edge.
        let trailingSlot = NSStackView(views: [overflowButton, collapseButton])
        trailingSlot.orientation = .horizontal
        trailingSlot.alignment = .centerY
        trailingSlot.spacing = SkimStripLayoutPlan.Metrics.trailingControlGap
        trailingSlot.translatesAutoresizingMaskIntoConstraints = false
        overflowButton.isHidden = true

        addSubview(rowStack)
        addSubview(trailingSlot)
        addSubview(bottomEdge)
        clipsToBounds = true
        // `SkimStripLayoutPlan` keeps the row inside the room before the trailing slot; this
        // constraint is only a backstop, so it never breaks the controls' fixed widths.
        let rowLimit = rowStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingSlot.leadingAnchor,
                                                          constant: -SkimStripLayoutPlan.Metrics.trailingGap)
        rowLimit.priority = .defaultHigh
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.leadingInset),
            rowStack.topAnchor.constraint(equalTo: topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            rowLimit,
            trailingSlot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.trailingInset),
            trailingSlot.centerYAnchor.constraint(equalTo: centerYAnchor),
            bottomEdge.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomEdge.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomEdge.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomEdge.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func configureOverflowButton() {
        // A 24 pt circle with the rail button states: hover, pressed, and open (toggled).
        overflowButton.railStyle = .popoverTrigger
        overflowButton.configureSymbol("ellipsis", accessibilityLabel: "More Skim settings", help: "More Skim settings")
        overflowButton.target = self
        overflowButton.action = #selector(overflowTapped(_:))
        overflowButton.widthAnchor.constraint(equalToConstant: Metrics.overflowButton).isActive = true
        overflowButton.heightAnchor.constraint(equalToConstant: Metrics.overflowButton).isActive = true
    }

    // MARK: - Responsive row

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateOverflowLayout()
    }

    /// Re-plans the row for the strip's current width. Only moves groups when the plan changes.
    private func updateOverflowLayout() {
        guard !groups.isEmpty, bounds.width > 0 else { return }
        let advances = groups.enumerated().map { index, entry in
            SkimStripLayoutPlan.advance(groupWidth: ceil(entry.view.fittingSize.width),
                                        leadingDivider: entry.divider != nil,
                                        isFirst: index == 0)
        }
        let plan = SkimStripLayoutPlan.make(advances: advances, stripWidth: bounds.width)
        guard plan != appliedPlan else {
            applySpacing(plan: plan, advances: advances)
            return
        }
        appliedPlan = plan
        if overflowPopover.isShown { overflowPopover.close() }
        for entry in groups {
            entry.divider?.removeFromSuperview()
            entry.view.removeFromSuperview()
        }
        for (index, entry) in groups.enumerated() {
            if index < plan.visibleCount {
                if let divider = entry.divider, index > 0 { rowStack.addArrangedSubview(divider) }
                rowStack.addArrangedSubview(entry.view)
            } else {
                overflowStack.addArrangedSubview(entry.view)
            }
        }
        applySpacing(plan: plan, advances: advances)
        overflowButton.isHidden = !plan.hasOverflow
        let names = groups[plan.visibleCount...].map { $0.setting.name }.joined(separator: ", ")
        overflowButton.toolTip = plan.hasOverflow ? "More Skim settings: \(names)" : nil
        overflowButton.setAccessibilityHelp(plan.hasOverflow ? "Opens \(names)." : nil)
    }

    /// Spreads the visible groups across the strip: the spare width is shared equally between the
    /// groups, and a divider sits in the middle of its gap (design system 9.8).
    private func applySpacing(plan: SkimStripLayoutPlan, advances: [CGFloat]) {
        let share = plan.spareShare(advances: advances, stripWidth: bounds.width)
        for (index, entry) in groups.enumerated() where index < plan.visibleCount {
            if let divider = entry.divider, index > 0 {
                rowStack.setCustomSpacing(Metrics.groupGap + share / 2, after: divider)
            }
            let followsWithDivider = index + 1 < groups.count && groups[index + 1].divider != nil
            let visibleNext = index + 1 < plan.visibleCount
            if !visibleNext {
                rowStack.setCustomSpacing(NSStackView.useDefaultSpacing, after: entry.view)
            } else if followsWithDivider {
                rowStack.setCustomSpacing(Metrics.groupGap + share / 2, after: entry.view)
            } else {
                rowStack.setCustomSpacing(Metrics.groupGap + share, after: entry.view)
            }
        }
    }

    @objc private func overflowTapped(_ sender: NSButton) {
        if overflowPopover.isShown {
            overflowPopover.close()
            return
        }
        overflowButton.isToggled = true
        overflowPopover.show(relativeTo: sender)
    }

    @objc private func accessibilityOptionsChanged() {
        bottomEdge.layer?.backgroundColor = StripColor.line.cgColor
        collapseButton.contentTintColor = StripColor.supportingText
        randomRangeSeparator.textColor = StripColor.supportingText
        applyLabelColors()
    }

    /// The design system's segmented control at its small size: 20 pt segments in a 2 pt frame.
    private static func makeSegmented(_ labels: [String]) -> DWBSegmentedControl {
        let control = DWBSegmentedControl(size: .small)
        control.segmentCount = labels.count
        for (index, label) in labels.enumerated() { control.setLabel(label, forSegment: index) }
        return control
    }

    private func configureSegmented(_ control: DWBSegmentedControl, action: Selector) {
        control.target = self
        control.action = action
    }

    private func configureNumberField(_ field: SkimNumberField,
                                      allowsFloats: Bool,
                                      minimum: Double,
                                      maximum: Double? = nil,
                                      width: CGFloat) {
        field.delegate = self
        field.alignment = .right
        field.controlSize = .small
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        field.heightAnchor.constraint(equalToConstant: Metrics.smallControl).isActive = true
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

    private func group(_ title: String, _ control: NSView, setting: SkimStripSetting) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = StripColor.groupLabel
        label.setAccessibilityElement(false)
        groupLabels.append((setting, label))
        // Every control sits in a slot as tall as the segmented control (20 pt segments in a 2 pt
        // frame), so every group has the same height and all the labels share one line.
        let slot = NSStackView(views: [control])
        slot.orientation = .horizontal
        slot.alignment = .centerY
        slot.spacing = 0
        slot.heightAnchor.constraint(equalToConstant: Metrics.segmentedControl).isActive = true
        let stack = NSStackView(views: [label, slot])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Metrics.labelToControl
        return stack
    }

    private func horizontal(_ views: NSView...) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Metrics.controlGap
        return stack
    }

    /// A number field with its stepper attached: 58 pt wide in all (44 pt field plus stepper).
    private func numberField(_ field: SkimNumberField, stepper: NSStepper) -> NSView {
        let stack = NSStackView(views: [field, stepper])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        stack.widthAnchor.constraint(equalToConstant: Metrics.numberFieldWithStepper).isActive = true
        return stack
    }

    private func suffixLabel(_ text: String) -> NSTextField {
        // `DWBLabel` follows Increase Contrast live.
        DWBLabel(text, size: 11, tone: .tertiary)
    }

    private func divider() -> NSView {
        let separator = StripSeparator()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: SkimStripLayoutPlan.Metrics.dividerWidth).isActive = true
        separator.heightAnchor.constraint(equalToConstant: DWBMetrics.skimStripHeight - 2 * Metrics.separatorInset).isActive = true
        return separator
    }

    private func applyLabelColors() {
        for entry in groupLabels {
            entry.label.textColor = activity.isActive(entry.setting) ? StripColor.groupLabel : DWBColor.textDisabled
        }
    }

    @objc private func settingsDidChange() { syncFromStore() }

    private func syncFromStore() {
        isSynchronizing = true
        defer { isSynchronizing = false }
        let settings = store.snapshot()
        applyActivity(SkimStripActivity(skimEnabled: settings.skimEnabled,
                                        acceptsImages: SettingsWindowController.acceptsImageMedia(),
                                        acceptsGIFs: SettingsWindowController.acceptsGIFMedia()))
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
        progressiveRandomSkim.state = settings.progressiveRandomSkimEnabled ? .on : .off
        applySavedDescriptions(settings)
        updateOverflowLayout()
    }

    /// Tooltips and accessibility help carry the saved value, read from the same snapshot as the controls.
    private func applySavedDescriptions(_ settings: SkimSettingsSnapshot) {
        for entry in describedControls {
            let lead = entry.hint() ?? entry.setting.name
            let saved = entry.setting.savedDescription(in: settings)
            let text = lead.hasSuffix(".") ? "\(lead) \(saved)" : "\(lead). \(saved)"
            entry.control.toolTip = text
            entry.control.setAccessibilityHelp(text)
        }
    }

    /// Greys the groups that do not apply: Clip duration and Start position while Skim is off, Image
    /// duration and GIF loops while Settings does not accept that media type. Greyed controls are
    /// disabled at `disabledAlpha`, with the group label in `textDisabled`.
    private func applyActivity(_ newActivity: SkimStripActivity) {
        activity = newActivity
        func apply(_ controls: [NSView], active: Bool) {
            for control in controls {
                (control as? NSControl)?.isEnabled = active
                // The design-system segmented control dims itself when disabled.
                control.alphaValue = active || control is DWBSegmentedControl ? 1 : DWBMetrics.disabledAlpha
            }
        }
        apply([durationMode, fixedDuration, randomMinimum, randomMaximum, startPosition],
              active: newActivity.skimEnabled)
        apply([imageDuration, imageDurationStepper], active: newActivity.acceptsImages)
        if let imageSuffix { apply([imageSuffix], active: newActivity.acceptsImages) }
        apply([gifLoops, gifLoopsStepper], active: newActivity.acceptsGIFs)
        applyLabelColors()
    }

    /// Runs a store write for this strip's own edit and reports what persisted. `before` is read first
    /// because the store's notification re-syncs the controls (and the snapshot they read) at once.
    private func commit(_ setting: SkimStripSetting, _ edit: () -> Void) {
        let before = store.snapshot()
        edit()
        let after = store.snapshot()
        if let confirmation = SkimStripConfirmation.make(for: setting, before: before, after: after) {
            onSettingCommitted?(confirmation)
        }
    }

    @objc private func durationModeChanged(_ sender: DWBSegmentedControl) {
        guard !isSynchronizing else { return }
        commit(.clipDuration) {
            store.setPreviewDurationMode(sender.selectedSegment == 0
                ? SettingsDefaultsRegistry.Defaults.previewDurationModeFixed
                : SettingsDefaultsRegistry.Defaults.previewDurationModeRandom)
        }
    }

    @objc private func startPositionChanged(_ sender: DWBSegmentedControl) {
        guard !isSynchronizing else { return }
        commit(.startPosition) {
            store.setStartPositionMode(sender.selectedSegment == 0
                ? SettingsDefaultsRegistry.Defaults.startPositionModeBeginning
                : SettingsDefaultsRegistry.Defaults.startPositionModeRandom)
        }
    }

    @objc private func imageDurationStepperChanged(_ sender: NSStepper) {
        guard !isSynchronizing else { return }
        commit(.imageDuration) { store.setImageDurationSeconds(sender.doubleValue) }
    }

    @objc private func gifLoopsStepperChanged(_ sender: NSStepper) {
        guard !isSynchronizing else { return }
        commit(.gifLoops) { store.setGIFLoopCount(sender.integerValue) }
    }

    @objc private func queueOrderChanged(_ sender: NSPopUpButton) {
        guard !isSynchronizing,
              let raw = sender.selectedItem?.representedObject as? String,
              let mode = QueueOrderMode(rawValue: raw) else { return }
        commit(.queueOrder) { store.setQueueOrderMode(mode) }
    }

    @objc private func loopQueueChanged(_ sender: NSSwitch) {
        guard !isSynchronizing else { return }
        commit(.loopQueue) { store.setLoopQueueEnabled(sender.state == .on) }
    }

    @objc private func progressiveRandomSkimChanged(_ sender: NSSwitch) {
        guard !isSynchronizing else { return }
        commit(.progressiveSkim) { store.setProgressiveRandomSkimEnabled(sender.state == .on) }
    }

    @objc private func collapseTapped(_ sender: NSButton) { onCollapse?() }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard !isSynchronizing, let field = notification.object as? NSTextField else { return }
        switch field {
        case fixedDuration: commit(.clipDuration) { store.setFixedDurationSeconds(field.integerValue) }
        case randomMinimum: commit(.clipDuration) { store.setRandomMinimumSeconds(field.integerValue) }
        case randomMaximum: commit(.clipDuration) { store.setRandomMaximumSeconds(field.integerValue) }
        case skipIntro: commit(.skipIntro) { store.setSkipIntroSeconds(field.integerValue) }
        case imageDuration: commit(.imageDuration) { store.setImageDurationSeconds(field.doubleValue) }
        case gifLoops: commit(.gifLoops) { store.setGIFLoopCount(field.integerValue) }
        default: return
        }
        syncFromStore()
    }
}

/// Semantic roles for the strip's chrome (design system 9.8). The divider between groups is `border`
/// and the active group labels are `textSecondary`; under Increase Contrast they take the stronger
/// `borderStrong` and `textPrimary` steps. The strip's bottom edge stays `gridLine` (`border` under
/// Increase Contrast). Supporting marks (the chevrons and the range dash) stay `textTertiary`.
private enum StripColor {
    static var divider: NSColor { DWBAccessibility.border }
    static var line: NSColor { DWBAccessibility.increaseContrast ? DWBAccessibility.border : DWBColor.gridLine }
    static var groupLabel: NSColor { DWBAccessibility.textSecondary }
    static var supportingText: NSColor { DWBAccessibility.textTertiary }
}

/// The 1 pt rule between strip groups. It follows Increase Contrast live.
private final class StripSeparator: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(false)
        applyColor()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(accessibilityOptionsChanged),
                                               name: DWBAccessibility.didChange,
                                               object: nil)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func accessibilityOptionsChanged() { applyColor() }

    private func applyColor() {
        layer?.backgroundColor = StripColor.divider.cgColor
    }
}

/// A number field in the design system's style: `surfaceSunken` ground, 1 pt `borderStrong` edge,
/// radius 5, 7 pt side padding.
final class SkimNumberField: NSTextField {
    override class var cellClass: AnyClass? {
        get { SkimNumberFieldCell.self }
        set {}
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBezeled = false
        isBordered = false
        drawsBackground = false
        textColor = DWBColor.textPrimary
        wantsLayer = true
        layer?.backgroundColor = DWBColor.surfaceSunken.cgColor
        layer?.borderColor = DWBColor.borderStrong.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = DWBMetrics.radiusBanner
    }

    convenience init() { self.init(frame: .zero) }

    required init?(coder: NSCoder) { fatalError("programmatic only") }
}

private final class SkimNumberFieldCell: NSTextFieldCell {
    private static let sidePadding: CGFloat = 7

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var inner = super.drawingRect(forBounds: rect).insetBy(dx: Self.sidePadding, dy: 0)
        let lineHeight = ceil((font?.ascender ?? 11) - (font?.descender ?? -3) + (font?.leading ?? 0))
        inner.origin.y = rect.minY + (rect.height - lineHeight) / 2
        inner.size.height = lineHeight
        return inner
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj,
                   delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                         delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj,
                     delegate: delegate, start: selStart, length: selLength)
    }
}
