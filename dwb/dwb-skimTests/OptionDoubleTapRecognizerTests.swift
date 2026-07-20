import XCTest

final class OptionDoubleTapRecognizerTests: XCTestCase {
    func testValidLeftOptionDoubleTapTogglesOnce() {
        assertValidDoubleTap(side: .left)
    }

    func testValidRightOptionDoubleTapTogglesOnce() {
        assertValidDoubleTap(side: .right)
    }

    func testLeftOptionAppKitSnapshotsTranslateWithoutKeyDown() {
        var adapter = OptionDoubleTapEventAdapter()
        XCTAssertFalse(adapter.handle(event(.flagsChanged, 58, [.option], 0), targetIsEligible: true))
        XCTAssertFalse(adapter.handle(event(.flagsChanged, 58, [], 0.04), targetIsEligible: true))
        XCTAssertFalse(adapter.handle(event(.flagsChanged, 58, [.option], 0.2), targetIsEligible: true))
        XCTAssertTrue(adapter.handle(event(.flagsChanged, 58, [], 0.24), targetIsEligible: true))
    }

    func testRightOptionAppKitSnapshotsTranslate() {
        var adapter = OptionDoubleTapEventAdapter()
        XCTAssertFalse(tap(&adapter, keyCode: 61, down: 0, up: 0.04))
        XCTAssertTrue(tap(&adapter, keyCode: 61, down: 0.2, up: 0.24))
    }

    func testMixedLeftRightDoubleTapToggles() {
        var adapter = OptionDoubleTapEventAdapter()
        XCTAssertFalse(tap(&adapter, keyCode: 58, down: 0, up: 0.04))
        XCTAssertTrue(tap(&adapter, keyCode: 61, down: 0.2, up: 0.24))
    }

    func testDeviceIndependentUnrelatedFlagsDoNotHideOptionTransition() {
        var adapter = OptionDoubleTapEventAdapter()
        XCTAssertFalse(adapter.handle(event(.flagsChanged, 58, [.option, .capsLock], 0), targetIsEligible: true))
        XCTAssertFalse(adapter.handle(event(.flagsChanged, 58, [.capsLock], 0.04), targetIsEligible: true))
        XCTAssertFalse(adapter.handle(event(.flagsChanged, 58, [.option, .capsLock], 0.2), targetIsEligible: true))
        XCTAssertTrue(adapter.handle(event(.flagsChanged, 58, [.capsLock], 0.24), targetIsEligible: true))
    }

    func testDuplicateFlagsChangedTransitionIsIgnored() {
        var adapter = OptionDoubleTapEventAdapter()
        XCTAssertFalse(adapter.handle(event(.flagsChanged, 58, [.option], 0), targetIsEligible: true))
        XCTAssertFalse(adapter.handle(event(.flagsChanged, 58, [.option], 0.01), targetIsEligible: true))
        XCTAssertFalse(adapter.handle(event(.flagsChanged, 58, [], 0.04), targetIsEligible: true))
        XCTAssertFalse(adapter.handle(event(.flagsChanged, 58, [.option], 0.2), targetIsEligible: true))
        XCTAssertTrue(adapter.handle(event(.flagsChanged, 58, [], 0.24), targetIsEligible: true))
    }

    func testThirdTapStartsNewSequenceRatherThanRetriggering() {
        var adapter = OptionDoubleTapEventAdapter()
        XCTAssertFalse(tap(&adapter, keyCode: 58, down: 0, up: 0.04))
        XCTAssertTrue(tap(&adapter, keyCode: 58, down: 0.2, up: 0.24))
        XCTAssertFalse(tap(&adapter, keyCode: 58, down: 0.3, up: 0.34))
    }

    func testTimeoutAfterOneTapDoesNotToggle() {
        var recognizer = OptionDoubleTapRecognizer()
        _ = tap(&recognizer, side: .left, down: 0, up: 0.05)
        recognizer.timeout(at: 0.46)
        XCTAssertFalse(tap(&recognizer, side: .left, down: 0.47, up: 0.50))
    }

