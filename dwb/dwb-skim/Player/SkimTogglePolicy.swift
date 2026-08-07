import Foundation

enum SkimTopBarControl: String, Equatable {
    case previousItem
    case skimToggle
    case queuePanel

    static let leadingOrder: [SkimTopBarControl] = [
        .previousItem,
        .skimToggle,
        .queuePanel,
    ]
}

enum SkimControlAccessibility {
    static let previousIdentifier = "previousItemButton"
    static let toggleIdentifier = "skimToggleButton"
    static let queueIdentifier = "queuePanelButton"
    static let clipDurationIdentifier = "clipDurationControls"
    static let startPositionIdentifier = "startPositionControls"
}

struct SkimControlPresentation: Equatable {
    let isEnabled: Bool

    var clipDurationControlsEnabled: Bool { isEnabled }
    var startPositionControlsEnabled: Bool { isEnabled }
    var toggleAccessibilityValue: String { isEnabled ? "On" : "Off" }
    var toggleTitle: String { isEnabled ? "Skim On" : "Skim Off" }
    var toggleHelp: String {
        "Skim is \(isEnabled ? "on" : "off"). Double-tap Option to toggle Skim."
    }
}

struct SkimDeadlineGuard: Equatable {
    let isSkimEnabled: Bool
    let scheduledAssignment: SkimMediaAssignmentToken?
    let currentAssignment: SkimMediaAssignmentToken?

    var mayAdvance: Bool {
        isSkimEnabled
            && scheduledAssignment != nil
            && scheduledAssignment == currentAssignment
    }
}

/// Tracks which assignment token and generation the window's currently scheduled preview
/// auto-advance deadline is bound to.
///
/// This is deliberately separate from `SkimPreviewSessionScheduler`, which owns only
/// session/queue-item/time state. A media assignment token can change out from under an
/// otherwise-unchanged logical preview session — most notably when playback-start handshake
/// recovery rebuilds the VLCKit player for the same session and queue item after a stalled
/// start. Without rebinding, the deadline callback's originally-captured assignment goes stale
/// and `SkimDeadlineGuard` rejects the fire, orphaning the session: the scheduler is left
/// `.scheduled` with a deadline that has already passed and no live timer to claim it, so
/// playback runs past the configured preview duration until natural end-of-media.
///
/// `scheduled` binds fresh state and advances the generation, so a callback captured before a
/// later relocation/replacement can recognize it no longer owns the live deadline even in the
/// (should-be-impossible, since `DispatchWorkItem.cancel()` already guards this on the serial
/// main queue) case its cancellation raced delivery. `rebind` updates only the assignment for a
/// still-live session/queue-item pairing, leaving the generation untouched — the pending timer
/// remains the right one; only what it must match against has moved.
struct SkimPreviewDeadlineBinding: Equatable {
    private(set) var sessionID: Int?
    private(set) var queueItemID: String?
    private(set) var assignment: SkimMediaAssignmentToken?
    private(set) var generation = 0

    /// Called every time a deadline is (re)scheduled: initial schedule, readiness-driven replace,
    /// relocation replace, or resume. Returns the new generation for the caller to capture
    /// alongside its timer.
    @discardableResult
    mutating func scheduled(sessionID: Int,
                            queueItemID: String,
                            assignment: SkimMediaAssignmentToken?) -> Int {
        self.sessionID = sessionID
        self.queueItemID = queueItemID
        self.assignment = assignment
        generation += 1
        return generation
    }

    /// Called when the window mints a new assignment token for media that is still logically the
    /// scheduled session (e.g. handshake-recovery player rebuild). Returns `true` when the
    /// binding matched and was rebound; `false` when this assignment belongs to a different
    /// session/queue-item and must not affect the live binding.
    @discardableResult
    mutating func rebind(sessionID: Int,
                         queueItemID: String,
                         assignment: SkimMediaAssignmentToken) -> Bool {
        guard self.sessionID == sessionID, self.queueItemID == queueItemID else { return false }
        self.assignment = assignment
        return true
    }

    mutating func clear() {
        sessionID = nil
        queueItemID = nil
        assignment = nil
    }

    func isCurrentGeneration(_ generation: Int) -> Bool {
        generation == self.generation
    }
}

enum SkimAssignmentBehavior: Equatable {
    case fullPlayback
    case skimPreview

    static func nextAssignment(isSkimEnabled: Bool) -> SkimAssignmentBehavior {
        isSkimEnabled ? .skimPreview : .fullPlayback
    }
}

enum SkimToggleTransition {
    static func toggled(_ current: Bool) -> Bool { !current }
}
