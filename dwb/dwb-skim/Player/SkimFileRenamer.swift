import Foundation

enum SkimFileRenameError: Error, Equatable {
    case invalidName
    case unchanged
    case extensionChange
    case sourceMissing
    case targetExists(String)
    case filesystemFailure(String)
}

extension SkimFileRenameError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Enter a filename that is not empty and does not contain \"/\"."
        case .unchanged:
            return "The filename is unchanged."
        case .extensionChange:
            return "The file extension cannot be changed; it is preserved automatically."
        case .sourceMissing:
            return "The original file could not be found."
        case .targetExists(let filename):
            return "A file named \"\(filename)\" already exists in this folder."
        case .filesystemFailure(let message):
            return message
        }
    }
}

/// Which of the two mutually-exclusive app-configured custom prefixes a
/// one-click prefix action targets.
enum CustomPrefixAction: Equatable {
    case primary
    case secondary
}

/// How a custom-prefix press changes a filename.
enum CustomPrefixTransition: Equatable {
    /// Neither configured prefix was present; the requested one was put on.
    case added
    /// The other configured prefix was present; it was swapped for the requested one.
    case replaced
    /// The requested prefix was present; it was taken off.
    case removed
}

/// Where a custom-prefix press came from. Only the `N` / `M` keys may advance
/// the queue (P52); the Queue Page footer chips never do.
enum PrefixPressOrigin: Equatable {
    case key
    case footerChip
}

/// Why a prefix press did not advance the queue (Debug Console wording).
enum PrefixAdvanceSkipReason: String, Equatable {
    case removed
    case queueTarget
    case noNextItem
    case renameFailed
}

/// The outcome of the advance-after-prefix rule for one press.
enum PrefixAdvanceDecision: Equatable {
    /// The setting is off; behave exactly as before and log nothing extra.
    case settingOff
    case advance
    case skip(PrefixAdvanceSkipReason)
}

enum PrefixAdvancePolicy {
    /// Decides whether a prefix press may advance to the next item once its
    /// rename succeeds. Pure: no AppKit, VLCKit, or filesystem access.
    ///
    /// - `targetDisplayIndices`: the resolved display indices the press acts on.
    /// - `transition`: the transition for a single target, or `nil` when the
    ///   press changes nothing (which never advances).
    /// - `hasNextItem`: true when `Next` would move (a later item exists, or Loop queue is on).
    static func decision(settingEnabled: Bool,
                         origin: PrefixPressOrigin,
                         targetDisplayIndices: [Int],
                         currentDisplayIndex: Int,
                         transition: CustomPrefixTransition?,
                         hasNextItem: Bool) -> PrefixAdvanceDecision {
        guard settingEnabled else { return .settingOff }
        guard origin == .key else { return .skip(.queueTarget) }
        guard targetDisplayIndices.count == 1,
              targetDisplayIndices[0] == currentDisplayIndex else { return .skip(.queueTarget) }
        guard let transition else { return .skip(.renameFailed) }
        guard transition != .removed else { return .skip(.removed) }
        guard hasNextItem else { return .skip(.noNextItem) }
        return .advance
    }
}

enum SkimFileRenamer {

    /// The authoritative form of a configured custom prefix: leading/trailing
    /// whitespace removed, and a single trailing `_` guaranteed so applying it
    /// always yields `prefix_<filename>`. An empty/whitespace-only value stays
    /// empty (that prefix slot is unconfigured).
    static func normalizedCustomPrefix(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasSuffix("_") ? trimmed : trimmed + "_"
    }

