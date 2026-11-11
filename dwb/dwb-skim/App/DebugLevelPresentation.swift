import Foundation

// MARK: - Debug level

enum DebugLevel: Int, Comparable {
    case info = 0, warning, error

    static func < (lhs: DebugLevel, rhs: DebugLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension DebugLevel {
    /// The level's word as the Debug Console shows it. Every level carries a word and a
    /// glyph, so a level is never told apart by color alone.
    var word: String {
        switch self {
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERR"
        }
    }

    /// The SF Symbol drawn before the word.
    var glyphName: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}
