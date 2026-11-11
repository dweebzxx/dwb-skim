import Foundation

/// Copy for the undo toast shown after a prefix change (design system 9.4).
///
/// Only prefix actions create an undo step (SD-023); a rename made from the rename sheet shows no
/// toast, so this type carries no source.
struct UndoToastPresentation: Equatable {
    enum Content: Equatable {
        /// One file: "Prefix changed:" plus its new filename.
        case file(name: String)
        /// Several files: "Prefix changed on N files", never the filenames.
        case batch(count: Int)
    }

    let content: Content

    init(step: SkimMarkerRenameUndoStep) {
        if step.moves.count == 1, let move = step.moves.first {
            content = .file(name: move.destination.lastPathComponent)
        } else {
            content = .batch(count: step.moves.count)
        }
    }

    var leadingText: String {
        switch content {
        case .file: return "Prefix changed:"
        case .batch: return "Prefix changed on"
        }
    }

    /// The value after `leadingText`: the new filename, or "N files".
    var valueText: String {
        switch content {
        case .file(let name): return name
        case .batch(let count): return "\(count) files"
        }
    }

    /// The spoken text: "Prefix changed on <filename>. Undo with Command Z." or
    /// "Prefix changed on N files. Undo with Command Z."
    var announcement: String {
        switch content {
        case .file(let name): return "Prefix changed on \(name). Undo with Command Z."
        case .batch(let count): return "Prefix changed on \(count) files. Undo with Command Z."
        }
    }
}