    /// Computes the target filename for a custom-prefix toggle/replace action,
    /// or `nil` when the action is a no-op (or the requested prefix is empty).
    ///
    /// The two configured prefixes are mutually exclusive and never stack:
    ///
    /// | Recognized state | `.primary` action        | `.secondary` action      |
    /// | ---------------- | ------------------------ | ------------------------ |
    /// | neither prefix   | add primary              | add secondary            |
    /// | primary present  | remove primary           | replace primary → 2ndary |
    /// | secondary present| replace secondary → 1ary | remove secondary         |
    ///
    /// Only the two literal app-configured prefixes are recognized; unrelated
    /// leading filename text is never stripped. When one configured prefix is
    /// itself a leading substring of the other, the longer match is treated as
    /// the prefix that is actually present. The extension is preserved
    /// automatically because the transform only ever prepends to / strips from
    /// the front of the complete filename.
    static func customPrefixToggleTargetFilename(for filename: String,
                                                primaryPrefix: String,
                                                secondaryPrefix: String,
                                                action: CustomPrefixAction) -> String? {
        guard let resolution = customPrefixResolution(for: filename,
                                                      primaryPrefix: primaryPrefix,
                                                      secondaryPrefix: secondaryPrefix,
                                                      action: action) else { return nil }
        return resolution.target == filename ? nil : resolution.target
    }

    /// What a custom-prefix action does to `filename`: `.added` (neither
    /// configured prefix present), `.replaced` (the other prefix present), or
    /// `.removed` (the requested prefix present). `nil` when the action is a
    /// no-op — an empty requested prefix or an unchanged name — exactly when
    /// `customPrefixToggleTargetFilename` returns `nil`. Both functions share
    /// `customPrefixResolution`, so they cannot disagree.
    static func customPrefixTransition(for filename: String,
                                       primaryPrefix: String,
                                       secondaryPrefix: String,
                                       action: CustomPrefixAction) -> CustomPrefixTransition? {
        guard let resolution = customPrefixResolution(for: filename,
                                                      primaryPrefix: primaryPrefix,
                                                      secondaryPrefix: secondaryPrefix,
                                                      action: action),
              resolution.target != filename else { return nil }
        return resolution.transition
    }

    /// The single branch table behind the toggle target and its transition
    /// kind. `nil` only for an empty requested prefix.
    private static func customPrefixResolution(for filename: String,
                                               primaryPrefix: String,
                                               secondaryPrefix: String,
                                               action: CustomPrefixAction)
        -> (transition: CustomPrefixTransition, target: String)? {
        let requested = action == .primary ? primaryPrefix : secondaryPrefix
        let other     = action == .primary ? secondaryPrefix : primaryPrefix
        guard !requested.isEmpty else { return nil }

        let hasRequested = filename.hasPrefix(requested)
        let hasOther     = !other.isEmpty && filename.hasPrefix(other)

        enum Present { case none, requested, other }
        let present: Present
        if hasRequested && hasOther {
            present = requested.count >= other.count ? .requested : .other
        } else if hasRequested {
            present = .requested
        } else if hasOther {
            present = .other
        } else {
            present = .none
        }

        switch present {
        case .none:      return (.added, requested + filename)
        case .requested: return (.removed, String(filename.dropFirst(requested.count)))
        case .other:     return (.replaced, requested + String(filename.dropFirst(other.count)))
        }
    }

    /// Renames `sourceURL` to a target filename derived from `typedFilename`,
    /// preserving the original file's extension automatically. The user may
    /// type a bare stem, or a stem with the original extension (any case);
    /// typing a different extension is rejected. Performs one same-directory
    /// `FileManager.moveItem(at:to:)` and verifies the move on success.
    static func rename(sourceURL: URL,
                       toCompleteFilename typedFilename: String,
                       fileManager: FileManager = .default) throws -> URL {
        let targetFilename = try extensionPreservingTargetFilename(typedName: typedFilename, originalURL: sourceURL)

        guard targetFilename != sourceURL.lastPathComponent else {
            throw SkimFileRenameError.unchanged
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw SkimFileRenameError.sourceMissing
        }

        let targetURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(targetFilename, isDirectory: false)
        guard !fileManager.fileExists(atPath: targetURL.path) else {
            throw SkimFileRenameError.targetExists(targetFilename)
        }

        try move(from: sourceURL, to: targetURL, fileManager: fileManager)
        return targetURL
    }

