import Foundation

/// A player window as seen by the reactivation planner.
///
/// `isOnScreen` deliberately mirrors AppKit's `NSWindow.isVisible`, which is
/// false for a miniaturized or ordered-out window. Treating that flag as
/// "this window exists" is what previously caused a Dock click on a minimized
/// player to build a second window, so existence here is membership in the
/// candidate list, never `isOnScreen`.
struct PlayerWindowReactivationCandidate: Equatable {
    let identifier: String
    let isKeyWindow: Bool
    let isMiniaturized: Bool
    let isOnScreen: Bool
    /// Recency rank, 0 == most recently active.
    let activationRank: Int

    init(identifier: String,
         isKeyWindow: Bool = false,
         isMiniaturized: Bool = false,
         isOnScreen: Bool = true,
         activationRank: Int = 0) {
        self.identifier = identifier
        self.isKeyWindow = isKeyWindow
        self.isMiniaturized = isMiniaturized
        self.isOnScreen = isOnScreen
        self.activationRank = activationRank
    }
}

enum PlayerWindowReactivationPlan: Equatable {
    /// Raise a window that already exists. The controller, its queue, and its
    /// playback state are untouched; only window ordering changes.
    case raiseExisting(identifier: String,
                       needsDeminiaturize: Bool,
                       needsOrderFront: Bool)
    /// Only when no player window exists at all.
    case createNewPlayerWindow
}

enum PlayerWindowReactivationPlanner {

    /// Chooses what a Dock reopen should do. Prefers the key player window,
    /// otherwise the most recently active one. Never creates a window while any
    /// player window still exists, no matter how it is currently displayed.
    static func plan(candidates: [PlayerWindowReactivationCandidate]) -> PlayerWindowReactivationPlan {
        guard let target = select(from: candidates) else {
            return .createNewPlayerWindow
        }
        return .raiseExisting(identifier: target.identifier,
                              needsDeminiaturize: target.isMiniaturized,
                              needsOrderFront: target.isMiniaturized || !target.isOnScreen || !target.isKeyWindow)
    }

    static func select(from candidates: [PlayerWindowReactivationCandidate]) -> PlayerWindowReactivationCandidate? {
        if let key = candidates.first(where: { $0.isKeyWindow && !$0.isMiniaturized }) {
            return key
        }
        return candidates.min { lhs, rhs in
            if lhs.activationRank != rhs.activationRank {
                return lhs.activationRank < rhs.activationRank
            }
            return lhs.identifier < rhs.identifier
        }
    }
}
