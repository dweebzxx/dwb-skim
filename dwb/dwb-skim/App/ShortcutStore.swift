import Foundation

extension Notification.Name {
    /// Posted after any change to the shortcut overrides (edit, remove, restore defaults,
    /// restore all settings). The menu, the Shortcuts page, key hints, and the prefix text refresh.
    static let shortcutsChanged = Notification.Name("com.dwb.skim.shortcutsChanged")
}

/// The keys each command uses now: its default keys, or the override the user saved.
///
/// Overrides live in skim's own `UserDefaults` domain (`com.dwb.skim`; the app uses
/// `UserDefaults.standard` and no shared suite) under one key, `shortcutOverrides`: a dictionary
/// from command identifier to the list of active keys in `ShortcutKey.storageText` form.
/// A command without an entry uses its defaults; an empty list means every key was removed.
final class ShortcutStore {

    static let defaultsKey = "shortcutOverrides"
    static let shared = ShortcutStore(defaults: .standard)

    private let defaults: UserDefaults
    private var cache: [ShortcutCommandID: [ShortcutKey]]?

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: Reading

    /// The overrides on disk. Unknown identifiers, fixed commands, and unreadable keys are
    /// ignored; an entry whose keys are all unreadable is ignored whole, so the defaults apply.
    static func readOverrides(from defaults: UserDefaults) -> [ShortcutCommandID: [ShortcutKey]] {
        guard let stored = defaults.dictionary(forKey: defaultsKey) else { return [:] }
        var result: [ShortcutCommandID: [ShortcutKey]] = [:]
        for (identifier, value) in stored {
            guard let id = ShortcutCommandID(rawValue: identifier),
                  ShortcutCommandTable.command(id).isEditable,
                  let texts = value as? [String] else { continue }
            let keys = texts.compactMap(ShortcutKey.init(storageText:)).filter(\.isRecordable)
            if keys.isEmpty && !texts.isEmpty { continue }
            result[id] = deduplicated(keys)
        }
        return result
    }

    private var overrides: [ShortcutCommandID: [ShortcutKey]] {
        if let cache { return cache }
        let loaded = Self.readOverrides(from: defaults)
        cache = loaded
        return loaded
    }

    /// The keys the command uses now, in order.
    func activeKeys(for id: ShortcutCommandID) -> [ShortcutKey] {
        overrides[id] ?? ShortcutCommandTable.command(id).defaultKeys
    }

    /// Menu equivalents in display order; the first belongs to the visible item.
    func menuKeys(for id: ShortcutCommandID) -> [ShortcutKey] {
        let command = ShortcutCommandTable.command(id)
        return activeKeys(for: id).filter { command.route(for: $0) == .menu }
    }

    /// Every command's active keys.
    var allActiveKeys: [ShortcutCommandID: [ShortcutKey]] {
        Dictionary(uniqueKeysWithValues: ShortcutCommandID.allCases.map { ($0, activeKeys(for: $0)) })
    }

    var hasOverrides: Bool { !overrides.isEmpty }

    // MARK: Writing

    /// Saves `keys` for an editable command. Keys equal to the defaults remove the override.
    func setKeys(_ keys: [ShortcutKey], for id: ShortcutCommandID) {
        let command = ShortcutCommandTable.command(id)
        guard command.isEditable else { return }
        var updated = overrides
        let unique = Self.deduplicated(keys)
        if unique == command.defaultKeys {
            updated[id] = nil
        } else {
            updated[id] = unique
        }
        write(updated)
    }

    /// Replaces `old` with `new`, removes `old` when `new` is `nil`, or appends `new` when
    /// `old` is `nil`. The command's other keys stay.
    func replaceKey(_ old: ShortcutKey?, with new: ShortcutKey?, for id: ShortcutCommandID) {
        var keys = activeKeys(for: id)
        switch (old, new) {
        case let (old?, new?):
            if let index = keys.firstIndex(of: old) { keys[index] = new } else { keys.append(new) }
        case let (old?, nil):
            keys.removeAll { $0 == old }
        case let (nil, new?):
            keys.append(new)
        case (nil, nil):
            return
        }
        setKeys(keys, for: id)
    }

    /// Removes every override. Nothing else in `UserDefaults` changes.
    func restoreDefaults() {
        Self.clearOverrides(in: defaults)
        cache = [:]
        NotificationCenter.default.post(name: .shortcutsChanged, object: self)
    }

    /// Removes the stored overrides from `defaults`: the part of "Restore Default Settings"
    /// that covers shortcuts.
    static func clearOverrides(in defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// Forgets what was read, so the next read comes from `UserDefaults`.
    func reload() {
        cache = nil
        NotificationCenter.default.post(name: .shortcutsChanged, object: self)
    }

    private func write(_ updated: [ShortcutCommandID: [ShortcutKey]]) {
        if updated.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(Dictionary(uniqueKeysWithValues: updated.map { ($0.key.rawValue, $0.value.map(\.storageText)) }),
                         forKey: Self.defaultsKey)
        }
        cache = updated
        NotificationCenter.default.post(name: .shortcutsChanged, object: self)
    }

    private static func deduplicated(_ keys: [ShortcutKey]) -> [ShortcutKey] {
        var seen = Set<ShortcutKey>()
        return keys.filter { seen.insert($0).inserted }
    }
}

// MARK: - Key hints

/// Tooltip and help text that names a command's key, written from the active keys.
enum ShortcutHints {

    /// The first active key of `id` as a key cap (`Q`, `\u{2318}Space`), or `nil` when unassigned.
    static func keyText(for id: ShortcutCommandID, store: ShortcutStore = .shared) -> String? {
        store.activeKeys(for: id).first?.capText
    }

    /// `Toggle queue panel (Q)`, or just `Toggle queue panel` when the command has no key.
    static func help(_ base: String, for id: ShortcutCommandID, store: ShortcutStore = .shared) -> String {
        guard let key = keyText(for: id, store: store) else { return base }
        return "\(base) (\(key))"
    }
}
