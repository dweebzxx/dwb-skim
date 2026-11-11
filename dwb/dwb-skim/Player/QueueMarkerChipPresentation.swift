import Foundation

/// Display state for one footer marker chip (design system "File markers").
///
/// Pure value logic: it owns no views and performs no rename. The chips keep the
/// one-click behavior of the existing prefix buttons; this type only decides what
/// each chip shows and says.
struct QueueMarkerChip: Equatable {
    enum Kind: Equatable {
        case primary
        case secondary
    }

    let kind: Kind
    /// The key that triggers the chip: `N` (primary) or `M` (secondary). Used in tooltips only; no key tag is drawn.
    let keyTag: String
    /// The normalized configured prefix, or "" when blank.
    let prefix: String
    /// The prefix cut to 8 characters with an ellipsis, or "—" when the prefix is blank.
    let label: String
    let isBlank: Bool
    /// The prefix is set and every targeted file already carries it.
    let isApplied: Bool
    /// False when the queue holds no items.
    let queueHasItems: Bool

    /// A blank prefix, or an empty queue, disables the chip.
    var isEnabled: Bool { !isBlank && queueHasItems }

    static let blankLabel = "—"
    static let maximumLabelCharacters = 8
    /// Where the prefix fields live, named in the blank-prefix tooltip.
    static let settingsLocation = "Settings > Queue & Files"

    private var roleName: String { kind == .primary ? "primary" : "secondary" }
    private var otherRoleName: String { kind == .primary ? "secondary" : "primary" }

    var tooltip: String {
        if isBlank { return "No \(roleName) prefix set. Set one in \(Self.settingsLocation)." }
        return "\(roleName.capitalized) prefix “\(prefix)”: add it to the selected file, press again to remove it, "
            + "or replace the \(otherRoleName) prefix. Shortcut: \(keyTag)"
    }

    var accessibilityLabel: String {
        if isBlank { return "\(roleName.capitalized) prefix not set" }
        return "Apply \(roleName) prefix \(prefix) to selected file"
    }

    var accessibilityValue: String { isApplied ? "applied" : "not applied" }

    /// The prefix, cut to `maximumLabelCharacters` with an ellipsis, or "—" when blank.
    /// Pass the normalized prefix the chip applies (`SettingsWindowController.customPrefixValue()`).
    static func label(for prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return blankLabel }
        return trimmed.count <= maximumLabelCharacters
            ? trimmed
            : String(trimmed.prefix(maximumLabelCharacters)) + "…"
    }

    /// The chips to show, primary first.
    ///
    /// The secondary chip is omitted when it repeats the primary prefix, as the footer
    /// buttons already did. A blank prefix keeps its chip, shown as "—" and disabled.
    ///
    /// - Parameter targetNames: The filenames the chips would act on: the selected rows,
    ///   or the current item when nothing is selected.
    /// - Parameter queueHasItems: False disables both chips.
    static func chips(primaryPrefix: String,
                      secondaryPrefix: String,
                      targetNames: [String],
                      queueHasItems: Bool = true) -> [QueueMarkerChip] {
        let primary = primaryPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondary = secondaryPrefix.trimmingCharacters(in: .whitespacesAndNewlines)

        func isApplied(_ kind: Kind, prefix: String) -> Bool {
            guard !prefix.isEmpty, !targetNames.isEmpty else { return false }
            let expected: SkimReviewStatus = kind == .primary ? .primary : .secondary
            // The descriptor resolves overlapping prefixes the same way the renamer does
            // (the longer match is the one present), so a chip never reads as applied
            // when pressing it would replace the other prefix instead.
            return targetNames.allSatisfy {
                SkimReviewStatusDescriptor.describe(displayName: $0,
                                                    primaryPrefix: primary,
                                                    secondaryPrefix: secondary).status == expected
            }
        }

        var result = [
            QueueMarkerChip(kind: .primary,
                            keyTag: "N",
                            prefix: primary,
                            label: label(for: primary),
                            isBlank: primary.isEmpty,
                            isApplied: isApplied(.primary, prefix: primary),
                            queueHasItems: queueHasItems),
        ]
        let duplicatesPrimary = !secondary.isEmpty && secondary == primary
        if !duplicatesPrimary {
            result.append(QueueMarkerChip(kind: .secondary,
                                          keyTag: "M",
                                          prefix: secondary,
                                          label: label(for: secondary),
                                          isBlank: secondary.isEmpty,
                                          isApplied: isApplied(.secondary, prefix: secondary),
                                          queueHasItems: queueHasItems))
        }
        return result
    }
}