    func testHoldAndRepeatDoNotToggle() {
        var recognizer = OptionDoubleTapRecognizer()
        XCTAssertFalse(recognizer.optionChanged(side: .left, isDown: true, isRepeat: false,
                                                timestamp: 0, isEligible: true))
        XCTAssertFalse(recognizer.optionChanged(side: .left, isDown: true, isRepeat: true,
                                                timestamp: 0.1, isEligible: true))
        XCTAssertFalse(recognizer.optionChanged(side: .left, isDown: false, isRepeat: false,
                                                timestamp: 1, isEligible: true))
    }

    func testNonModifierKeyCancellationAndHeldKeyExclusion() {
        var adapter = OptionDoubleTapEventAdapter()
        XCTAssertFalse(adapter.handle(event(.keyDown, 0, [.option], 0.01), targetIsEligible: true))
        XCTAssertFalse(tap(&adapter, keyCode: 58, down: 0.02, up: 0.04))
        XCTAssertFalse(adapter.handle(event(.keyUp, 0, [], 0.05), targetIsEligible: true))
        XCTAssertFalse(tap(&adapter, keyCode: 58, down: 0.1, up: 0.14))
    }

    func testOptionChordCancellation() {
        var adapter = OptionDoubleTapEventAdapter()
        XCTAssertFalse(adapter.handle(event(.flagsChanged, 58, [.option], 0), targetIsEligible: true))
        XCTAssertFalse(adapter.handle(event(.keyDown, 13, [.option], 0.01), targetIsEligible: true))
        XCTAssertFalse(adapter.handle(event(.keyUp, 13, [.option], 0.02), targetIsEligible: true))
        XCTAssertFalse(adapter.handle(event(.flagsChanged, 58, [], 0.04), targetIsEligible: true))
        XCTAssertFalse(tap(&adapter, keyCode: 58, down: 0.1, up: 0.14))
    }

    func testInactiveAppOrWindowNeverToggles() {
        var recognizer = OptionDoubleTapRecognizer()
        XCTAssertFalse(recognizer.optionChanged(side: .left, isDown: true, isRepeat: false,
                                                timestamp: 0, isEligible: false))
        XCTAssertFalse(recognizer.optionChanged(side: .left, isDown: false, isRepeat: false,
                                                timestamp: 0.05, isEligible: false))
        XCTAssertFalse(tap(&recognizer, side: .left, down: 0.1, up: 0.15))
    }

    func testFocusChangeResetsSequence() {
        var recognizer = OptionDoubleTapRecognizer()
        _ = tap(&recognizer, side: .left, down: 0, up: 0.04)
        recognizer.focusChanged()
        XCTAssertFalse(tap(&recognizer, side: .left, down: 0.1, up: 0.14))
    }

    func testKeyPlayerEligibilityDoesNotRequireVideoSurfaceFirstResponder() {
        let target = OptionDoubleTapTargetDescriptor(identifier: "player",
                                                      isPlayerWindow: true,
                                                      isKeyWindow: true,
                                                      isTextEntryFocused: false)
        XCTAssertEqual(OptionDoubleTapTargetDescriptor.keyPlayerIdentifier(applicationIsActive: true,
                                                                             targets: [target]),
                       "player")
    }

    func testTextEntrySettingsAndDebugWindowsAreExcluded() {
        let targets = [
            OptionDoubleTapTargetDescriptor(identifier: "editing-player", isPlayerWindow: true, isKeyWindow: true, isTextEntryFocused: true),
            OptionDoubleTapTargetDescriptor(identifier: "settings", isPlayerWindow: false, isKeyWindow: true, isTextEntryFocused: false),
            OptionDoubleTapTargetDescriptor(identifier: "debug", isPlayerWindow: false, isKeyWindow: true, isTextEntryFocused: false),
        ]
        XCTAssertNil(OptionDoubleTapTargetDescriptor.keyPlayerIdentifier(applicationIsActive: true, targets: targets))
    }

    func testMultiWindowRoutingSelectsOnlyKeyPlayer() {
        let targets = [
            OptionDoubleTapTargetDescriptor(identifier: "background", isPlayerWindow: true, isKeyWindow: false, isTextEntryFocused: false),
            OptionDoubleTapTargetDescriptor(identifier: "key", isPlayerWindow: true, isKeyWindow: true, isTextEntryFocused: false),
        ]
        XCTAssertEqual(OptionDoubleTapTargetDescriptor.keyPlayerIdentifier(applicationIsActive: true,
                                                                             targets: targets),
                       "key")
    }

