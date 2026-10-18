import Foundation

/// Two-byte diagnostic trouble code as defined by SAE J2012, for example P0401 or U0100.
public struct DTCCode: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public enum System: String, Sendable, Codable, CaseIterable {
        case powertrain = "P"
        case chassis = "C"
        case body = "B"
        case network = "U"

        public var german: String {
            switch self {
            case .powertrain: "Antrieb (Motor, Getriebe, Abgas)"
            case .chassis: "Fahrwerk (Bremsen, Lenkung, Federung)"
            case .body: "Karosserie (Airbag, Komfort, Licht)"
            case .network: "Netzwerk und Kommunikation"
            }
        }
    }

    public enum Origin: String, Sendable, Codable {
        case sae
        case manufacturer

        public var german: String {
            switch self {
            case .sae: "genormter Code (SAE)"
            case .manufacturer: "herstellerspezifischer Code"
            }
        }
    }

    public let raw: UInt16

    public init(raw: UInt16) {
        self.raw = raw
    }

    public init(high: UInt8, low: UInt8) {
        raw = UInt16(high) << 8 | UInt16(low)
    }

    /// Parses text such as "P0401": system letter, digit 0 to 3, three hex digits.
    public init?(_ text: String) {
        let characters = Array(text.uppercased().utf8)
        guard characters.count == 5,
              let system = Array("PCBU".utf8).firstIndex(of: characters[0]),
              (0x30...0x33).contains(characters[1]),
              let a = Hex.nibble(characters[2]),
              let b = Hex.nibble(characters[3]),
              let c = Hex.nibble(characters[4])
        else { return nil }
        raw = UInt16(system) << 14
            | UInt16(characters[1] - 0x30) << 12
            | UInt16(a) << 8 | UInt16(b) << 4 | UInt16(c)
    }

    public var system: System { System.allCases[Int(raw >> 14)] }
    public var firstDigit: Int { Int((raw >> 12) & 0x3) }
    public var secondDigit: Int { Int((raw >> 8) & 0xF) }

    public var description: String {
        let tail = String(raw & 0x0FFF, radix: 16, uppercase: true)
        return system.rawValue + String(firstDigit) + String(repeating: "0", count: 3 - tail.count) + tail
    }

    /// SAE J2012 ranges: P0, P2, P34 to P39 and the digits 0 and 3 for C, B, U are SAE controlled.
    public var origin: Origin {
        switch (system, firstDigit) {
        case (.powertrain, 1): .manufacturer
        case (.powertrain, 3): secondDigit <= 3 ? .manufacturer : .sae
        case (.powertrain, _): .sae
        case (_, 1), (_, 2): .manufacturer
        default: .sae
        }
    }

    /// Powertrain group by second digit for SAE controlled P0 and P2 codes. Nil where no stable group exists.
    public var subsystemGerman: String? {
        guard system == .powertrain else { return nil }
        switch (firstDigit, secondDigit) {
        case (0, 0x0): return "Kraftstoff- und Luftzumessung, Zusatz-Emissionssysteme"
        case (0, 0x1), (0, 0x2): return "Kraftstoff- und Luftzumessung"
        case (0, 0x3): return "Zündsystem oder Fehlzündungen"
        case (0, 0x4): return "Zusätzliche Abgasreinigung"
        case (0, 0x5): return "Geschwindigkeit, Leerlauf, Zusatzeingänge"
        case (0, 0x6): return "Steuergerät und Ausgänge"
        case (0, 0x7), (0, 0x8), (0, 0x9): return "Getriebe"
        case (0, 0xA): return "Hybridantrieb"
        case (2, 0x0), (2, 0x1), (2, 0x2), (2, 0xA): return "Kraftstoff- und Luftzumessung, Zusatz-Emissionssysteme"
        case (2, 0x3): return "Zündsystem"
        case (2, 0x4): return "Zusätzliche Abgasreinigung"
        case (2, 0x5): return "Zusatzeingänge"
        case (2, 0x6): return "Steuergerät und Ausgänge"
        case (2, 0x7): return "Getriebe"
        default: return nil
        }
    }

    public static func < (lhs: DTCCode, rhs: DTCCode) -> Bool { lhs.raw < rhs.raw }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let code = DTCCode(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Kein gültiger Fehlercode: \(text)"))
        }
        self = code
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
