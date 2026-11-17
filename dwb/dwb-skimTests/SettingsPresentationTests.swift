import XCTest

final class SettingsPresentationTests: XCTestCase {
    func testSettingsCategoriesAreStableAndRestorable() {
        XCTAssertEqual(SettingsPresentation.paneIdentifiers.count, 8)
        XCTAssertEqual(SettingsPresentation.panes.map(\.title), [
            "Playback", "Appearance & Controls", "Queue & Files", "Shortcuts",
            "Skim Preview", "dwb+",
            "Advanced", "About",
        ])
        XCTAssertFalse(SettingsPresentation.sidebarUsesSymbols)
        XCTAssertEqual(SettingsPresentation.validatedPaneIdentifier("skimPlus"), "skimPlus")
        XCTAssertEqual(SettingsPresentation.validatedPaneIdentifier("removed"), "playback")
    }

    func testSettingsAccentRolesResolveToDesignSystemTokens() {
        XCTAssertEqual(SettingsPresentation.AccentRole.allCases.count, 6)
        let expected: [SettingsPresentation.AccentRole: SettingsPresentation.DesignToken] = [
            .primaryEmphasis: .accentText,
            .informationalLink: .accentText,
            .selectedSidebarFill: .accentTintStrong,
            .focusKeyline: .accentFill,
            .shortcutKeyline: .accentFill,
            .structuralSeparator: .border,
        ]
        for role in SettingsPresentation.AccentRole.allCases {
            XCTAssertEqual(SettingsPresentation.designToken(for: role), expected[role], "\(role)")
        }
    }

    func testSettingsUsesOneSharedAlignmentAndResponsiveLayoutModel() {
        XCTAssertEqual(SettingsPresentation.labelColumnWidth, 156)
        XCTAssertEqual(SettingsPresentation.columnSpacing, 14)
        XCTAssertEqual(SettingsPresentation.rowSpacing, 13)
        XCTAssertEqual(SettingsPresentation.pageLeadingInset, 30)
        XCTAssertEqual(SettingsPresentation.helperMaximumWidth, 390)
        XCTAssertEqual(SettingsPresentation.sliderWidth, 190)
        XCTAssertEqual(SettingsPresentation.minimumWindowSize.width, 760)
        XCTAssertEqual(SettingsPresentation.minimumWindowSize.height, 500)
        XCTAssertEqual(SettingsPresentation.defaultWindowSize.width, 820)
        XCTAssertEqual(SettingsPresentation.defaultWindowSize.height, 550)
        XCTAssertGreaterThan(SettingsPresentation.maximumContentWidth, SettingsPresentation.labelColumnWidth)
    }

    func testWindowTitleIsStaticAndPaneHeadingsAreContentData() {
        XCTAssertEqual(SettingsPresentation.windowTitle, "Settings")
        XCTAssertEqual(SettingsPresentation.paneHeading(for: "controls"), "Appearance & Controls")
        XCTAssertEqual(SettingsPresentation.paneHeading(for: "removed"), "Playback")
    }

    func testAboutValuesComeFromBundleMetadata() {
        let values = SettingsPresentation.aboutDisplayValues(infoDictionary: [
            "CFBundleDisplayName": "dwb skim",
            "CFBundleShortVersionString": "4.2.2",
            "CFBundleVersion": "422",
            "LSMinimumSystemVersion": "13.0",
        ])
        XCTAssertEqual(values.productName, "dwb skim")
        XCTAssertEqual(values.version, "4.2.2")
        XCTAssertEqual(values.build, "422")
        XCTAssertEqual(values.minimumSystemVersion, "13.0")
        XCTAssertFalse(SettingsPresentation.productDescription.isEmpty)
    }

    func testReopeningSettingsRestoresTheStoredPane() {
        // Regression: every entry point previously forced "playback", which also
        // overwrote the stored pane on each open.
        XCTAssertEqual(
            SettingsPresentation.resolvedPaneIdentifier(requested: nil, stored: "queueFiles"),
            "queueFiles"
        )
        XCTAssertEqual(
            SettingsPresentation.resolvedPaneIdentifier(requested: nil, stored: "about"),
            "about"
        )
    }

    func testAnExplicitPaneRequestWinsOverTheStoredPane() {
        XCTAssertEqual(
            SettingsPresentation.resolvedPaneIdentifier(requested: "skimPlus", stored: "advanced"),
            "skimPlus"
        )
    }

