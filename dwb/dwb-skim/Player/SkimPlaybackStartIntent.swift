import Foundation

enum SkimStartMetadataReadiness: String, Equatable {
    case unavailable
    case provisional
    case final
}

enum SkimStartIntentStatus: Equatable {
    case awaitingMetadata
    case awaitingMedia
    case ready
    case seekRequested
    case seekConfirmed
    case userOverridden
    case exhausted
    case cancelled(String)
}

enum SkimStartIntentAction: Equatable {
    case none(String)
    case requestSeek(offsetSeconds: TimeInterval, attempt: Int, reason: String)
    case confirmed(observedOffsetSeconds: TimeInterval)
    case stale(String)
    case exhausted
}

struct SkimPlaybackStartIntentState: Equatable {
    let windowID: String
    var queueItemID: String
    let playbackSessionID: Int
    let startMode: SkimPreviewStartMode
    let requestedSkipIntroSeconds: TimeInterval
    let previewDurationSeconds: TimeInterval?
    let startRandomValue: Double
    let createdUptime: TimeInterval
    var retryDeadlineUptime: TimeInterval
    let maximumSeekAttempts: Int

    var assignment: SkimMediaAssignmentToken?
    /// Wrapper object identifier recorded at bind time. Diagnostics only — VLCKit replaces its
    /// own wrapper for an unchanged assignment, so this must never gate acceptance.
    var boundWrapperDiagnostic: String?
    var mediaDurationSeconds: TimeInterval?
    var metadataReadiness: SkimStartMetadataReadiness = .unavailable
    var desiredOffsetSeconds: TimeInterval?
    var seekWasRequested = false
    var seekWasConfirmed = false
    var seekAttemptCount = 0
    var lastSeekRequestUptime: TimeInterval?
    var lastObservedOffsetSeconds: TimeInterval?
    var pausedUptime: TimeInterval?
    var status: SkimStartIntentStatus = .awaitingMetadata
}

/// Pure state machine for one window-owned VLC media start. The caller supplies
/// observed playback time and executes returned seek requests against the bound media.
struct SkimPlaybackStartIntentCoordinator {
    private(set) var state: SkimPlaybackStartIntentState?

    mutating func begin(windowID: String,
                        queueItemID: String,
                        playbackSessionID: Int,
                        startMode: SkimPreviewStartMode,
                        skipIntroSeconds: TimeInterval,
                        previewDurationSeconds: TimeInterval?,
                        startRandomValue: Double,
                        createdUptime: TimeInterval,
                        retryWindow: TimeInterval = 3,
                        maximumSeekAttempts: Int = 3) {
        let boundedWindow = max(0, retryWindow.isFinite ? retryWindow : 0)
        state = SkimPlaybackStartIntentState(
            windowID: windowID,
            queueItemID: queueItemID,
            playbackSessionID: playbackSessionID,
            startMode: startMode,
            requestedSkipIntroSeconds: max(0, skipIntroSeconds),
            previewDurationSeconds: Self.validDuration(previewDurationSeconds),
            startRandomValue: min(1, max(0, startRandomValue)),
            createdUptime: createdUptime,
            retryDeadlineUptime: createdUptime + boundedWindow,
            maximumSeekAttempts: max(1, maximumSeekAttempts),
            assignment: nil,
            boundWrapperDiagnostic: nil,
            mediaDurationSeconds: nil,
            status: .awaitingMetadata
        )
    }

    /// Binds this session's intent to one window-owned media assignment. `wrapperDiagnostic` is
    /// recorded for logging only and is deliberately not part of any acceptance check.
    @discardableResult
    mutating func bindAssignment(playbackSessionID: Int,
                                 queueItemID: String,
                                 assignment: SkimMediaAssignmentToken,
                                 wrapperDiagnostic: String? = nil) -> Bool {
        guard var current = matchingState(playbackSessionID: playbackSessionID,
                                          queueItemID: queueItemID) else { return false }
        current.boundWrapperDiagnostic = wrapperDiagnostic
        if current.assignment != assignment {
            current.assignment = assignment
            current.seekWasRequested = false
            current.seekWasConfirmed = false
            current.seekAttemptCount = 0
            current.lastSeekRequestUptime = nil
            current.lastObservedOffsetSeconds = nil
            if case .userOverridden = current.status {
                // A deliberate user position remains authoritative for this session.
            } else if current.desiredOffsetSeconds == nil {
                current.status = .awaitingMetadata
            } else {
                current.status = .ready
            }
        }
        state = current
        return true
    }

    @discardableResult
    mutating func updateMetadata(playbackSessionID: Int,
                                 queueItemID: String,
                                 durationSeconds: TimeInterval?,
                                 readiness: SkimStartMetadataReadiness) -> Bool {
        guard var current = matchingState(playbackSessionID: playbackSessionID,
                                          queueItemID: queueItemID) else { return false }
        guard current.status != .userOverridden,
              current.status != .exhausted,
              !Self.isCancelled(current.status) else { return false }
        guard let duration = Self.validDuration(durationSeconds) else {
            if current.mediaDurationSeconds == nil {
                current.metadataReadiness = .unavailable
                current.status = current.assignment == nil ? .awaitingMedia : .awaitingMetadata
            }
            state = current
            return false
        }

        let plan = SkimPreviewPlaybackPlan.plan(
            mode: current.startMode,
            skipIntroSeconds: current.requestedSkipIntroSeconds,
            clipDurationSeconds: current.previewDurationSeconds,
            mediaDurationSeconds: duration,
            randomValue: current.startRandomValue
        )
        current.mediaDurationSeconds = duration
        current.metadataReadiness = readiness
        current.desiredOffsetSeconds = plan.startOffsetSeconds
        if current.assignment == nil {
            current.status = .awaitingMedia
        } else if !current.seekWasConfirmed && current.status != .userOverridden {
            current.status = .ready
        }
        state = current
        return true
    }

