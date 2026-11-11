import Foundation

/// One same-directory file move: `source` is renamed to `destination`.
struct SkimMarkerRenameMove: Equatable {
    let source: URL
    let destination: URL

    var isNoOp: Bool {
        source.standardizedFileURL.path == destination.standardizedFileURL.path
    }

    var inverse: SkimMarkerRenameMove {
        SkimMarkerRenameMove(source: destination, destination: source)
    }
}

/// The single undo step of one player window: every file moved by its most
/// recent marker rename (`N`/`M` primary or secondary prefix). A multi-file
/// marker rename is one step. Manual renames never create a step (SD-023).
struct SkimMarkerRenameUndoStep: Equatable {
    /// The forward moves, in the order they were performed.
    let moves: [SkimMarkerRenameMove]
}

/// Why an undo was refused. Messages are skim's existing "Cannot Undo" wording.
enum SkimMarkerRenameUndoRefusal: Error, Equatable {
    case renamedFileMissing
    case originalNameOccupied(String)

    var message: String {
        switch self {
        case .renamedFileMissing:
            return "The renamed file could not be found."
        case .originalNameOccupied(let filename):
            return "A file named \"\(filename)\" already exists at the original location."
        }
    }
}

/// Per-window, session-only slot holding at most one undo step.
struct SkimMarkerRenameUndoSlot {
    private(set) var step: SkimMarkerRenameUndoStep?

    var canUndo: Bool { step != nil }

    /// Records the moves a marker rename performed. A new step replaces the
    /// old one. Moves that change nothing are dropped, and a marker action that
    /// changes nothing neither creates nor replaces a step.
    mutating func record(_ moves: [SkimMarkerRenameMove]) {
        let effective = moves.filter { !$0.isNoOp }
        guard !effective.isEmpty else { return }
        step = SkimMarkerRenameUndoStep(moves: effective)
    }

    mutating func clear() {
        step = nil
    }
}

enum SkimMarkerRenameUndoPlanner {

    /// Builds the inverse of `step` (each file from its new name back to its
    /// old name) after checking every file first. If any check fails, nothing
    /// may be renamed: a file must still be at its new name, and no file may
    /// already be at its old name.
    static func inversePlan(
        for step: SkimMarkerRenameUndoStep,
        fileExistsAtPath: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Result<[SkimMarkerRenameMove], SkimMarkerRenameUndoRefusal> {
        let inverse = step.moves.reversed().map(\.inverse)
        for move in inverse {
            guard fileExistsAtPath(move.source.path) else {
                return .failure(.renamedFileMissing)
            }
            guard !fileExistsAtPath(move.destination.path) else {
                return .failure(.originalNameOccupied(move.destination.lastPathComponent))
            }
        }
        return .success(inverse)
    }

    /// Performs a checked inverse plan in order. Stops at the first filesystem
    /// error and returns the moves that completed before it, so the caller can
    /// update queue state for exactly those files.
    static func perform(
        _ plan: [SkimMarkerRenameMove],
        moveItem: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    ) -> (completed: [SkimMarkerRenameMove], error: Error?) {
        var completed: [SkimMarkerRenameMove] = []
        for move in plan {
            do {
                try moveItem(move.source, move.destination)
            } catch {
                return (completed, error)
            }
            completed.append(move)
        }
        return (completed, nil)
    }
}