    /// Derives an extension-preserving rename target from a typed name.
    ///
    /// - The typed value is treated as a filename/stem only, never a path.
    /// - Empty/whitespace-only input, input containing "/", and path-like
    ///   input are rejected as `.invalidName`.
    /// - If the original file has an extension, the typed value may omit it
    ///   (extension is appended), or repeat it in any case (the original
    ///   exact spelling is preserved in the result); any other extension is
    ///   rejected as `.extensionChange`.
    /// - If the original file has no extension, the typed value must not add
    ///   one; doing so is rejected as `.extensionChange`.
    static func extensionPreservingTargetFilename(typedName: String, originalURL: URL) throws -> String {
        let trimmed = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            throw SkimFileRenameError.invalidName
        }
        guard trimmed == URL(fileURLWithPath: trimmed).lastPathComponent else {
            throw SkimFileRenameError.invalidName
        }

        let originalExtension = originalURL.pathExtension
        let typedExtension = (trimmed as NSString).pathExtension

        if originalExtension.isEmpty {
            guard typedExtension.isEmpty else {
                throw SkimFileRenameError.extensionChange
            }
            return trimmed
        }

        guard !typedExtension.isEmpty else {
            return trimmed + "." + originalExtension
        }

        guard typedExtension.caseInsensitiveCompare(originalExtension) == .orderedSame else {
            throw SkimFileRenameError.extensionChange
        }

        let stem = (trimmed as NSString).deletingPathExtension
        guard !stem.isEmpty else {
            throw SkimFileRenameError.invalidName
        }
        return stem + "." + originalExtension
    }

    /// Performs the same-directory filesystem move and verifies the source no
    /// longer exists and the target exists before returning.
    private static func move(from sourceURL: URL, to targetURL: URL, fileManager: FileManager) throws {
        do {
            try fileManager.moveItem(at: sourceURL, to: targetURL)
        } catch {
            throw SkimFileRenameError.filesystemFailure(error.localizedDescription)
        }

        guard !fileManager.fileExists(atPath: sourceURL.path),
              fileManager.fileExists(atPath: targetURL.path) else {
            throw SkimFileRenameError.filesystemFailure("The file could not be verified after renaming.")
        }
    }
}

enum SkimQueueURLUpdate {
    /// Replaces the URL at `displayIndex` in `playbackSet`, verifying it still
    /// matches `originalURL` before mutating (guards against a stale display
    /// selection if the queue changed between the user's action and this call).
    static func replacingURL(in playbackSet: [URL],
                             displayOrder: [Int],
                             displayIndex: Int,
                             matching originalURL: URL,
                             with renamedURL: URL) -> [URL]? {
        guard displayIndex >= 0, displayIndex < displayOrder.count else { return nil }
        let setIndex = displayOrder[displayIndex]
        guard setIndex >= 0, setIndex < playbackSet.count else { return nil }
        guard playbackSet[setIndex].standardizedFileURL.path == originalURL.standardizedFileURL.path else { return nil }
        var updated = playbackSet
        updated[setIndex] = renamedURL
        return updated
    }

    /// Replaces the first occurrence of `originalURL` anywhere in
    /// `playbackSet`, independent of display order or sort position. Used
    /// where the caller does not have (or cannot trust) a display index —
    /// e.g. after the queue may have been resorted.
    static func replacingURL(in playbackSet: [URL],
                             matching originalURL: URL,
                             with renamedURL: URL) -> [URL]? {
        guard let index = playbackSet.firstIndex(where: {
            $0.standardizedFileURL.path == originalURL.standardizedFileURL.path
        }) else {
            return nil
        }
        var updated = playbackSet
        updated[index] = renamedURL
        return updated
    }
}
