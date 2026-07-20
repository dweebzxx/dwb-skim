import Foundation

enum PlaybackCompletionAction: String {
    case playNext
    case loopQueueNext
    case stopLastItem
    case ignoredUserStop
}

struct PlaybackCompletionPolicy {
    let currentDisplayIndex: Int
    let displayOrderCount: Int
    let isLoopQueueEnabled: Bool
    let queueIsEmpty: Bool

    var action: PlaybackCompletionAction {
        if currentDisplayIndex < displayOrderCount - 1 { return .playNext }
        if isLoopQueueEnabled && !queueIsEmpty { return .loopQueueNext }
        return .stopLastItem
    }
}