    func testUnknownPaneIdentifiersFallBackSafely() {
        XCTAssertEqual(
            SettingsPresentation.resolvedPaneIdentifier(requested: nil, stored: nil),
            "playback"
        )
        XCTAssertEqual(
            SettingsPresentation.resolvedPaneIdentifier(requested: nil, stored: "removed"),
            "playback"
        )
        // An unknown explicit request must not discard a valid stored pane.
        XCTAssertEqual(
            SettingsPresentation.resolvedPaneIdentifier(requested: "removed", stored: "shortcuts"),
            "shortcuts"
        )
    }

    func testEveryPaneIdentifierResolvesToItself() {
        for identifier in SettingsPresentation.paneIdentifiers {
            XCTAssertEqual(
                SettingsPresentation.resolvedPaneIdentifier(requested: identifier, stored: nil),
                identifier
            )
        }
    }

    func testEveryExistingSettingIsRepresentedOnceInTheInventory() {
        let labels = SettingsPresentation.representedSettingLabels
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertTrue(labels.contains("Clip duration"))
        XCTAssertTrue(labels.contains("Queue order"))
        XCTAssertTrue(labels.contains("Background audio volume"))
        XCTAssertTrue(labels.contains("Restore Default Settings\u{2026}"))
        XCTAssertTrue(labels.contains("Enable background audio"))
        XCTAssertTrue(labels.contains("Coverage"))
    }

    func testProgressiveRandomSkimCoverageIntensityPresentationExposesFiveLevels() {
        XCTAssertEqual(SettingsPresentation.progressiveRandomSkimIntensityOptions.count, 5)
        XCTAssertEqual(SettingsPresentation.progressiveRandomSkimIntensityOptions, [
            .light, .standard, .thorough, .ultra, .max
        ])
        XCTAssertEqual(SettingsPresentation.progressiveRandomSkimIntensityLabels, [
            "Light", "Standard", "Thorough", "Ultra", "Max"
        ])

        for (expectedSegment, intensity) in SettingsPresentation.progressiveRandomSkimIntensityOptions.enumerated() {
            XCTAssertEqual(SettingsPresentation.intensitySegment(for: intensity), expectedSegment)
            XCTAssertEqual(SettingsPresentation.intensity(forSegment: expectedSegment), intensity)
        }

        // Out-of-bounds segment fallback
        XCTAssertEqual(SettingsPresentation.intensity(forSegment: -1), .standard)
        XCTAssertEqual(SettingsPresentation.intensity(forSegment: 5), .standard)
        XCTAssertEqual(SettingsPresentation.intensity(forSegment: 99), .standard)

        XCTAssertEqual(
            SettingsPresentation.Text.coverageHelper,
            "Controls how many segments are sampled. Segment lengths follow the preview duration settings above."
        )
    }

    // MARK: - Sidebar groups and page headers (P48)

    func testSidebarGroupsFollowTheSuiteOrder() {
        let groups = SettingsPresentation.sidebarGroups
        XCTAssertEqual(groups.map(\.label), ["General", "dwb skim", "System"])
        XCTAssertEqual(groups.map(\.isAccented), [false, true, false])
        XCTAssertEqual(groups[0].paneIdentifiers, ["playback", "controls", "queueFiles", "shortcuts"])
        XCTAssertEqual(groups[1].paneIdentifiers, ["skimPreview", "skimPlus"])
        XCTAssertEqual(groups[2].paneIdentifiers, ["advanced", "about"])
    }

    func testPanesAreTheGroupsFlattenedInSidebarOrder() {
        XCTAssertEqual(SettingsPresentation.paneIdentifiers,
                       SettingsPresentation.sidebarGroups.flatMap(\.paneIdentifiers))
        XCTAssertEqual(SettingsPresentation.paneIdentifiers.count, 8)
        XCTAssertEqual(Set(SettingsPresentation.paneIdentifiers).count, 8)
        // The page identifiers (and the stored selected-page key) did not change.
        XCTAssertEqual(Set(SettingsPresentation.paneIdentifiers),
                       ["playback", "skimPreview", "skimPlus", "controls",
                        "queueFiles", "shortcuts", "advanced", "about"])
        XCTAssertEqual(SettingsPresentation.selectedPaneDefaultsKey, "dwb.settings.selectedPane")
    }

