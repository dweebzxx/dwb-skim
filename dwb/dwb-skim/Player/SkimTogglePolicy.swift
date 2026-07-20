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
