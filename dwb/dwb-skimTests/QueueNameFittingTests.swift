import AppKit
import XCTest

/// Row text (design system 10.4): measured middle truncation of filenames, the prefix and search attributes, and the
/// failed-row message. Fit decisions use real native font measurement where fonts matter.
final class QueueNameFittingTests: XCTestCase {

    private let sample = "Long summer evening in the mountains.mp4"

    // MARK: - The truncation rule

    func testTailKeepsNineCharactersOrHalfTheKeptCountWhicheverIsSmaller() {
        XCTAssertEqual(QueueNameFitting.tailLength(keptCount: 40), 9)
        XCTAssertEqual(QueueNameFitting.tailLength(keptCount: 18), 9)
        XCTAssertEqual(QueueNameFitting.tailLength(keptCount: 17), 8)
        XCTAssertEqual(QueueNameFitting.tailLength(keptCount: 8), 4)
        XCTAssertEqual(QueueNameFitting.tailLength(keptCount: 3), 1)
        XCTAssertEqual(QueueNameFitting.tailLength(keptCount: 1), 0)
    }

    func testANameThatFitsIsShownWhole() {
        let fit = QueueNameFitting.fit(characterCount: sample.count, maxWidth: 1000) { _ in 100 }
        XCTAssertEqual(fit, .full)
    }

    func testCharactersAreDroppedOneAtATimeUntilTheNameFits() {
        // One point per character plus one for the ellipsis: a 28 pt line keeps 27 characters.
        let count = sample.count
        let fit = QueueNameFitting.fit(characterCount: count, maxWidth: 28) { candidate in
            switch candidate {
            case .full: return CGFloat(count)
            case .middle(let head, let tail): return CGFloat(head + tail + 1)
            case .ellipsisOnly: return 1
            }
        }
        XCTAssertEqual(fit, .middle(head: 18, tail: 9), "27 kept: min(9, 13) = 9 after the ellipsis")
    }

    func testTheDesignSystemSampleReadsWithItsExtensionIntact() {
        // Section 10.4: "Long summer evening in the…tains.mp4" (35 kept: 26 + 9).
        let name = NSAttributedString(string: sample)
        XCTAssertEqual(sample.count, 40)
        XCTAssertEqual(QueueNameFitting.apply(.middle(head: 26, tail: 9), to: name).string,
                       "Long summer evening in the…tains.mp4")
        XCTAssertEqual(name.string, sample, "the filename itself is never mutated")
    }

    func testApplyKeepsTheHeadTheEllipsisAndTheTail() {
        let shown = QueueNameFitting.apply(.middle(head: 10, tail: 9), to: NSAttributedString(string: sample)).string
        XCTAssertEqual(shown, "Long summe…tains.mp4")
        XCTAssertEqual(QueueNameFitting.apply(.full, to: NSAttributedString(string: sample)).string, sample)
    }

    func testTinyWidthsFallBackToJustTheEllipsis() {
        let fit = QueueNameFitting.fit(characterCount: 40, maxWidth: 0.5) { candidate in
            if case .ellipsisOnly = candidate { return 8 }
            return 100
        }
        XCTAssertEqual(fit, .ellipsisOnly)
        XCTAssertEqual(QueueNameFitting.apply(.ellipsisOnly, to: NSAttributedString(string: sample)).string, "…")
    }

    func testANameTooNarrowForAnyKeptCharactersEndsAtJustTheEllipsis() {
        // Two characters: keeping one needs 6 points, the ellipsis alone needs 3, and 3 is all there is.
        let fit = QueueNameFitting.fit(characterCount: 2, maxWidth: 3) { candidate in
            switch candidate {
            case .full: return 10
            case .middle(let head, let tail): return CGFloat(head + tail + 1) * 3
            case .ellipsisOnly: return 3
            }
        }
        XCTAssertEqual(fit, .ellipsisOnly)
    }

    func testCharactersAreWholeGraphemesNotUTF16Units() {
        // "é" as e + combining acute and a flag are single characters; truncation must never split them.
        let name = NSAttributedString(string: "caf\u{65}\u{301}-🇨🇦-clip-final-take-02.mp4")
        let shown = QueueNameFitting.apply(.middle(head: 6, tail: 6), to: name).string
        XCTAssertEqual(shown.count, 13)
        XCTAssertTrue(shown.hasPrefix("caf\u{65}\u{301}-🇨🇦"))
        XCTAssertTrue(shown.hasSuffix("02.mp4"))
    }