    // MARK: - Real NSEvent translation
    //
    // The regression that made this shortcut dead in the shipped app: building a
    // snapshot from a genuine .flagsChanged NSEvent read -[NSEvent isARepeat],
    // which is valid only for keyDown/keyUp and raises
    // NSInternalInconsistencyException otherwise. Every other test here uses the
    // memberwise initializer, so none of them could observe it. These go through
    // init?(event:) with real events instead.

    func testSnapshotFromRealFlagsChangedEventDoesNotRaise() {
        let snapshot = OptionDoubleTapEventSnapshot(
            event: Self.flagsChangedEvent(keyCode: 58, flags: [.maskAlternate]))
        XCTAssertEqual(snapshot?.kind, .flagsChanged)
        XCTAssertEqual(snapshot?.keyCode, 58)
        XCTAssertEqual(snapshot?.isRepeat, false)
        XCTAssertTrue(snapshot?.normalizedModifierFlags.contains(.option) == true)
    }

    func testRealLeftOptionDoubleTapEventSequenceTogglesExactlyOnce() {
        assertRealDoubleTap(firstKeyCode: 58, secondKeyCode: 58)
    }

    func testRealRightOptionDoubleTapEventSequenceTogglesExactlyOnce() {
        assertRealDoubleTap(firstKeyCode: 61, secondKeyCode: 61)
    }

    func testRealMixedSideOptionDoubleTapEventSequencesToggleExactlyOnce() {
        assertRealDoubleTap(firstKeyCode: 58, secondKeyCode: 61)
        assertRealDoubleTap(firstKeyCode: 61, secondKeyCode: 58)
    }

    // MARK: - Application-scoped dispatch

    func testCoordinatorStartsOnceAndStopsCleanly() {
        let coordinator = OptionDoubleTapCoordinator(notificationCenter: NotificationCenter(),
                                                     targetIsEligible: { true },
                                                     onToggle: {})
        coordinator.start()
        coordinator.start()
        XCTAssertTrue(coordinator.isInstalled)
        coordinator.stop()
        XCTAssertFalse(coordinator.isInstalled)
    }

    func testDispatchForwardsEveryEventIncludingTheGestureCompletingOne() {
        var toggles = 0
        let coordinator = OptionDoubleTapCoordinator(notificationCenter: NotificationCenter(),
                                                     targetIsEligible: { true },
                                                     onToggle: { toggles += 1 })
        var forwarded: [UInt16] = []
        for event in Self.doubleTapEvents(firstKeyCode: 58, secondKeyCode: 58) {
            SkimApplicationEventDispatch.dispatch(event, to: coordinator) { forwarded.append($0.keyCode) }
        }
        XCTAssertEqual(toggles, 1, "one physical gesture must produce exactly one toggle")
        XCTAssertEqual(forwarded.count, 4, "sendEvent must forward every original event, never swallow one")
    }

    func testDispatchForwardsEventsWhenNoCoordinatorIsInstalled() {
        var forwarded = 0
        SkimApplicationEventDispatch.dispatch(Self.flagsChangedEvent(keyCode: 58, flags: [.maskAlternate]),
                                              to: nil) { _ in forwarded += 1 }
        XCTAssertEqual(forwarded, 1)
    }

    func testIneligibleTargetSuppressesToggleButStillForwards() {
        var toggles = 0
        let coordinator = OptionDoubleTapCoordinator(notificationCenter: NotificationCenter(),
                                                     targetIsEligible: { false },
                                                     onToggle: { toggles += 1 })
        var forwarded = 0
        for event in Self.doubleTapEvents(firstKeyCode: 58, secondKeyCode: 58) {
            SkimApplicationEventDispatch.dispatch(event, to: coordinator) { _ in forwarded += 1 }
        }
        XCTAssertEqual(toggles, 0)
        XCTAssertEqual(forwarded, 4)
    }

    func testPrincipalClassNameMatchesModuleQualifiedApplicationSubclass() {
        XCTAssertEqual(SkimApplicationConfiguration.principalClassName, "dwb_skim.SkimApplication")
        XCTAssertEqual(SkimApplicationConfiguration.moduleName, "dwb_skim",
                       "must match SWIFT_MODULE_NAME in dwb/project.yml")
    }

    // MARK: - Real-event helpers

