import Foundation

/// Decides when a video start counts as stalled, and when a run of stalled starts is worth a
/// second warning. Pure value logic: it holds ids, paths, and times the window gives it, and it
/// never touches a player. The window writes the console lines and owns the one watchdog timer.
///
/// - Single start: a video start that has not seen `.playing` within `stallSeconds` is stalled.
/// - Streak: consecutive video starts that never saw `.playing` are counted once each, when the
///   start is judged stalled or when its session ends. `.playing` resets the count. The count
///   reaching `streakWarningCount` warns once, until the next reset.
/// - A session that was paused before `.playing` never warns and is never counted.
struct PlaybackStartStallMonitor {

    static let stallSeconds: TimeInterval = 5.0
    static let streakWarningCount = 3

    /// What the window should write after an event. Both fields can be set together.
    struct Outcome: Equatable {
        struct StalledStart: Equatable {
            let sessionID: Int
            let fileName: String
            let secondsSinceStart: TimeInterval
        }
        struct StreakWarning: Equatable {
            let count: Int
            let sessionID: Int
            let fileName: String
        }
        var stalledStart: StalledStart?
        var streakWarning: StreakWarning?
    }

    private struct Session {
        let id: Int
        let filePath: String
        let fileName: String
        let startTime: TimeInterval
        var sawPlaying = false
        var paused: Bool
        var warned = false
        var counted = false
    }

    private var active: Session?
    private(set) var failedStartStreak = 0
    private var streakWarned = false

    var activeSessionID: Int? { active?.id }

    // MARK: - Single-start decision

    /// True when a start should get its one `start-stalled` warning.
    static func shouldWarnStalledStart(startTime: TimeInterval,
                                       now: TimeInterval,
                                       sawPlaying: Bool,
                                       watchedSessionID: Int,
                                       currentSessionID: Int,
                                       isPaused: Bool,
                                       alreadyWarned: Bool) -> Bool {
        guard !sawPlaying, !isPaused, !alreadyWarned,
              watchedSessionID == currentSessionID else { return false }
        return now - startTime >= stallSeconds
    }

    // MARK: - Events

    /// A new video start. Ends the previous session first.
    mutating func beginVideoSession(id: Int,
                                    filePath: String,
                                    fileName: String,
                                    startTime: TimeInterval,
                                    isPaused: Bool) -> Outcome {
        let outcome = endActiveSession()
        active = Session(id: id, filePath: filePath, fileName: fileName,
                         startTime: startTime, paused: isPaused)
        return outcome
    }

    /// The active session ended: replaced by another start (an image too) or the window closed.
    /// Counts it toward the streak when it never saw `.playing` and was never paused.
    mutating func endActiveSession() -> Outcome {
        guard let session = active else { return Outcome() }
        active = nil
        guard !session.sawPlaying, !session.paused, !session.counted else { return Outcome() }
        return Outcome(stalledStart: nil, streakWarning: countFailedStart(of: session))
    }

    /// A `.playing` state arrived for `mediaPath`. Returns true when it belongs to the active
    /// session, which resets the streak.
    @discardableResult
    mutating func notePlaying(mediaPath: String, isPaused: Bool) -> Bool {
        guard !isPaused, var session = active, session.filePath == mediaPath else { return false }
        session.sawPlaying = true
        active = session
        failedStartStreak = 0
        streakWarned = false
        return true
    }

    /// The window paused the session. A session paused before `.playing` never warns or counts,
    /// and resuming does not bring it back.
    mutating func notePaused() {
        active?.paused = true
    }

    /// The watchdog timer fired.
    mutating func watchdogFired(now: TimeInterval,
                                currentSessionID: Int,
                                isPaused: Bool) -> Outcome {
        guard var session = active else { return Outcome() }
        guard Self.shouldWarnStalledStart(startTime: session.startTime,
                                          now: now,
                                          sawPlaying: session.sawPlaying,
                                          watchedSessionID: session.id,
                                          currentSessionID: currentSessionID,
                                          isPaused: isPaused || session.paused,
                                          alreadyWarned: session.warned) else { return Outcome() }
        session.warned = true
        let stalled = Outcome.StalledStart(sessionID: session.id,
                                           fileName: session.fileName,
                                           secondsSinceStart: now - session.startTime)
        let streak = session.counted ? nil : countFailedStart(of: &session)
        active = session
        return Outcome(stalledStart: stalled, streakWarning: streak)
    }

    // MARK: - Streak

    private mutating func countFailedStart(of session: Session) -> Outcome.StreakWarning? {
        var copy = session
        return countFailedStart(of: &copy)
    }

    private mutating func countFailedStart(of session: inout Session) -> Outcome.StreakWarning? {
        session.counted = true
        failedStartStreak += 1
        guard failedStartStreak >= Self.streakWarningCount, !streakWarned else { return nil }
        streakWarned = true
        return Outcome.StreakWarning(count: failedStartStreak,
                                     sessionID: session.id,
                                     fileName: session.fileName)
    }
}