    mutating func evaluate(playbackSessionID: Int,
                           queueItemID: String,
                           assignment: SkimMediaAssignmentToken,
                           observedOffsetSeconds: TimeInterval,
                           isSeekable: Bool,
                           isPaused: Bool,
                           now: TimeInterval) -> SkimStartIntentAction {
        guard var current = matchingState(playbackSessionID: playbackSessionID,
                                          queueItemID: queueItemID) else {
            return .stale("session-or-item-mismatch")
        }
        guard let bound = current.assignment else {
            return .stale("assignment-unbound")
        }
        guard bound == assignment else {
            return .stale(bound.playerGeneration == assignment.playerGeneration
                          ? "assignment-generation-mismatch"
                          : "player-generation-mismatch")
        }
        if current.status == .seekConfirmed { return .none("already-confirmed") }
        if Self.isTerminal(current.status) { return .none("terminal") }
        if current.status == .userOverridden { return .none("user-overridden") }
        guard let desired = current.desiredOffsetSeconds else { return .none("metadata-unavailable") }

        let observed = observedOffsetSeconds.isFinite ? max(0, observedOffsetSeconds) : 0
        current.lastObservedOffsetSeconds = observed
        let tolerance = Self.confirmationTolerance(desiredOffsetSeconds: desired)
        if desired <= tolerance || abs(observed - desired) <= tolerance {
            current.seekWasConfirmed = true
            current.status = .seekConfirmed
            state = current
            return .confirmed(observedOffsetSeconds: observed)
        }
        if isPaused {
            state = current
            return .none("session-paused")
        }
        guard isSeekable else {
            state = current
            return .none("media-not-seekable")
        }
        if current.seekAttemptCount >= current.maximumSeekAttempts ||
            (current.seekAttemptCount > 0 && now > current.retryDeadlineUptime) {
            current.status = .exhausted
            state = current
            return .exhausted
        }
        if let lastRequest = current.lastSeekRequestUptime,
           now - lastRequest < Self.minimumRetryInterval {
            state = current
            return .none("retry-cooldown")
        }

        current.seekAttemptCount += 1
        current.seekWasRequested = true
        current.lastSeekRequestUptime = now
        current.status = .seekRequested
        let reason = current.seekAttemptCount == 1 ? "initial" : (observed <= tolerance ? "reset-to-zero" : "offset-mismatch")
        let attempt = current.seekAttemptCount
        state = current
        return .requestSeek(offsetSeconds: desired, attempt: attempt, reason: reason)
    }

    @discardableResult
    mutating func noteUserSeek(playbackSessionID: Int, queueItemID: String) -> Bool {
        guard var current = matchingState(playbackSessionID: playbackSessionID,
                                          queueItemID: queueItemID) else { return false }
        current.status = .userOverridden
        state = current
        return true
    }

    mutating func pause(playbackSessionID: Int,
                        queueItemID: String,
                        now: TimeInterval) -> Bool {
        guard var current = matchingState(playbackSessionID: playbackSessionID,
                                          queueItemID: queueItemID),
              current.pausedUptime == nil else { return false }
        current.pausedUptime = now
        state = current
        return true
    }

    mutating func resume(playbackSessionID: Int,
                         queueItemID: String,
                         now: TimeInterval) -> Bool {
        guard var current = matchingState(playbackSessionID: playbackSessionID,
                                          queueItemID: queueItemID),
              let pausedUptime = current.pausedUptime else { return false }
        current.retryDeadlineUptime += max(0, now - pausedUptime)
        current.pausedUptime = nil
        state = current
        return true
    }

    @discardableResult
    mutating func updateQueueItemID(playbackSessionID: Int,
                                    from oldID: String,
                                    to newID: String) -> Bool {
        guard var current = matchingState(playbackSessionID: playbackSessionID,
                                          queueItemID: oldID) else { return false }
        current.queueItemID = newID
        state = current
        return true
    }

    @discardableResult
    mutating func cancel(reason: String) -> Bool {
        guard var current = state, !Self.isCancelled(current.status) else { return false }
        current.status = .cancelled(reason)
        state = current
        return true
    }

    private func matchingState(playbackSessionID: Int,
                               queueItemID: String) -> SkimPlaybackStartIntentState? {
        guard let state,
              state.playbackSessionID == playbackSessionID,
              state.queueItemID == queueItemID else { return nil }
        return state
    }

    private static func validDuration(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func isTerminal(_ status: SkimStartIntentStatus) -> Bool {
        switch status {
        case .userOverridden, .exhausted, .cancelled:
            return true
        case .awaitingMetadata, .awaitingMedia, .ready, .seekRequested, .seekConfirmed:
            return false
        }
    }

    private static func isCancelled(_ status: SkimStartIntentStatus) -> Bool {
        if case .cancelled = status { return true }
        return false
    }

    private static func confirmationTolerance(desiredOffsetSeconds: TimeInterval) -> TimeInterval {
        max(0.4, min(1.0, desiredOffsetSeconds * 0.005))
    }

    private static let minimumRetryInterval: TimeInterval = 0.25
}