    func testEveryPageExceptAboutHasAHeaderWithTheDesignSystemDescription() {
        for identifier in SettingsPresentation.paneIdentifiers {
            if identifier == "about" {
                XCTAssertFalse(SettingsPresentation.showsPageHeader(for: identifier))
                XCTAssertEqual(SettingsPresentation.pageDescription(for: identifier), "")
            } else {
                XCTAssertTrue(SettingsPresentation.showsPageHeader(for: identifier), identifier)
                XCTAssertFalse(SettingsPresentation.pageDescription(for: identifier).isEmpty, identifier)
            }
        }
        XCTAssertEqual(SettingsPresentation.pageDescription(for: "playback"),
                       "Video playback, image timing, and GIF loops.")
        XCTAssertEqual(SettingsPresentation.pageDescription(for: "shortcuts"),
                       "Find and customize keyboard shortcuts for this app.")
        XCTAssertEqual(SettingsPresentation.pageDescription(for: "skimPlus"),
                       "Play a background track on its own or alongside video audio.")
    }

    // MARK: - Playback, Appearance & Controls, Queue & Files (P55)

    func testThePageIdentifierForAppearanceAndControlsIsUnchanged() {
        let controls = SettingsPresentation.panes.first { $0.title == "Appearance & Controls" }
        XCTAssertEqual(controls?.identifier, "controls")
        XCTAssertEqual(SettingsPresentation.paneIdentifiers[1], "controls")
        XCTAssertEqual(SettingsPresentation.validatedPaneIdentifier("controls"), "controls")
    }

    func testThreeGeneralPagesHaveTheApprovedTitlesAndDescriptions() {
        XCTAssertEqual(SettingsPresentation.paneHeading(for: "playback"), "Playback")
        XCTAssertEqual(SettingsPresentation.pageDescription(for: "playback"),
                       "Video playback, image timing, and GIF loops.")
        XCTAssertEqual(SettingsPresentation.paneHeading(for: "controls"), "Appearance & Controls")
        XCTAssertEqual(SettingsPresentation.pageDescription(for: "controls"),
                       "Customize playback controls and window appearance.")
        XCTAssertEqual(SettingsPresentation.paneHeading(for: "queueFiles"), "Queue & Files")
        XCTAssertEqual(SettingsPresentation.pageDescription(for: "queueFiles"),
                       "Choose accepted media, queue behavior, and filename prefixes.")
    }

    func testThreeGeneralPagesListTheirSectionsInOrder() {
        typealias Text = SettingsPresentation.Text
        XCTAssertEqual(Text.playbackSections, ["Video", "Images & GIFs", "Audio"])
        XCTAssertEqual(Text.controlsSections, ["Playback controls", "Window"])
        XCTAssertEqual(Text.queueFilesSections, ["Accepted media", "Queue behavior", "Filename prefixes"])
        XCTAssertEqual(Text.acceptedMediaTitles, ["Videos", "Images", "GIFs"])
    }

    func testSettingLabelsAreSentenceCaseAndNameThePlaybackControls() {
        typealias Text = SettingsPresentation.Text
        XCTAssertEqual(Text.showFilenameTitle, "Show filename when playback starts")
        XCTAssertEqual(Text.autoHidePlaybackControlsTitle, "Automatically hide playback controls")
        XCTAssertEqual(Text.reduceMotionTitle, "Reduce motion in playback controls")
        XCTAssertEqual(Text.autoHideTitleBarTitle, "Automatically hide title bar")
        XCTAssertEqual(Text.hideTitleBarTitle, "Hide title bar")
        XCTAssertEqual(Text.showQueuePanelTitle, "Show queue panel in new player windows")
        XCTAssertEqual(Text.advanceAfterPrefixTitle, "Advance after applying a prefix")
        XCTAssertEqual(Text.primaryPrefixLabel, "Primary prefix")
        XCTAssertEqual(Text.secondaryPrefixLabel, "Secondary prefix")
        XCTAssertEqual(Text.imageDurationUnit, "seconds")
        XCTAssertEqual(Text.gifLoopsUnit, "loops")
        for label in SettingsPresentation.representedSettingLabels {
            XCTAssertFalse(label.contains("overlay"), label)
            XCTAssertFalse(label.contains("titlebar"), label)
            XCTAssertFalse(label.contains("custom prefix"), label)
        }
    }

    func testSupportingTextMatchesTheApprovedWording() {
        typealias Text = SettingsPresentation.Text
        XCTAssertEqual(Text.playbackSpeedHelper,
                       "Affects video only. Applies to the most recently active player window.")
        XCTAssertEqual(Text.windowOpacityHelper, "Applies to the most recently active player window.")
        XCTAssertEqual(Text.hideTitleBarHelper, "Removes the title bar while keeping the player windowed.")
        XCTAssertEqual(Text.prefixGuidance,
                       "Leave a prefix blank to disable its action. Prefixes replace each other rather than stack. Each prefix ends in exactly one underscore.")
        XCTAssertFalse(Text.queueOrderHelper.contains("Queue Page"))
        XCTAssertFalse(Text.showQueuePanelTitle.contains("Queue Page"))
    }

