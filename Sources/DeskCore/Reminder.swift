import Foundation

public enum Posture: String, Codable, Sendable {
    case sitting
    case standing
}

public struct Favourites: Equatable, Sendable {
    public let sit: UInt16
    public let stand: UInt16

    public init(sit: UInt16, stand: UInt16) {
        self.sit = sit
        self.stand = stand
    }
}

public struct DeskSettings: Codable, Equatable, Sendable {
    public var deskID: UUID?
    public var deskName: String?
    public var sitPosition: UInt16?
    public var standPosition: UInt16?
    public var customPosition: UInt16?
    public var customName: String?
    public var baseHeightCm: Double
    public var sitMinutes: Int
    public var standMinutes: Int
    public var remindersEnabled: Bool

    public init(
        deskID: UUID? = nil,
        deskName: String? = nil,
        sitPosition: UInt16? = nil,
        standPosition: UInt16? = nil,
        customPosition: UInt16? = nil,
        customName: String? = nil,
        baseHeightCm: Double = 62.0,
        sitMinutes: Int = 45,
        standMinutes: Int = 15,
        remindersEnabled: Bool = true
    ) {
        self.deskID = deskID
        self.deskName = deskName
        self.sitPosition = sitPosition
        self.standPosition = standPosition
        self.customPosition = customPosition
        self.customName = customName
        self.baseHeightCm = baseHeightCm
        self.sitMinutes = sitMinutes
        self.standMinutes = standMinutes
        self.remindersEnabled = remindersEnabled
    }

    public var customDisplayName: String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Favorit 3" : trimmed
    }

    public var favourites: Favourites? {
        guard let sitPosition, let standPosition else { return nil }
        return Favourites(sit: sitPosition, stand: standPosition)
    }
}

public enum ReminderLogic {
    public static func posture(position: UInt16, favourites: Favourites) -> Posture {
        let midpoint = (Int(favourites.sit) + Int(favourites.stand)) / 2
        let standIsHigher = favourites.stand >= favourites.sit
        let isAbove = Int(position) > midpoint
        return isAbove == standIsHigher ? .standing : .sitting
    }

    public static func dueDate(posture: Posture, since: Date, settings: DeskSettings) -> Date {
        let minutes = posture == .sitting ? settings.sitMinutes : settings.standMinutes
        return since.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
    }

    public static func target(after posture: Posture, favourites: Favourites) -> UInt16 {
        posture == .sitting ? favourites.stand : favourites.sit
    }
}
