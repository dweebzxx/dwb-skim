import Foundation

/// Display state for one footer marker cell (design system sections 5 "File markers" and 10.5).
///
/// Pure value logic: it owns no views and performs no rename. The cells keep the one-click
/// behavior of the existing prefix buttons; this type only decides what each cell shows and says.
struct QueueMarkerChip: Equatable {
    enum Kind: Equatable {
        case primary
        case secondary
    }

    /// The mark in a marker cell's top-right corner: never a fill.
    enum MarkState: Equatable {
        /// No targeted file carries the prefix (or nothing is targeted).
        case none
        /// Every targeted file carries the prefix: a 4 pt dot.
        case applied
        /// Some, not all, targeted files carry it: a 4 pt ring.
        case mixed
    }

    let kind: Kind
    /// The key that triggers the chip: `N` (primary) or `M` (secondary). Used in tooltips and the accessible name only.
    let keyTag: String
    /// The normalized configured prefix, or "" when blank.
    let prefix: String
    /// The whole prefix, or "—" when it is blank. The cell shortens it by measurement; the full prefix
    /// stays in `prefix`, the tooltip and the accessibility label.
    let label: String
    let isBlank: Bool
    /// What the targeted files carry, from the same classifier the renamer and the row colors use.
    let markState: MarkState
    /// False when the queue holds no items.
    let queueHasItems: Bool
    /// False when nothing is targeted: no selection, and no visible current item.
    var hasTargets: Bool = true

    /// The prefix is set and every targeted file already carries it.
    var isApplied: Bool { markState == .applied }
    /// The prefix is on some, not all, targeted files.
    var isMixed: Bool { markState == .mixed }

    /// A blank prefix, an empty queue, or nothing targeted disables the chip.
    var isEnabled: Bool { !isBlank && queueHasItems && hasTargets }

    static let blankLabel = "—"
    /// Where the prefix fields live, named in the blank-prefix tooltip.
    static let settingsLocation = "Settings > Queue & Files"

    private var roleName: String { kind == .primary ? "primary" : "secondary" }
    private var otherRoleName: String { kind == .primary ? "secondary" : "primary" }

    var tooltip: String {
        if isBlank { return "No \(roleName) prefix set. Set one in \(Self.settingsLocation)." }
        var text = "\(roleName.capitalized) prefix “\(prefix)”: add it to the selected file, press again to remove it, "
            + "or replace the \(otherRoleName) prefix. Shortcut: \(keyTag)"
        if markState == .mixed { text += ". Some of the targeted files already have it." }
        return text
    }

    var accessibilityLabel: String {
        if isBlank { return "\(roleName.capitalized) prefix not set" }
        return "Apply \(roleName) prefix \(prefix) to selected file, shortcut \(keyTag)"
    }

    var accessibilityValue: String {
        switch markState {
        case .none: return "not applied"
        case .applied: return "applied"
        case .mixed: return "mixed, applied to some files"
        }
    }

    /// The prefix, or "—" when blank. No fixed cut: the cell fits it to its own section by measuring.
    /// Pass the normalized prefix the chip applies (`SettingsWindowController.customPrefixValue()`).
    static func label(for prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? blankLabel : trimmed
    }

    /// The chips to show, primary first.
    ///
    /// The secondary chip is omitted when it repeats the primary prefix, as the footer
    /// buttons already did; its grid position stays empty. A blank prefix keeps its chip, shown as "—" and disabled.
    ///
    /// - Parameter targetNames: The filenames the chips would act on: the selected rows,
    ///   or the current item when nothing is selected. The mark describes exactly these.
    /// - Parameter queueHasItems: False disables both chips.
    /// - Parameter hasTargets: False (nothing selected and no visible current item) disables both chips.
    static func chips(primaryPrefix: String,
                      secondaryPrefix: String,
                      targetNames: [String],
                      queueHasItems: Bool = true,
                      hasTargets: Bool = true) -> [QueueMarkerChip] {
        let primary = primaryPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondary = secondaryPrefix.trimmingCharacters(in: .whitespacesAndNewlines)

        func markState(_ kind: Kind, prefix: String) -> MarkState {
            guard !prefix.isEmpty, !targetNames.isEmpty else { return .none }
            let expected: SkimReviewStatus = kind == .primary ? .primary : .secondary
            // The descriptor resolves overlapping prefixes the same way the renamer does
            // (the longer match is the one present), so a chip never reads as applied
            // when pressing it would replace the other prefix instead.
            let carrying = targetNames.filter {
                SkimReviewStatusDescriptor.describe(displayName: $0,
                                                    primaryPrefix: primary,
                                                    secondaryPrefix: secondary).status == expected
            }.count
            if carrying == 0 { return .none }
            return carrying == targetNames.count ? .applied : .mixed
        }

        var result = [
            QueueMarkerChip(kind: .primary,
                            keyTag: "N",
                            prefix: primary,
                            label: label(for: primary),
                            isBlank: primary.isEmpty,
                            markState: markState(.primary, prefix: primary),
                            queueHasItems: queueHasItems,
                            hasTargets: hasTargets),
        ]
        let duplicatesPrimary = !secondary.isEmpty && secondary == primary
        if !duplicatesPrimary {
            result.append(QueueMarkerChip(kind: .secondary,
                                          keyTag: "M",
                                          prefix: secondary,
                                          label: label(for: secondary),
                                          isBlank: secondary.isEmpty,
                                          markState: markState(.secondary, prefix: secondary),
                                          queueHasItems: queueHasItems,
                                          hasTargets: hasTargets))
        }
        return result
    }
}