    // MARK: Dependent rows

    func testHideDelayFollowsAutomaticallyHidePlaybackControls() {
        XCTAssertTrue(SettingsPresentation.hideDelayIsEnabled(automaticallyHidesPlaybackControls: true))
        XCTAssertFalse(SettingsPresentation.hideDelayIsEnabled(automaticallyHidesPlaybackControls: false))
    }

    func testAutomaticTitleBarHidingYieldsToHideTitleBar() {
        XCTAssertTrue(SettingsPresentation.automaticTitleBarHidingIsEnabled(hidesTitleBar: false))
        XCTAssertFalse(SettingsPresentation.automaticTitleBarHidingIsEnabled(hidesTitleBar: true))
    }

    // MARK: Speed popup titles

    func testSpeedPopupTitlesUseTheMultiplicationSign() {
        // The nine rates of `PlaybackSpeedOption.all`, in menu order.
        let rates: [Float] = [0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 2.50, 3.00]
        XCTAssertEqual(rates.map(SettingsPresentation.speedPopupTitle(forRate:)), [
            "0.25\u{00D7}", "0.50\u{00D7}", "0.75\u{00D7}", "1.00\u{00D7} (Normal)",
            "1.25\u{00D7}", "1.50\u{00D7}", "2.00\u{00D7}", "2.50\u{00D7}", "3.00\u{00D7}",
        ])
    }

    func testSpeedPopupTitleUsesTheMultiplicationSignNotTheLetterX() {
        for rate: Float in [0.25, 1.00, 3.00] {
            let title = SettingsPresentation.speedPopupTitle(forRate: rate)
            XCTAssertTrue(title.contains("\u{00D7}"), title)
            XCTAssertFalse(title.contains("x"), title)
        }
    }

    // MARK: Prefix shortcut text

    func testPrefixShortcutTextForOneKey() {
        XCTAssertEqual(SettingsPresentation.prefixShortcutText(keys: ["N"]), "Shortcut: N")
    }

    func testPrefixShortcutTextForSeveralKeysKeepsAssignmentOrder() {
        XCTAssertEqual(SettingsPresentation.prefixShortcutText(keys: ["N", "H"]), "Shortcuts: N, H")
        XCTAssertEqual(SettingsPresentation.prefixShortcutText(keys: ["H", "N", "K"]), "Shortcuts: H, N, K")
    }

    func testPrefixShortcutTextForNoKey() {
        XCTAssertEqual(SettingsPresentation.prefixShortcutText(keys: []), "Shortcut: Unassigned")
    }

    func testPrefixShortcutLinesComeFromTheLiveKeyAssignments() {
        XCTAssertEqual(SettingsPresentation.prefixShortcutLine(for: .primaryPrefixRename), "Shortcut: N")
        XCTAssertEqual(SettingsPresentation.prefixShortcutLine(for: .secondaryPrefixRename), "Shortcut: M")
    }

    func testPrefixShortcutLineFollowsAnOverrideAddedKeysAndRemoval() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare("n"), with: .bare("k"), for: .togglePrimaryPrefix)
        XCTAssertEqual(SettingsPresentation.prefixShortcutLine(for: .primaryPrefixRename, store: store), "Shortcut: K")
        store.replaceKey(nil, with: .bare("h"), for: .togglePrimaryPrefix)
        XCTAssertEqual(SettingsPresentation.prefixShortcutLine(for: .primaryPrefixRename, store: store), "Shortcuts: K, H")
        store.replaceKey(.bare("k"), with: nil, for: .togglePrimaryPrefix)
        store.replaceKey(.bare("h"), with: nil, for: .togglePrimaryPrefix)
        XCTAssertEqual(SettingsPresentation.prefixShortcutLine(for: .primaryPrefixRename, store: store), "Shortcut: Unassigned")
        // The other prefix is untouched.
        XCTAssertEqual(SettingsPresentation.prefixShortcutLine(for: .secondaryPrefixRename, store: store), "Shortcut: M")
        store.restoreDefaults()
        XCTAssertEqual(SettingsPresentation.prefixShortcutLine(for: .primaryPrefixRename, store: store), "Shortcut: N")
    }
}
