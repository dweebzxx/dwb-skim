import AppKit

// A keyboard shortcut as skim stores, matches, and shows it: modifiers plus one key.
//
// `key` is the character the dispatch sees (`charactersIgnoringModifiers`, lowercased), with
// the same function-key characters AppKit uses for the arrows and Delete. That one string
// is what `handleSkimShortcut` compares and what a menu item takes as its `keyEquivalent`,
// so a key follows the user's keyboard layout exactly as it did before shortcuts were editable.

/// ⌃ ⌥ ⇧ ⌘, in the standard display order.
struct ShortcutModifiers: OptionSet, Hashable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    static let control = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let shift = ShortcutModifiers(rawValue: 1 << 2)
    static let command = ShortcutModifiers(rawValue: 1 << 3)

    private static let ordered: [(modifier: ShortcutModifiers, symbol: String, word: String, token: String)] = [
        (.control, "\u{2303}", "Control", "control"),
        (.option, "\u{2325}", "Option", "option"),
        (.shift, "\u{21E7}", "Shift", "shift"),
        (.command, "\u{2318}", "Command", "command"),
    ]

    /// ⌘, ⌃, or ⌥ is held. Only these send a key to the menu bar; Shift alone never does.
    var hasMenuModifier: Bool { !isDisjoint(with: [.control, .option, .command]) }

    var symbols: String { Self.ordered.filter { contains($0.modifier) }.map(\.symbol).joined() }
    var spokenWords: [String] { Self.ordered.filter { contains($0.modifier) }.map(\.word) }
    var storageTokens: [String] { Self.ordered.filter { contains($0.modifier) }.map(\.token) }

    static func modifier(forToken token: String) -> ShortcutModifiers? {
        ordered.first { $0.token == token }?.modifier
    }

    /// The four modifiers a shortcut can use, from an event's flags. Caps Lock, Fn, and the
    /// numeric-pad flag arrow keys carry are ignored, as the existing dispatch ignores them.
    init(eventFlags flags: NSEvent.ModifierFlags) {
        var result: ShortcutModifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.control) { flags.insert(.control) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.command) { flags.insert(.command) }
        return flags
    }
}

struct ShortcutKey: Hashable {
    var modifiers: ShortcutModifiers
    /// The key character; empty when only modifiers are held.
    var key: String

    init(modifiers: ShortcutModifiers = [], key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    /// A key with no modifiers, as the existing table stores them.
    static func bare(_ key: String) -> ShortcutKey { ShortcutKey(key: key) }

    var isModifierOnly: Bool { key.isEmpty }
    /// Reaches the player window's key handler: no modifier at all.
    var usesKeyHandler: Bool { !isModifierOnly && modifiers.isEmpty }
    /// Reaches a menu item's key equivalent: ⌘, ⌃, or ⌥ with a key.
    var usesMenu: Bool { !isModifierOnly && modifiers.hasMenuModifier }

    /// The base keys the recorder can capture. Modified invalid combinations still reach
    /// validation so the editor can show its inline message.
    var hasRecordableBase: Bool {
        let special = [Self.space, Self.leftArrow, Self.rightArrow, Self.upArrow,
                       Self.downArrow, Self.delete, Self.forwardDelete]
        let printable = key.count == 1 && key.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
                || CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
        }
        return special.contains(key) || printable
    }

    /// The suite rule for keys saved by the editor or read from an override.
    var isRecordable: Bool {
        guard hasRecordableBase else { return false }
        guard modifiers.isEmpty || modifiers.hasMenuModifier else { return false }
        if modifiers.contains(.shift) && ![Self.space, Self.leftArrow, Self.rightArrow, Self.upArrow,
                                          Self.downArrow, Self.delete, Self.forwardDelete].contains(key) {
            return key.count == 1 && key.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        }
        return true
    }

    // MARK: Key characters

    static let space = " "
    static let leftArrow = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    static let rightArrow = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    static let upArrow = String(UnicodeScalar(NSUpArrowFunctionKey)!)
    static let downArrow = String(UnicodeScalar(NSDownArrowFunctionKey)!)
    /// Delete (backspace) as `charactersIgnoringModifiers` and a menu's `keyEquivalent` write it.
    static let delete = String(UnicodeScalar(NSDeleteCharacter)!)
    static let forwardDelete = String(UnicodeScalar(NSDeleteFunctionKey)!)
    static let returnKey = "\r"
    static let enter = "\u{3}"
    static let tab = "\t"
    static let escape = "\u{1B}"
    static let home = String(UnicodeScalar(NSHomeFunctionKey)!)
    static let end = String(UnicodeScalar(NSEndFunctionKey)!)
    static let pageUp = String(UnicodeScalar(NSPageUpFunctionKey)!)
    static let pageDown = String(UnicodeScalar(NSPageDownFunctionKey)!)

    private static func functionKey(_ number: Int) -> String {
        String(UnicodeScalar(NSF1FunctionKey + number - 1)!)
    }

