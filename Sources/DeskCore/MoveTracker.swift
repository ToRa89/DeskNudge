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

    public init(target: UInt16, startedAt: Date, timeout: TimeInterval = 60, settleDelay: TimeInterval = 1.5) {
        self.target = target
        self.startedAt = startedAt
        self.timeout = timeout
        self.settleDelay = settleDelay
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
        if atRest && elapsed >= settleDelay {
            return distance <= Self.restTolerance ? .reached : .stoppedShort(sample.position)
        }
        return .keepGoing
    }
}