    // MARK: - Real measurement

    private func attributed(_ name: String, isCurrent: Bool = false, query: String = "") -> NSAttributedString {
        QueueNameStyle.attributed(for: name, isCurrent: isCurrent, searchQuery: query, primaryPrefix: "keep_", secondaryPrefix: "later_")
    }

    func testFittedNamesMeasureWithinTheWidthInTheirRealFonts() {
        // The name line at the actual 199 pt minimum: card 183 - inset 5 - right 10 = 168, and 152 with a bookmark.
        let card = QueueRowMetrics.cardFrame(rowWidth: 199, isCurrent: false)
        let plain = QueueRowMetrics.frames(card: card, isCurrent: false, isFailed: false, hasBookmark: false).name.width
        let marked = QueueRowMetrics.frames(card: card, isCurrent: false, isFailed: false, hasBookmark: true).name.width
        XCTAssertEqual(plain, 168)
        XCTAssertEqual(marked, 152)
        let names = [sample, "keep_" + sample, "later_Studio_07_a_very_long_recording_name_from_the_coast_at_sunset_2026-11-11_final.mp4", "short.mp4"]
        for name in names {
            for width in [plain, marked, 120, 60] {
                let fitted = QueueNameFitting.fitted(attributed(name), maxWidth: width)
                XCTAssertLessThanOrEqual(ceil(fitted.size().width), width, "\(name) at \(width)")
            }
        }
    }

    func testAShortNameIsUntouchedAndALongOneKeepsItsExtension() {
        XCTAssertEqual(QueueNameFitting.fitted(attributed("short.mp4"), maxWidth: 168).string, "short.mp4")
        let shown = QueueNameFitting.fitted(attributed(sample), maxWidth: 140).string
        XCTAssertTrue(shown.contains("…"))
        XCTAssertTrue(shown.hasSuffix(".mp4"), "the tail keeps the extension: \(shown)")
        XCTAssertTrue(shown.hasPrefix("Long "), "the head keeps the start of the name: \(shown)")
    }

    func testMoreRoomKeepsMoreOfTheName() {
        let narrow = QueueNameFitting.fitted(attributed(sample), maxWidth: 100).string.count
        let wide = QueueNameFitting.fitted(attributed(sample), maxWidth: 160).string.count
        XCTAssertGreaterThan(wide, narrow)
    }