    /// Named keys: storage name, key character, key-cap glyph, spoken name.
    private static let namedKeys: [(name: String, key: String, cap: String, spoken: String)] = {
        var keys: [(name: String, key: String, cap: String, spoken: String)] = [
            ("space", space, "Space", "Space"),
            ("left", leftArrow, "\u{2190}", "Left Arrow"),
            ("right", rightArrow, "\u{2192}", "Right Arrow"),
            ("up", upArrow, "\u{2191}", "Up Arrow"),
            ("down", downArrow, "\u{2193}", "Down Arrow"),
            ("return", returnKey, "\u{21A9}", "Return"),
            ("enter", enter, "\u{2324}", "Enter"),
            ("tab", tab, "\u{21E5}", "Tab"),
            ("delete", delete, "\u{232B}", "Delete"),
            ("forwarddelete", forwardDelete, "\u{2326}", "Forward Delete"),
            ("home", home, "\u{2196}", "Home"),
            ("end", end, "\u{2198}", "End"),
            ("pageup", pageUp, "\u{21DE}", "Page Up"),
            ("pagedown", pageDown, "\u{21DF}", "Page Down"),
            ("escape", escape, "\u{238B}", "Escape"),
        ]
        for number in 1...20 {
            keys.append(("f\(number)", functionKey(number), "F\(number)", "F\(number)"))
        }
        return keys
    }()

    private static let punctuationNames: [String: String] = [
        ",": "Comma", ".": "Period", "/": "Slash", "\\": "Backslash", ";": "Semicolon",
        "'": "Quote", "[": "Left Bracket", "]": "Right Bracket", "-": "Minus", "=": "Equals",
        "`": "Grave Accent",
    ]

    /// Key codes that identify non-printing keys regardless of layout, as characters.
    private static let specialKeyCodes: [UInt16: String] = {
        var codes: [UInt16: String] = [
            49: space, 123: leftArrow, 124: rightArrow, 125: downArrow, 126: upArrow,
            36: returnKey, 76: enter, 48: tab, 51: delete, 117: forwardDelete,
            115: home, 119: end, 116: pageUp, 121: pageDown, 53: escape,
        ]
        let functionKeyCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                                          105, 107, 113, 106, 64, 79, 80, 90]
        for (index, code) in functionKeyCodes.enumerated() { codes[code] = functionKey(index + 1) }
        return codes
    }()

    /// The key an event presses, or `nil` when it has no usable key (a dead key, say).
    /// `characters` is the key's character with no modifier applied
    /// (`event.characters(byApplyingModifiers: [])`); key codes decide Space, the arrows and
    /// the other non-printing keys.
    static func key(keyCode: UInt16, characters: String?) -> String? {
        if let special = specialKeyCodes[keyCode] { return special }
        guard let text = characters?.lowercased(), text.count == 1,
              let scalar = text.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F else { return nil }
        return text
    }

    /// A recorded or dispatched key press.
    static func recorded(keyCode: UInt16,
                         characters: String?,
                         modifiers: ShortcutModifiers) -> ShortcutKey? {
        guard let key = key(keyCode: keyCode, characters: characters) else { return nil }
        let candidate = ShortcutKey(modifiers: modifiers, key: key)
        return candidate.hasRecordableBase ? candidate : nil
    }

    // MARK: Notation

    /// The key as it reads on a key cap: modifier symbols in the order ⌃ ⌥ ⇧ ⌘, then the key.
    var capText: String { modifiers.symbols + Self.keyCapText(key) }

    /// The key as words, for VoiceOver and search: `Shift-Command-R`.
    var spokenText: String {
        (modifiers.spokenWords + (isModifierOnly ? [] : [Self.spokenName(key)])).joined(separator: "-")
    }

    /// The text search matches: the cap and the spoken form.
    var searchText: String { "\(capText) \(spokenText)" }

    static func keyCapText(_ key: String) -> String {
        if let named = namedKeys.first(where: { $0.key == key }) { return named.cap }
        return key.uppercased()
    }

    static func spokenName(_ key: String) -> String {
        if let named = namedKeys.first(where: { $0.key == key }) { return named.spoken }
        return punctuationNames[key] ?? key.uppercased()
    }

    // MARK: Storage

    /// The form kept in `shortcutOverrides`: lowercase modifier names, then the key, joined by
    /// `+`. Examples: `n`, `space`, `command+space`, `shift+command+r`, `command++`.
    var storageText: String {
        let name = Self.namedKeys.first(where: { $0.key == key })?.name ?? key
        return (modifiers.storageTokens + [name]).joined(separator: "+")
    }

    init?(storageText text: String) {
        var rest = Substring(text)
        var modifiers: ShortcutModifiers = []
        while let plus = rest.firstIndex(of: "+"), plus != rest.startIndex,
              let modifier = ShortcutModifiers.modifier(forToken: String(rest[rest.startIndex..<plus])) {
            modifiers.insert(modifier)
            rest = rest[rest.index(after: plus)...]
        }
        let name = String(rest)
        guard !name.isEmpty else { return nil }
        if let named = Self.namedKeys.first(where: { $0.name == name.lowercased() }) {
            self.init(modifiers: modifiers, key: named.key)
        } else if name.count == 1, let scalar = name.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F {
            self.init(modifiers: modifiers, key: name.lowercased())
        } else {
            return nil
        }
    }
}
