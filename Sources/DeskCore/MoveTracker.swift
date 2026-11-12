import Foundation

/// Decides, tick by tick, whether a drive to a target position is finished.
public struct MoveTracker: Sendable {
    public enum Outcome: Equatable, Sendable {
        case keepGoing
        case reached
        case stoppedShort(UInt16)
        case timedOut
    }

    /// 0.5 cm counts as "arrived".
    public static let defaultTolerance: UInt16 = 50
    /// 1.5 cm still counts as arrived once the desk has come to rest.
    public static let restTolerance: UInt16 = 150

    public let target: UInt16
    public let startedAt: Date
    public let timeout: TimeInterval
    public let settleDelay: TimeInterval
    /// Position when the drive was requested; nil if unknown.
    public let startPosition: UInt16?
    /// A desk waking from standby can take several seconds before it starts moving.
    public let startGrace: TimeInterval

    public init(
        target: UInt16,
        startedAt: Date,
        startPosition: UInt16? = nil,
        timeout: TimeInterval = 60,
        settleDelay: TimeInterval = 1.5,
        startGrace: TimeInterval = 6
    ) {
        self.target = target
        self.startedAt = startedAt
        self.startPosition = startPosition
        self.timeout = timeout
        self.settleDelay = settleDelay
        self.startGrace = startGrace
    }

    private func hasLeftStart(_ position: UInt16) -> Bool {
        guard let startPosition else { return false }
        let moved = position > startPosition ? position - startPosition : startPosition - position
        return moved > Self.defaultTolerance
    }

    public enum NudgeDirection: Equatable, Sendable { case up, down }

    /// After a long idle period the controller ignores reference-input targets
    /// until it receives a real up/down command. Seconds before the first nudge
    /// and between nudges.
    public static let nudgeInterval: TimeInterval = 1.5

    /// Direction for a short up/down pulse when the desk still sits at its start
    /// position although a target was sent; nil when no pulse is due.
    public func wakeNudge(now: Date, sample: HeightSpeed?, lastNudgeAt: Date?) -> NudgeDirection? {
        guard let sample, sample.speed == 0, !hasLeftStart(sample.position) else { return nil }
        let elapsed = now.timeIntervalSince(startedAt)
        guard elapsed >= Self.nudgeInterval, elapsed < startGrace else { return nil }
        if let lastNudgeAt, now.timeIntervalSince(lastNudgeAt) < Self.nudgeInterval { return nil }
        guard sample.position != target else { return nil }
        return target > sample.position ? .up : .down
    }

    public func evaluate(now: Date, sample: HeightSpeed?) -> Outcome {
        let elapsed = now.timeIntervalSince(startedAt)
        guard let sample else {
            return elapsed >= timeout ? .timedOut : .keepGoing
        }
        let distance = sample.position > target ? sample.position - target : target - sample.position
        let atRest = sample.speed == 0

        if atRest && distance <= Self.defaultTolerance { return .reached }
        if elapsed >= timeout { return .timedOut }
        if atRest && !hasLeftStart(sample.position) && elapsed < startGrace { return .keepGoing }
        if atRest && elapsed >= settleDelay {
            return distance <= Self.restTolerance ? .reached : .stoppedShort(sample.position)
        }
        return .keepGoing
    }
}
