import Foundation

enum SkimPreviewReadinessSource: String, Equatable {
    case playing
    case fallback
    case resume
    case metadata
    case relocation
}

enum SkimPreviewTerminalReason: String, Equatable {
    case deadline
    case naturalEnd
}

enum SkimPreviewSeekState: Equatable {
    case pending
    case applied
    case skipped(String)
}

enum SkimPreviewSessionStatus: Equatable {
    case ineligible
    case awaitingReadiness
    case scheduled
    case suspended
    case fired(SkimPreviewTerminalReason)
    case cancelled(String)
}

enum SkimPreviewDeadlineUpdate: Equatable {
    case scheduled(deadlineUptime: TimeInterval)
    case confirmed(deadlineUptime: TimeInterval)
    case replaced(previousDeadlineUptime: TimeInterval, deadlineUptime: TimeInterval)
    case suspended(remainingSeconds: TimeInterval)
    case ignored(String)
}

enum SkimPreviewPauseUpdate: Equatable {
    case suspended(remainingSeconds: TimeInterval?)
    case resumed(deadlineUptime: TimeInterval)
    case awaitingReadiness
    case confirmedPaused(remainingSeconds: TimeInterval?)
    case confirmedRunning(deadlineUptime: TimeInterval?)
    case ignored(String)
}

enum SkimPreviewDeadlineClaim: Equatable {
    case fired
    case rejected(String)
}

enum SkimPreviewNaturalEndClaim: Equatable {
    case won
    case confirmed
    case notEligible
    case rejected(String)
}

struct SkimPreviewSessionSchedulingState: Equatable {
    let sessionID: Int
    var queueItemID: String
    let plannedDurationSeconds: TimeInterval?
    let createdUptime: TimeInterval
    let metadataRetryDeadlineUptime: TimeInterval
    var playbackStartUptime: TimeInterval?
    var effectiveDurationSeconds: TimeInterval?
    var deadlineUptime: TimeInterval?
    var readinessSource: SkimPreviewReadinessSource?
    var status: SkimPreviewSessionStatus
    var seekState: SkimPreviewSeekState = .pending
    var isPaused = false
    var pausedUptime: TimeInterval?
    var suspendedRemainingSeconds: TimeInterval?
}

/// Pure per-window preview scheduling authority. Callers own the concrete timer and
/// feed its monotonic fire time back through `claimDeadline` before advancing.
struct SkimPreviewSessionScheduler {
    private(set) var state: SkimPreviewSessionSchedulingState?

    mutating func begin(sessionID: Int,
                        queueItemID: String,
                        plannedDurationSeconds: TimeInterval?,
                        createdUptime: TimeInterval,
                        metadataRetryWindow: TimeInterval) {
        let duration = Self.validDuration(plannedDurationSeconds)
        let retryWindow = max(0, metadataRetryWindow.isFinite ? metadataRetryWindow : 0)
        state = SkimPreviewSessionSchedulingState(
            sessionID: sessionID,
            queueItemID: queueItemID,
            plannedDurationSeconds: duration,
            createdUptime: createdUptime,
            metadataRetryDeadlineUptime: createdUptime + retryWindow,
            playbackStartUptime: nil,
            effectiveDurationSeconds: duration,
            deadlineUptime: nil,
            readinessSource: nil,
            status: duration == nil ? .ineligible : .awaitingReadiness
        )
    }

    mutating func registerReadiness(sessionID: Int,
                                    queueItemID: String,
                                    source: SkimPreviewReadinessSource,
                                    now: TimeInterval,
                                    effectiveDurationSeconds: TimeInterval? = nil) -> SkimPreviewDeadlineUpdate {
        guard var current = matchingState(sessionID: sessionID, queueItemID: queueItemID) else {
            return .ignored("session-or-item-mismatch")
        }
        guard current.plannedDurationSeconds != nil else { return .ignored("full-file") }
        switch current.status {
        case .awaitingReadiness, .scheduled, .suspended:
            break
        case .ineligible:
            return .ignored("full-file")
        case .fired:
            return .ignored("already-fired")
        case .cancelled:
            return .ignored("cancelled")
        }

        guard let duration = Self.validDuration(effectiveDurationSeconds)
                ?? current.effectiveDurationSeconds
                ?? current.plannedDurationSeconds else {
            return .ignored("invalid-duration")
        }

        if current.isPaused {
            current.effectiveDurationSeconds = duration
            current.suspendedRemainingSeconds = min(current.suspendedRemainingSeconds ?? duration, duration)
            current.readinessSource = source
            current.status = .suspended
            state = current
            return .suspended(remainingSeconds: current.suspendedRemainingSeconds ?? duration)
        }

        if let existingDeadline = current.deadlineUptime,
           let startUptime = current.playbackStartUptime {
            let refinedDeadline = startUptime + duration
            if refinedDeadline < existingDeadline - Self.deadlineTolerance {
                current.effectiveDurationSeconds = duration
                current.deadlineUptime = refinedDeadline
                current.readinessSource = source
                current.status = .scheduled
                state = current
                return .replaced(previousDeadlineUptime: existingDeadline,
                                 deadlineUptime: refinedDeadline)
            }
            state = current
            return .confirmed(deadlineUptime: existingDeadline)
        }

        current.playbackStartUptime = now
        current.effectiveDurationSeconds = duration
        current.deadlineUptime = now + duration
        current.readinessSource = source
        current.status = .scheduled
        state = current
        return .scheduled(deadlineUptime: now + duration)
    }

