import Foundation

/// One row of Settings > Shortcuts: one command, with every key it uses now.
struct ShortcutRow: Equatable {
    typealias Tone = ShortcutCommand.Tone

    let commandID: ShortcutCommandID
    /// The action name.
    let title: String
    let groupTitle: String
    /// Context text shown in the row: when the action applies. `nil` for unconditional actions.
    let contextText: String?
    /// The keys the action uses now, in order. Empty for an unassigned or gesture action.
    let keys: [ShortcutKey]
    /// A gesture shown as a single cap in place of keys ("Double-tap Option").
    let gestureText: String?
    let isEditable: Bool
    let tone: Tone

    init(command: ShortcutCommand, keys: [ShortcutKey]) {
        commandID = command.id
        title = command.name
        groupTitle = command.group.rawValue
        contextText = command.contextText
        self.keys = keys
        gestureText = command.gestureText
        isEditable = command.isEditable
        tone = command.tone
    }

    /// The key caps drawn at the end of the row, in `ShortcutKey.capText` notation.
    var caps: [String] {
        if let gestureText { return [gestureText] }
        return keys.map(\.capText)
    }

    /// The keys as words ("Command-Z"), for VoiceOver and search.
    var spoken: String {
        if let gestureText { return gestureText }
        return keys.isEmpty ? Self.unassignedText : keys.map(\.spokenText).joined(separator: ", ")
    }

    /// An editable action with no key.
    var isUnassigned: Bool { isEditable && keys.isEmpty && gestureText == nil }

    /// The keyboard-map keys this row lights. Only an unmodified key that is on the map.
    var mapKeys: [String] {
        keys.compactMap { key in
            guard key.usesKeyHandler else { return nil }
            let name = ShortcutsPresentation.mapName(forKey: key.key)
            return ShortcutsPresentation.mapKeySet.contains(name) ? name : nil
        }
    }

    var accessibilityLabel: String { "\(title), \(spoken)" }

    static let unassignedText = "Unassigned"

    /// Everything search reads: the action, its group, its keys (symbols and words), and its context.
    var searchText: String {
        var parts = [title, groupTitle]
        if let gestureText {
            parts.append(gestureText)
        } else {
            parts.append(contentsOf: keys.map(\.searchText))
            if keys.isEmpty { parts.append(Self.unassignedText) }
        }
        if let contextText { parts.append(contextText) }
        return parts.joined(separator: " ").lowercased()
    }
}

/// A titled group of shortcut rows.
struct ShortcutGroup: Equatable {
    let title: String
    let rows: [ShortcutRow]
}

/// The grouping, search, and keyboard-map data for Settings > Shortcuts. Pure data: it owns no
/// views, and it takes every key from `ShortcutCommandTable` and `ShortcutStore`.
enum ShortcutsPresentation {
    static let arrowLeft = "\u{2190}"
    static let arrowRight = "\u{2192}"
    static let arrowUp = "\u{2191}"
    static let arrowDown = "\u{2193}"

    static let pageDescription = "Find and customize keyboard shortcuts for this app."
    static let scopeText = "Changes apply only to dwb skim."
    static let searchLabel = "Search shortcuts"
    static let restoreDefaultsTitle = "Restore Defaults\u{2026}"
    static let restoreConfirmTitle = "Restore default shortcuts for dwb skim?"
    static let restoreConfirmMessage = "This resets every keyboard shortcut in dwb skim to its default. No other setting changes."
    static let restoreConfirmAction = "Restore Defaults"
    static let noMatchesText = "No matching shortcuts."

    /// Group titles, in page order.
    static var groupTitles: [String] { ShortcutCommandTable.groups.map(\.group.rawValue) }

    /// Every command, grouped by task, with the keys in use now.
    static func groups(store: ShortcutStore = .shared) -> [ShortcutGroup] {
        ShortcutCommandTable.groups.map { entry in
            ShortcutGroup(title: entry.group.rawValue,
                          rows: entry.commands.map { ShortcutRow(command: $0, keys: store.activeKeys(for: $0.id)) })
        }
    }

    // MARK: - Search

    /// The groups with only the rows that match `query` in the action name, group name, a key
    /// (symbol or words), or the context text. A blank query keeps everything; groups left
    /// empty are dropped. Several words must each appear somewhere in the row.
    static func filtered(_ groups: [ShortcutGroup], query: String) -> [ShortcutGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return groups }
        let words = needle.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        return groups.compactMap { group in
            let rows = group.rows.filter { matches($0, needle: needle, words: words) }
            return rows.isEmpty ? nil : ShortcutGroup(title: group.title, rows: rows)
        }
    }

    private static func matches(_ row: ShortcutRow, needle: String, words: [String]) -> Bool {
        let haystack = row.searchText
        if haystack.contains(needle) { return true }
        // A multi-word query ("command shift r") matches when each word starts a word of the row.
        guard words.count > 1 else { return false }
        let rowWords = haystack.split(whereSeparator: { $0 == " " || $0 == "-" })
        return words.allSatisfy { word in rowWords.contains { $0.hasPrefix(word) } }
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

    /// The map's name for a key character: capitals for letters, "Space", and the arrow glyphs.
    static func mapName(forKey key: String) -> String {
        switch key {
        case ShortcutKey.space: return mapSpaceKey
        case ShortcutKey.leftArrow: return arrowLeft
        case ShortcutKey.rightArrow: return arrowRight
        case ShortcutKey.upArrow: return arrowUp
        case ShortcutKey.downArrow: return arrowDown
        default: return key.uppercased()
        }
    }

    /// The tone each used map key takes: the primary and secondary prefix keys take the marker
    /// colors, every other used key the accent.
    static func mapTones(in groups: [ShortcutGroup]) -> [String: ShortcutRow.Tone] {
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
