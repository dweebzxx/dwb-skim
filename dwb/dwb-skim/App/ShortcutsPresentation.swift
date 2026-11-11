import Foundation

/// One row of Settings > Shortcuts.
struct ShortcutRow: Equatable {
    enum Tone: Equatable {
        case accent
        case markerPrimary
        case markerSecondary
    }

    /// The action name. These are the titles the page has always shown.
    let title: String
    /// The keys as words ("Command-Z"). Used for accessibility and for search.
    let spoken: String
    /// The key caps drawn at the end of the row ("⌘Z").
    let caps: [String]
    /// The keyboard-map keys this row lights up. Empty for chords and modifier gestures.
    let mapKeys: [String]
    let tone: Tone

    init(_ title: String, _ spoken: String, tone: Tone = .accent) {
        self.title = title
        self.spoken = spoken
        self.caps = [ShortcutsPresentation.capText(forSpoken: spoken)]
        self.mapKeys = ShortcutsPresentation.mapKeySet.contains(spoken) ? [spoken] : []
        self.tone = tone
    }

    var accessibilityLabel: String { "\(title), \(spoken)" }
}

/// A titled group of shortcut rows.
struct ShortcutGroup: Equatable {
    let title: String
    let rows: [ShortcutRow]
}

/// The grouping, search, and keyboard-map data for Settings > Shortcuts
/// (design system `ShortcutsPage`). Pure data: it owns no views.
enum ShortcutsPresentation {
    static let arrowLeft = "\u{2190}"
    static let arrowRight = "\u{2192}"
    static let arrowUp = "\u{2191}"
    static let arrowDown = "\u{2193}"

    /// Group titles, in page order.
    static let groupTitles = ["Playback", "Navigation", "File markers", "Queue & window", "dwb skim only"]

    /// Every shortcut the page has listed, grouped by task rather than by window.
    static let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Playback", rows: [
            ShortcutRow("Play/Pause", "Space"),
            ShortcutRow("Seek backward 10 seconds", arrowLeft),
            ShortcutRow("Seek forward 10 seconds", arrowRight),
            ShortcutRow("Play / Pause", "Command-Space"),
            ShortcutRow("Volume Up", "Command-\(arrowUp)"),
            ShortcutRow("Volume Down", "Command-\(arrowDown)"),
        ]),
        ShortcutGroup(title: "Navigation", rows: [
            ShortcutRow("Previous item", ","),
            ShortcutRow("Next item", "."),
        ]),
        ShortcutGroup(title: "File markers", rows: [
            ShortcutRow("Primary prefix (add / remove / replace)", "N", tone: .markerPrimary),
            ShortcutRow("Secondary prefix (add / remove / replace)", "M", tone: .markerSecondary),
            ShortcutRow("Rename current file\u{2026}", "R"),
            ShortcutRow("Undo last prefix change", "Command-Z"),
            ShortcutRow("Bookmark", "B"),
        ]),
        ShortcutGroup(title: "Queue & window", rows: [
            ShortcutRow("Toggle queue panel", "Q"),
            ShortcutRow("Fullscreen", "F"),
            ShortcutRow("Open\u{2026}", "Command-O"),
            ShortcutRow("New Window", "Command-N"),
            ShortcutRow("Four Window Grid", "Command-4"),
            ShortcutRow("Settings\u{2026}", "Command-,"),
            ShortcutRow("Close", "Command-W"),
            ShortcutRow("Minimize", "Command-M"),
            ShortcutRow("Quit dwb skim", "Command-Q"),
            ShortcutRow("Reveal in Finder", "Command-Shift-R"),
            ShortcutRow("Clear Queue", "Command-Shift-Delete"),
            ShortcutRow("Fit", "Command-1"),
            ShortcutRow("Fill", "Command-2"),
            ShortcutRow("Stretch", "Command-3"),
        ]),
        ShortcutGroup(title: "dwb skim only", rows: [
            ShortcutRow("Toggle Skim", "Double-tap Option"),
            ShortcutRow("Next Progressive Random Skim segment", arrowRight),
        ]),
    ]

    // MARK: - Search

    /// The groups with only the rows that match `query` in the action name or a key.
    /// A blank query keeps everything; groups left empty are dropped.
    static func filtered(_ groups: [ShortcutGroup], query: String) -> [ShortcutGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return groups }
        return groups.compactMap { group in
            let rows = group.rows.filter { matches($0, needle: needle) }
            return rows.isEmpty ? nil : ShortcutGroup(title: group.title, rows: rows)
        }
    }

    private static func matches(_ row: ShortcutRow, needle: String) -> Bool {
        let haystack = ([row.title, row.spoken] + row.caps).joined(separator: " ").lowercased()
        return haystack.contains(needle)
    }

    // MARK: - Key caps

    /// "Command-Shift-Delete" as "⌘⇧⌫". Words that are not modifier chords pass through.
    static func capText(forSpoken spoken: String) -> String {
        let modifiers: [(word: String, glyph: String)] = [
            ("Command-", "\u{2318}"), ("Shift-", "\u{21E7}"), ("Option-", "\u{2325}"), ("Control-", "\u{2303}"),
        ]
        var rest = spoken
        var glyphs = ""
        var matched = true
        while matched {
            matched = false
            for modifier in modifiers where rest.hasPrefix(modifier.word) {
                glyphs += modifier.glyph
                rest.removeFirst(modifier.word.count)
                matched = true
            }
        }
        if rest == "Delete", !glyphs.isEmpty { rest = "\u{232B}" }
        return glyphs + rest
    }

    // MARK: - Keyboard map

    /// The QWERTY rows the map draws, top to bottom. The space bar and arrows follow.
    static let mapLetterRows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M", ",", "."],
    ]
    static let mapSpaceKey = "Space"
    static let mapArrowKeys = [arrowLeft, arrowUp, arrowDown, arrowRight]

    static let mapKeySet: Set<String> = Set(mapLetterRows.flatMap { $0 } + [mapSpaceKey] + mapArrowKeys)

    /// The tone each used map key takes: `N` and `M` take the marker colors, every other
    /// used key the accent.
    static func mapTones(in groups: [ShortcutGroup] = ShortcutsPresentation.groups) -> [String: ShortcutRow.Tone] {
        var tones: [String: ShortcutRow.Tone] = [:]
        for row in groups.flatMap({ $0.rows }) {
            for key in row.mapKeys {
                if row.tone != .accent {
                    tones[key] = row.tone
                } else if tones[key] == nil {
                    tones[key] = .accent
                }
            }
        }
        return tones
    }
}
