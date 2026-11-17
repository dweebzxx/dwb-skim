import Foundation

/// What the editor sheet decides about a recorded key.
enum ShortcutKeyValidation: Equatable {
    case valid
    /// The key cannot run this action (a modifier alone, or a key its route cannot deliver).
    case invalid
    /// Another command already uses the key in a context that can be active at the same time.
    case conflict(with: ShortcutCommandID)

    static let invalidMessage = "This key combination can\u{2019}t be used for this action."

    /// `Already assigned to ‘Next item’ in this context.`
    static func conflictMessage(actionName: String) -> String {
        "Already assigned to \u{2018}\(actionName)\u{2019} in this context."
    }

    var message: String? {
        switch self {
        case .valid: return nil
        case .invalid: return Self.invalidMessage
        case .conflict(let id): return Self.conflictMessage(actionName: ShortcutCommandTable.command(id).name)
        }
    }

    var allowsSave: Bool { self == .valid }
}

enum ShortcutValidation {

    /// Checks `candidate` as a key for `id`. `replacing` is the key being edited, which leaves
    /// the command's own list while the candidate is checked. `keysByCommand` holds every
    /// command's active keys.
    ///
    /// The order follows the editor: a modifier alone is invalid; then a key another command
    /// uses in an overlapping context is a conflict (also when this command could not
    /// deliver the key); then a key this command cannot deliver is invalid.
    static func evaluate(_ candidate: ShortcutKey,
                         for id: ShortcutCommandID,
                         replacing: ShortcutKey?,
                         keysByCommand: [ShortcutCommandID: [ShortcutKey]]) -> ShortcutKeyValidation {
        guard candidate.isRecordable else { return .invalid }

        // These Edit keys are reserved even where a text field is not currently focused.
        let reserved: [ShortcutCommandID] = [.undoTyping, .redoTyping, .cut, .copy, .paste, .selectAll]
        if let owner = reserved.first(where: { ShortcutCommandTable.command($0).defaultKeys.contains(candidate) }) {
            return .conflict(with: owner)
        }

        let command = ShortcutCommandTable.command(id)
        let context = command.context(for: candidate)
        for other in ShortcutCommandTable.all where other.id != id {
            let keys = keysByCommand[other.id] ?? other.defaultKeys
            guard keys.contains(candidate) else { continue }
            if context.overlaps(other.context(for: candidate)) { return .conflict(with: other.id) }
        }

        guard canDeliver(candidate, to: command, otherKeys: []) else { return .invalid }
        return .valid
    }

    /// Whether either route can run `key`. The number of other keys does not limit a command.
    static func canDeliver(_ key: ShortcutKey, to command: ShortcutCommand, otherKeys: [ShortcutKey]) -> Bool {
        command.route(for: key) != .invalid
    }

    /// Convenience for a store.
    static func evaluate(_ candidate: ShortcutKey,
                         for id: ShortcutCommandID,
                         replacing: ShortcutKey?,
                         store: ShortcutStore) -> ShortcutKeyValidation {
        evaluate(candidate, for: id, replacing: replacing, keysByCommand: store.allActiveKeys)
    }
}
