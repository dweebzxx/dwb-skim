import Foundation

/// A filename split into the editable stem and the protected extension (design system 9.3).
struct RenameFilenameParts: Equatable {
    let stem: String
    /// The extension with its leading dot, or "" when the file has none.
    let extensionSuffix: String

    init(filename: String) {
        let name = filename as NSString
        let pathExtension = name.pathExtension
        stem = name.deletingPathExtension
        extensionSuffix = pathExtension.isEmpty ? "" : "." + pathExtension
    }

    var filename: String { stem + extensionSuffix }
}

/// The result of checking a typed stem in the single-file rename sheet.
enum RenameNameValidation: Equatable {
    /// The name can be applied.
    case valid
    /// The name matches the current one. Nothing to say, and Rename stays disabled.
    case unchanged
    case empty
    /// The name contains `/` or `:`.
    case forbiddenCharacter
    /// A file with this complete name already exists in the folder.
    case alreadyExists(String)

    /// Inline message under the field. `nil` for `.valid` and `.unchanged`.
    var inlineMessage: String? {
        switch self {
        case .valid, .unchanged: return nil
        case .empty: return "Enter a name."
        case .forbiddenCharacter: return "Names can\u{2019}t contain \u{201C}/\u{201D} or \u{201C}:\u{201D}."
        case .alreadyExists(let name): return "\u{201C}\(name)\u{201D} already exists in this folder."
        }
    }

    /// Rename is enabled only for a valid, changed name.
    var allowsRename: Bool { self == .valid }

    /// True when the field edge and focus ring take the error colors.
    var isError: Bool { inlineMessage != nil }

    static let forbiddenCharacters = CharacterSet(charactersIn: "/:")

    /// Checks `typedStem` against the file being renamed.
    ///
    /// - Parameter nameExists: Whether a file with this complete name is already in the folder.
    static func validate(typedStem: String,
                         original: RenameFilenameParts,
                         nameExists: (String) -> Bool) -> RenameNameValidation {
        let trimmed = typedStem.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == original.stem { return .unchanged }
        if trimmed.isEmpty { return .empty }
        if typedStem.rangeOfCharacter(from: forbiddenCharacters) != nil { return .forbiddenCharacter }
        let complete = trimmed + original.extensionSuffix
        if nameExists(complete) { return .alreadyExists(complete) }
        return .valid
    }

    /// The complete filename to rename to: the trimmed stem plus the protected extension.
    static func completeFilename(typedStem: String, original: RenameFilenameParts) -> String {
        typedStem.trimmingCharacters(in: .whitespacesAndNewlines) + original.extensionSuffix
    }
}

/// Content of the batch rename sheet: the "old › new" list and its copy.
struct BatchRenamePreview: Equatable {
    struct Row: Equatable {
        let oldName: String
        let newName: String

        /// "old › new", used as the row's accessibility text.
        var text: String { "\(oldName) \u{203A} \(newName)" }
    }

    static let maximumRows = 4

    /// At most `maximumRows` rows, in rename order.
    let rows: [Row]
    /// The number of moves not shown as rows.
    let remainingCount: Int
    let totalCount: Int

    init(moves: [(oldName: String, newName: String)]) {
        totalCount = moves.count
        rows = moves.prefix(Self.maximumRows).map { Row(oldName: $0.oldName, newName: $0.newName) }
        remainingCount = max(0, moves.count - Self.maximumRows)
    }

    var title: String { "Rename \(totalCount) Files?" }
    var confirmTitle: String { "Rename \(totalCount) Files" }

    /// "and N more", or `nil` when every move has a row.
    var moreText: String? {
        remainingCount > 0 ? "and \(remainingCount) more" : nil
    }

    /// The caption text and the range of the prefix inside it, which the sheet draws in
    /// monospaced semibold in the prefix's marker color.
    static func caption(prefix: String, count: Int) -> (text: String, prefixRange: NSRange) {
        let lead = "Applying prefix \""
        let text = "\(lead)\(prefix)\" will rename \(count) files on disk."
        let range = NSRange(location: (lead as NSString).length, length: (prefix as NSString).length)
        return (text, range)
    }
}