    func testAPrefixThatIsPartOfTheKeptHeadKeepsItsMarkerColorAndBoldWeight() {
        let fitted = QueueNameFitting.fitted(attributed("keep_" + sample), maxWidth: 140)
        let color = fitted.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, theme.markerPrimary)
        let font = fitted.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font, QueueFonts.namePrefix)
    }

    // MARK: - Attributes: prefix and search

    func testConfiguredPrefixIsBoldInItsMarkerRoleAndTheRestIsMediumPrimary() {
        let primary = attributed("keep_clip.mp4")
        XCTAssertEqual(primary.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, theme.markerPrimary)
        XCTAssertEqual(primary.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, QueueFonts.namePrefix)
        XCTAssertEqual(primary.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor, DWBColor.textPrimary)
        XCTAssertEqual(primary.attribute(.font, at: 5, effectiveRange: nil) as? NSFont, QueueFonts.name(isCurrent: false))

        let secondary = attributed("later_clip.mp4")
        XCTAssertEqual(secondary.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, theme.markerSecondary)
        XCTAssertEqual(secondary.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor, DWBColor.textPrimary)
    }

    func testPrimaryIsPeriwinkleAndSecondaryBurntOrangeForSkim() {
        XCTAssertEqual(theme.markerPrimary, DWBColor.periOnDark)
        XCTAssertEqual(theme.markerSecondary, DWBColor.orangeOnDark)
    }

    func testThePlayingRowNameIsSemiboldAndOthersAreMedium() {
        XCTAssertEqual(attributed("clip.mp4", isCurrent: true).attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
                       NSFont.systemFont(ofSize: 12.5, weight: .semibold))
        XCTAssertEqual(attributed("clip.mp4").attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
                       NSFont.systemFont(ofSize: 12.5, weight: .medium))
    }

    func testFirstCaseAndAccentInsensitiveSearchMatchIsBoldOnTheStrongTintWithAnAccentUnderline() throws {
        let name = attributed("Résumé résumé.mp4", query: "RESUME")
        var range = NSRange()
        let background = name.attribute(.backgroundColor, at: 0, effectiveRange: &range) as? NSColor
        XCTAssertEqual(background, theme.accentTintStrong)
        XCTAssertEqual(range, NSRange(location: 0, length: 6), "only the first match")
        XCTAssertEqual(name.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(name.attribute(.underlineColor, at: 0, effectiveRange: nil) as? NSColor, theme.accentText)
        XCTAssertEqual(name.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, QueueFonts.namePrefix)
        XCTAssertNil(name.attribute(.backgroundColor, at: 7, effectiveRange: nil), "the second occurrence is not highlighted")
    }

    func testNoMatchLeavesTheNamePlain() {
        let name = attributed("clip.mp4", query: "zzz")
        XCTAssertNil(name.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertEqual(name.string, "clip.mp4")
    }

    func testOverlappingPrefixesColorTheLongerMatchLikeTheRenamer() {
        let overlapping = QueueNameStyle.attributed(for: "a_b_clip.mp4", isCurrent: false, searchQuery: "",
                                                    primaryPrefix: "a_", secondaryPrefix: "a_b_")
        XCTAssertEqual(overlapping.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor, theme.markerSecondary,
                       "the longer secondary prefix is the one present, all four characters")
        XCTAssertEqual(overlapping.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor, DWBColor.textPrimary)
    }

    func testAFailedRowKeepsItsNameInPrimaryText() {
        // §10.4: only the icon and the metadata line change for a failed row.
        XCTAssertEqual(attributed("clip.mp4").attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, DWBColor.textPrimary)
    }

    // MARK: - Metadata and failed rows

    func testMetadataReadsDurationDotSize() {
        XCTAssertEqual(QueueRowTextPresentation.metadata(duration: "5:58", fileSize: "58.5 MB"), "5:58 · 58.5 MB")
        XCTAssertEqual(QueueRowTextPresentation.metadata(duration: "--:--", fileSize: "--"), "--:-- · --")
    }

    func testFailedRowMessageIsTheFullSentenceWhenItFits() {
        let measure: (String) -> CGFloat = { QueueFonts.width(of: $0, font: QueueFonts.metadata) }
        XCTAssertEqual(QueueRowTextPresentation.failedMeta(maxWidth: 400, measure: measure),
                       "Playback failed · Double-click to retry")
    }

    func testFailedRowMessageShortensToItsFirstClauseAtTheMinimumPanel() {
        // 199 pt: card 183 - failed inset 27 - right 10 = 146 pt for the message.
        let card = QueueRowMetrics.cardFrame(rowWidth: 199, isCurrent: false)
        let width = QueueRowMetrics.frames(card: card, isCurrent: false, isFailed: true, hasBookmark: false).meta.width
        XCTAssertEqual(width, 146)
        let measure: (String) -> CGFloat = { QueueFonts.width(of: $0, font: QueueFonts.metadata) }
        let shown = QueueRowTextPresentation.failedMeta(maxWidth: width, measure: measure)
        XCTAssertLessThanOrEqual(measure(shown), width, "no clipped message")
        XCTAssertEqual(shown, "Playback failed")
        // The full sentence stays available for the tooltip and accessibility help.
        XCTAssertEqual(QueueRowTextPresentation.failedMetaFull, "Playback failed · Double-click to retry")
    }

    func testTheFullFailedSentenceFitsFromTheDefaultPanelUp() {
        let measure: (String) -> CGFloat = { QueueFonts.width(of: $0, font: QueueFonts.metadata) }
        for inner: CGFloat in [279, 334, 359] {
            let card = QueueRowMetrics.cardFrame(rowWidth: inner, isCurrent: false)
            let width = QueueRowMetrics.frames(card: card, isCurrent: false, isFailed: true, hasBookmark: false).meta.width
            XCTAssertEqual(QueueRowTextPresentation.failedMeta(maxWidth: width, measure: measure),
                           QueueRowTextPresentation.failedMetaFull, "\(inner)")
        }
    }

    func testMetadataFitsTheMinimumPanelWithoutClipping() {
        // A long, realistic metadata line against the narrowest text column (the playing card's 136 pt).
        let card = QueueRowMetrics.cardFrame(rowWidth: 199, isCurrent: true)
        let width = QueueRowMetrics.frames(card: card, isCurrent: true, isFailed: false, hasBookmark: true).meta.width
        let text = QueueRowTextPresentation.metadata(duration: "12:34:56", fileSize: "123.4 MB")
        XCTAssertLessThanOrEqual(QueueFonts.width(of: text, font: QueueFonts.metadata), width)
    }
}