    mutating func replaceDeadlineForRelocation(sessionID: Int,
                                               queueItemID: String,
                                               now: TimeInterval,
                                               durationSeconds: TimeInterval) -> SkimPreviewDeadlineUpdate {
        guard var current = matchingState(sessionID: sessionID, queueItemID: queueItemID) else {
            return .ignored("session-or-item-mismatch")
        }
        guard let duration = Self.validDuration(durationSeconds),
              current.plannedDurationSeconds != nil else {
            return .ignored("full-file-or-invalid-duration")
        }
        switch current.status {
        case .awaitingReadiness, .scheduled, .suspended:
            break
        case .ineligible:
            return .ignored("full-file")
        case .fired:
            return .ignored("already-fired")
        case .cancelled:
            return .ignored("cancelled")
        }

        if current.isPaused {
            current.playbackStartUptime = nil
            current.effectiveDurationSeconds = duration
            current.deadlineUptime = nil
            current.suspendedRemainingSeconds = duration
            current.readinessSource = .relocation
            current.status = .suspended
            state = current
            return .suspended(remainingSeconds: duration)
        }

        let previous = current.deadlineUptime
        let deadline = now + duration
        current.playbackStartUptime = now
        current.effectiveDurationSeconds = duration
        current.deadlineUptime = deadline
        current.readinessSource = .relocation
        current.status = .scheduled
        state = current
        if let previous {
            return .replaced(previousDeadlineUptime: previous, deadlineUptime: deadline)
        }
        return .scheduled(deadlineUptime: deadline)
    }

    mutating func claimDeadline(sessionID: Int,
                                queueItemID: String,
                                expectedDeadlineUptime: TimeInterval,
                                now: TimeInterval) -> SkimPreviewDeadlineClaim {
        guard var current = matchingState(sessionID: sessionID, queueItemID: queueItemID) else {
            return .rejected("session-or-item-mismatch")
        }
        guard !current.isPaused else { return .rejected("session-paused") }
        guard current.status == .scheduled,
              let deadline = current.deadlineUptime else {
            return .rejected("not-scheduled")
        }
        guard abs(deadline - expectedDeadlineUptime) <= Self.deadlineTolerance else {
            return .rejected("replaced-deadline")
        }
        guard now + Self.fireTolerance >= deadline else {
            return .rejected("early-callback")
        }
        current.status = .fired(.deadline)
        state = current
        return .fired
    }

    mutating func claimNaturalEnd(sessionID: Int,
                                  queueItemID: String) -> SkimPreviewNaturalEndClaim {
        guard var current = matchingState(sessionID: sessionID, queueItemID: queueItemID) else {
            return .notEligible
        }
        guard current.plannedDurationSeconds != nil else { return .notEligible }
        guard !current.isPaused else { return .rejected("session-paused") }
        switch current.status {
        case .awaitingReadiness, .scheduled:
            current.status = .fired(.naturalEnd)
            state = current
            return .won
        case .suspended:
            return .rejected("session-paused")
        case .fired(.naturalEnd):
            return .confirmed
        case .fired(.deadline):
            return .rejected("deadline-already-fired")
        case .cancelled:
            return .rejected("session-cancelled")
        case .ineligible:
            return .notEligible
        }
    }

    mutating func allowNaturalEndAfterUnadvancableDeadline(sessionID: Int,
                                                           queueItemID: String) -> Bool {
        guard var current = matchingState(sessionID: sessionID, queueItemID: queueItemID),
              current.status == .fired(.deadline) else { return false }
        current.status = .ineligible
        state = current
        return true
    }

