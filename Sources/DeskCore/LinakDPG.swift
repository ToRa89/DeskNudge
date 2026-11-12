import Foundation

/// DPG ("desk panel gateway") commands of the LINAK control box.
/// Format as used by rhyst/linak-controller: request = 0x7F, command, 0x00 (read) or 0x80 + payload (write);
/// the answer arrives as a notification on the DPG characteristic, starting with 0x01 when valid.
public enum LinakDPG {
    public static let userIDCommand: UInt8 = 0x86

    private static let header: UInt8 = 0x7F
    private static let readFlag: UInt8 = 0x00
    private static let writeFlag: UInt8 = 0x80
    private static let validMarker: UInt8 = 0x01

    public static func readRequest(_ command: UInt8) -> Data {
        Data([header, command, readFlag])
    }

    public static func writeRequest(_ command: UInt8, payload: Data) -> Data {
        Data([header, command, writeFlag]) + payload
    }

    /// Payload of a DPG answer, or nil if the answer is invalid.
    public static func payload(ofResponse response: Data) -> Data? {
        let bytes = [UInt8](response)
        guard bytes.count >= 2, bytes[0] == validMarker else { return nil }
        return Data(bytes.dropFirst(2))
    }

    /// DPG1C controllers only accept movement over Bluetooth when the user ID starts with 0x01.
    /// Returns the corrected ID, or nil if nothing needs to change.
    public static func fixedUserID(_ userID: Data) -> Data? {
        var bytes = [UInt8](userID)
        guard let first = bytes.first, first != validMarker else { return nil }
        bytes[0] = validMarker
        return Data(bytes)
    }
}
