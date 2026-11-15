import Foundation

// MARK: - Log entry

struct DebugLogEntry {
    let date: Date
    let level: DebugLevel
    let category: String
    let message: String
}

// MARK: - Retention rules

/// What the Debug Console keeps in memory, with the console on and off. Nothing is written to disk.
///
/// - Console on: every line goes to the main buffer, which keeps the newest `mainCapacity` lines.
/// - Console off: warnings and errors go to the main buffer. Info lines wait in a context list that
///   keeps the newest `contextCapacity` lines. A warning or error first moves the whole context list
///   into the main buffer, in time order, and then adds itself, so no line is stored twice.
/// - Info lines in `unkeptContextCategory` are never kept as context while the console is off. They
///   are too frequent and would push out everything else. Its warnings are kept like any other.
struct DebugConsoleRetention {

    static let mainCapacity = 5_000
    static let contextCapacity = 400
    static let unkeptContextCategory = "queue-geometry"

    private var main: DebugLogRetentionBuffer<DebugLogEntry>
    private var context: DebugLogRetentionBuffer<DebugLogEntry>

    init(mainCapacity: Int = DebugConsoleRetention.mainCapacity,
         contextCapacity: Int = DebugConsoleRetention.contextCapacity) {
        main = DebugLogRetentionBuffer<DebugLogEntry>(capacity: mainCapacity)
        context = DebugLogRetentionBuffer<DebugLogEntry>(capacity: contextCapacity)
    }

    /// The lines the console shows, oldest first.
    var entries: [DebugLogEntry] { main.entries }

    /// Info lines waiting as context for a later warning or error, oldest first.
    var pendingContextEntries: [DebugLogEntry] { context.entries }

    /// Every category in the main buffer, sorted.
    var categories: [String] { Array(Set(main.entries.map(\.category))).sorted() }

    /// Stores one line. Returns true when the main buffer changed, so a caller can skip all
    /// display work for a line that only joined the context list or was not kept.
    @discardableResult
    mutating func store(_ entry: DebugLogEntry, isConsoleEnabled: Bool) -> Bool {
        if isConsoleEnabled {
            flushContext()
            main.append(entry)
            return true
        }
        if entry.level >= .warning {
            flushContext()
            main.append(entry)
            return true
        }
        if entry.category != Self.unkeptContextCategory {
            context.append(entry)
        }
        return false
    }

    /// Moves the whole context list into the main buffer, in time order.
    mutating func flushContext() {
        let pending = context.entries
        guard !pending.isEmpty else { return }
        for entry in pending { main.append(entry) }
        context.removeAll()
    }

    /// Clears the main buffer and the context list.
    mutating func removeAll() {
        main.removeAll()
        context.removeAll()
    }
}