    @discardableResult
    mutating func cancel(reason: String) -> Bool {
        guard var current = state else { return false }
        switch current.status {
        case .fired, .cancelled:
            return false
        case .ineligible, .awaitingReadiness, .scheduled, .suspended:
            current.status = .cancelled(reason)
            state = current
            return true
        }
    }

    mutating func pause(sessionID: Int,
                        queueItemID: String,
                        now: TimeInterval) -> SkimPreviewPauseUpdate {
        guard var current = matchingState(sessionID: sessionID, queueItemID: queueItemID) else {
            return .ignored("session-or-item-mismatch")
        }
        if current.isPaused {
            return .confirmedPaused(remainingSeconds: current.suspendedRemainingSeconds)
        }
        switch current.status {
        case .fired, .cancelled:
            return .ignored("terminal")
        case .ineligible:
            current.isPaused = true
            current.pausedUptime = now
            state = current
            return .suspended(remainingSeconds: nil)
        case .awaitingReadiness:
            current.isPaused = true
            current.pausedUptime = now
            current.suspendedRemainingSeconds = current.effectiveDurationSeconds
            current.status = .suspended
        case .scheduled:
            current.isPaused = true
            current.pausedUptime = now
            if let deadline = current.deadlineUptime {
                current.suspendedRemainingSeconds = max(0.001, deadline - now)
            } else {
                current.suspendedRemainingSeconds = current.effectiveDurationSeconds
            }
            current.deadlineUptime = nil
            current.status = .suspended
        case .suspended:
            current.isPaused = true
            current.pausedUptime = current.pausedUptime ?? now
        }
        state = current
        return .suspended(remainingSeconds: current.suspendedRemainingSeconds)
    }

    mutating func resume(sessionID: Int,
                         queueItemID: String,
                         now: TimeInterval) -> SkimPreviewPauseUpdate {
        guard var current = matchingState(sessionID: sessionID, queueItemID: queueItemID) else {
            return .ignored("session-or-item-mismatch")
        }
        guard current.isPaused else {
            return .confirmedRunning(deadlineUptime: current.deadlineUptime)
        }
        current.isPaused = false
        current.pausedUptime = nil
        switch current.status {
        case .fired, .cancelled:
            state = current
            return .ignored("terminal")
        case .ineligible:
            state = current
            return .awaitingReadiness
        case .suspended:
            guard current.readinessSource != nil,
                  let remaining = Self.validDuration(current.suspendedRemainingSeconds
                                                     ?? current.effectiveDurationSeconds
                                                     ?? current.plannedDurationSeconds) else {
                current.status = .awaitingReadiness
                state = current
                return .awaitingReadiness
            }
            let deadline = now + remaining
            current.playbackStartUptime = now
            current.deadlineUptime = deadline
            current.suspendedRemainingSeconds = nil
            current.readinessSource = .resume
            current.status = .scheduled
            state = current
            return .resumed(deadlineUptime: deadline)
        case .awaitingReadiness:
            state = current
            return .awaitingReadiness
        case .scheduled:
            state = current
            return .confirmedRunning(deadlineUptime: current.deadlineUptime)
        }
    }

    mutating func updateQueueItemID(sessionID: Int, from oldID: String, to newID: String) -> Bool {
        guard var current = matchingState(sessionID: sessionID, queueItemID: oldID) else { return false }
        current.queueItemID = newID
        state = current
        return true
    }

    mutating func markSeekApplied(sessionID: Int, queueItemID: String) -> Bool {
        guard var current = matchingState(sessionID: sessionID, queueItemID: queueItemID),
              current.seekState == .pending else { return false }
        current.seekState = .applied
        state = current
        return true
    }

    mutating func markSeekSkipped(sessionID: Int, queueItemID: String, reason: String) -> Bool {
        guard var current = matchingState(sessionID: sessionID, queueItemID: queueItemID),
              current.seekState == .pending else { return false }
        current.seekState = .skipped(reason)
        state = current
        return true
    }

    func needsMetadataRetry(sessionID: Int, queueItemID: String, now: TimeInterval) -> Bool {
        guard let current = matchingState(sessionID: sessionID, queueItemID: queueItemID) else { return false }
        return current.seekState == .pending && !current.isPaused && now <= current.metadataRetryDeadlineUptime
    }

    private func matchingState(sessionID: Int,
                               queueItemID: String) -> SkimPreviewSessionSchedulingState? {
        guard let state,
              state.sessionID == sessionID,
              state.queueItemID == queueItemID else { return nil }
        return state
    }

    private static func validDuration(_ duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    private static let deadlineTolerance: TimeInterval = 0.000_1
    private static let fireTolerance: TimeInterval = 0.02
}
