import Foundation

/// Hex helpers for every byte that crosses the adapter boundary.
public enum Hex {
    private static let digits: [Character] = Array("0123456789ABCDEF")

    public static func byteString(_ byte: UInt8) -> String {
        String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
    }

    public static func encode(_ bytes: some Sequence<UInt8>, separator: String = "") -> String {
        bytes.map(byteString).joined(separator: separator)
    }

    /// Decodes hex text. Spaces, tabs and line breaks are ignored, every other character must be a hex digit.
    public static func decode(_ text: String) throws -> [UInt8] {
        let characters = text.utf8.filter { ![0x20, 0x09, 0x0D, 0x0A].contains($0) }
        guard characters.count.isMultiple(of: 2) else {
            throw OBDError.malformedResponse("Hex-Text mit ungerader Länge: \(text)")
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(characters.count / 2)
        var index = 0
        while index < characters.count {
            guard let high = nibble(characters[index]), let low = nibble(characters[index + 1]) else {
                throw OBDError.malformedResponse("Kein gültiger Hex-Text: \(text)")
            }
            bytes.append(high << 4 | low)
            index += 2
        }
        return bytes
    }

    public static func nibble(_ character: UInt8) -> UInt8? {
        switch character {
        case 0x30...0x39: character - 0x30
        case 0x41...0x46: character - 0x41 + 10
        case 0x61...0x66: character - 0x61 + 10
        default: nil
        }
    }

    public static func isHexDigits<S: StringProtocol>(_ text: S) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { nibble($0) != nil }
    }

    /// CAN identifiers are printed with three digits (11-bit) or eight digits (29-bit).
    public static func canID(_ value: UInt32, extended: Bool) -> String {
        let text = String(value, radix: 16, uppercase: true)
        let width = extended ? 8 : 3
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    public static func parseCANID<S: StringProtocol>(_ text: S) -> UInt32? {
        guard text.count == 3 || text.count == 8, isHexDigits(text) else { return nil }
        return UInt32(text, radix: 16)
    }
}
