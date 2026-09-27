import XCTest

final class SettingsPresentationTests: XCTestCase {
    func testSettingsCategoriesAreStableAndRestorable() {
        XCTAssertEqual(SettingsPresentation.paneIdentifiers.count, 8)
        XCTAssertEqual(SettingsPresentation.panes.map(\.title), [
            "Playback", "Skim Preview", "Skim+", "Controls",
            "Queue & Files", "Shortcuts", "Advanced", "About",
        ])
        XCTAssertFalse(SettingsPresentation.sidebarUsesSymbols)
        XCTAssertFalse(SettingsPresentation.usesPlayerPeriwinkleAsPrimaryAccent)
        XCTAssertEqual(SettingsPresentation.validatedPaneIdentifier("skimPlus"), "skimPlus")
        XCTAssertEqual(SettingsPresentation.validatedPaneIdentifier("removed"), "playback")
    }

    func testSettingsAccentRolesResolveToDwbSkimDarkTealTokens() {
        XCTAssertEqual(SettingsPresentation.AccentRole.allCases.count, 6)
        for role in SettingsPresentation.AccentRole.allCases {
            let expected: SettingsPresentation.BrandToken = role == .structuralSeparator ? .darkTeal : .darkTeal500
            XCTAssertEqual(SettingsPresentation.brandToken(for: role), expected)
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
        XCTAssertEqual(SettingsPresentation.paneHeading(for: "controls"), "Controls")
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
        XCTAssertTrue(labels.contains("Restore All Settings to Default"))
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
            SettingsPresentation.progressiveRandomSkimCoverageHelperText,
            "How many Progressive Random Skim segments to sample across the video.\nSnippet lengths follow the Clip Duration settings above."
        )
    }
}