    private func assertRealDoubleTap(firstKeyCode: UInt16,
                                     secondKeyCode: UInt16,
                                     file: StaticString = #filePath, line: UInt = #line) {
        var adapter = OptionDoubleTapEventAdapter()
        var toggles = 0
        for event in Self.doubleTapEvents(firstKeyCode: firstKeyCode, secondKeyCode: secondKeyCode) {
            guard let snapshot = OptionDoubleTapEventSnapshot(event: event) else {
                return XCTFail("real flagsChanged event produced no snapshot", file: file, line: line)
            }
            if adapter.handle(snapshot, targetIsEligible: true) { toggles += 1 }
        }
        XCTAssertEqual(toggles, 1, file: file, line: line)
    }

    /// Press/release/press/release, matching what the window server delivers.
    private static func doubleTapEvents(firstKeyCode: UInt16, secondKeyCode: UInt16) -> [NSEvent] {
        [flagsChangedEvent(keyCode: firstKeyCode, flags: [.maskAlternate], timestamp: 0),
         flagsChangedEvent(keyCode: firstKeyCode, flags: [], timestamp: 0.04),
         flagsChangedEvent(keyCode: secondKeyCode, flags: [.maskAlternate], timestamp: 0.20),
         flagsChangedEvent(keyCode: secondKeyCode, flags: [], timestamp: 0.24)]
    }

    /// A genuine .flagsChanged NSEvent. NSEvent exposes no public initializer for
    /// this type, so it is bridged from a CGEvent the way AppKit does.
    private static func flagsChangedEvent(keyCode: UInt16,
                                          flags: CGEventFlags,
                                          timestamp: TimeInterval = 0) -> NSEvent {
        let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        cgEvent.type = .flagsChanged
        cgEvent.flags = flags
        cgEvent.timestamp = UInt64(timestamp * 1_000_000_000)
        return NSEvent(cgEvent: cgEvent)!
    }

    func testOnePhysicalDoubleTapEmitsExactlyOneToggle() {
        var adapter = OptionDoubleTapEventAdapter()
        var toggles = 0
        for snapshot in [event(.flagsChanged, 58, [.option], 0),
                         event(.flagsChanged, 58, [], 0.04),
                         event(.flagsChanged, 58, [.option], 0.2),
                         event(.flagsChanged, 58, [], 0.24)] {
            if adapter.handle(snapshot, targetIsEligible: true) { toggles += 1 }
        }
        XCTAssertEqual(toggles, 1)
    }

    private func assertValidDoubleTap(side: OptionKeySide,
                                      file: StaticString = #filePath, line: UInt = #line) {
        var recognizer = OptionDoubleTapRecognizer()
        XCTAssertFalse(tap(&recognizer, side: side, down: 0, up: 0.04), file: file, line: line)
        XCTAssertTrue(tap(&recognizer, side: side, down: 0.20, up: 0.24), file: file, line: line)
        XCTAssertFalse(tap(&recognizer, side: side, down: 0.30, up: 0.34), file: file, line: line)
    }

    private func event(_ kind: OptionDoubleTapEventKind,
                       _ keyCode: UInt16,
                       _ flags: NSEvent.ModifierFlags,
                       _ timestamp: TimeInterval) -> OptionDoubleTapEventSnapshot {
        OptionDoubleTapEventSnapshot(kind: kind, keyCode: keyCode,
                                     modifierFlags: flags, timestamp: timestamp)
    }

    private func tap(_ adapter: inout OptionDoubleTapEventAdapter,
                     keyCode: UInt16,
                     down: TimeInterval,
                     up: TimeInterval) -> Bool {
        XCTAssertFalse(adapter.handle(event(.flagsChanged, keyCode, [.option], down), targetIsEligible: true))
        return adapter.handle(event(.flagsChanged, keyCode, [], up), targetIsEligible: true)
    }

    private func tap(_ recognizer: inout OptionDoubleTapRecognizer,
                     side: OptionKeySide,
                     down: TimeInterval,
                     up: TimeInterval) -> Bool {
        XCTAssertFalse(recognizer.optionChanged(side: side, isDown: true, isRepeat: false,
                                                timestamp: down, isEligible: true))
        return recognizer.optionChanged(side: side, isDown: false, isRepeat: false,
                                        timestamp: up, isEligible: true)
    }
}
