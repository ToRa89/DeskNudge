import Foundation

/// GATT identifiers of the LINAK desk control box (as found in the LINAK SDK of the Desk Control app).
public enum LinakUUID {
    public static let controlService = "99FA0001-338A-1024-8A49-009C0215F78A"
    public static let command = "99FA0002-338A-1024-8A49-009C0215F78A"
    public static let referenceOutputService = "99FA0020-338A-1024-8A49-009C0215F78A"
    public static let heightSpeed = "99FA0021-338A-1024-8A49-009C0215F78A"
    public static let referenceInputService = "99FA0030-338A-1024-8A49-009C0215F78A"
    public static let referenceInput = "99FA0031-338A-1024-8A49-009C0215F78A"
    public static let dpgService = "99FA0010-338A-1024-8A49-009C0215F78A"
    public static let dpg = "99FA0011-338A-1024-8A49-009C0215F78A"
}

public enum LinakCommand {
    public static let up = Data([0x47, 0x00])
    public static let down = Data([0x46, 0x00])
    public static let stop = Data([0xFF, 0x00])
    public static let wakeUp = Data([0xFE, 0x00])
}

/// Position in units of 0.1 mm above the lowest desk position, speed in device units.
public struct HeightSpeed: Equatable, Sendable {
    public let position: UInt16
    public let speed: Int16

    public init(position: UInt16, speed: Int16) {
        self.position = position
        self.speed = speed
    }
}

public enum LinakCodec {
    public static func decodeHeightSpeed(_ data: Data) -> HeightSpeed? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data.prefix(4))
        let position = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        let speed = Int16(bitPattern: UInt16(bytes[2]) | UInt16(bytes[3]) << 8)
        return HeightSpeed(position: position, speed: speed)
    }

    public static func encodeTarget(_ position: UInt16) -> Data {
        Data([UInt8(position & 0xFF), UInt8(position >> 8)])
    }

    /// Longest stroke of a LINAK column accepted for manual input (70 cm).
    public static let maxStroke: UInt16 = 7000

    public static func centimetres(position: UInt16, baseHeightCm: Double) -> Double {
        baseHeightCm + Double(position) / 100.0
    }

    /// Converts a user-entered height to a desk position, or nil if it lies outside the possible range.
    public static func position(centimetres: Double, baseHeightCm: Double) -> UInt16? {
        let raw = ((centimetres - baseHeightCm) * 100.0).rounded()
        guard raw.isFinite, raw >= 0, raw <= Double(maxStroke) else { return nil }
        return UInt16(raw)
    }
}
