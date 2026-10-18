import Foundation

public enum PIDCategory: String, Sendable, Codable, CaseIterable {
    case engine, fuel, air, exhaust, temperature, electrical, vehicle, diagnostics

    public var german: String {
        switch self {
        case .engine: "Motor"
        case .fuel: "Kraftstoff"
        case .air: "Luft und Ansaugung"
        case .exhaust: "Abgas"
        case .temperature: "Temperaturen"
        case .electrical: "Elektrik"
        case .vehicle: "Fahrzeug"
        case .diagnostics: "Diagnose"
        }
    }
}

/// One SAE J1979 service 01 parameter with its decoder.
public struct PIDDefinition: Sendable, Identifiable {
    public let pid: UInt8
    public let name: String
    public let category: PIDCategory
    public let byteCount: Int
    public let formula: String
    let decoder: @Sendable ([UInt8]) throws -> [DecodedField]

    public var id: UInt8 { pid }
    public var reference: String { "SAE J1979 Dienst 01, PID \(Hex.byteString(pid))" }

    init(pid: UInt8, name: String, category: PIDCategory, byteCount: Int, formula: String,
         decoder: @escaping @Sendable ([UInt8]) throws -> [DecodedField]) {
        self.pid = pid
        self.name = name
        self.category = category
        self.byteCount = byteCount
        self.formula = formula
        self.decoder = decoder
    }
}

public enum J1979 {
    public static let supportQueryPIDs: [UInt8] = [0x00, 0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0]

    public static func isSupportQuery(_ pid: UInt8) -> Bool {
        pid.isMultiple(of: 0x20) && pid <= 0xC0
    }

    public static func definition(_ pid: UInt8) -> PIDDefinition? { catalog[pid] }

    public static var allDefinitions: [PIDDefinition] { catalog.values.sorted { $0.pid < $1.pid } }

    /// Decodes the data bytes that follow `41 <pid>`. Unknown PIDs are returned as raw bytes.
    public static func decode(pid: UInt8, data: [UInt8]) throws -> [DecodedField] {
        guard let definition = catalog[pid] else {
            return [DecodedField(label: "PID \(Hex.byteString(pid))", value: .raw(data))]
        }
        guard data.count >= definition.byteCount else {
            throw OBDError.malformedResponse("PID \(Hex.byteString(pid)) erwartet \(definition.byteCount) Bytes, erhalten \(data.count)")
        }
        return try definition.decoder(Array(data.prefix(definition.byteCount)))
    }

    /// Decodes a support bitmask. Bit 7 of byte A stands for PID base + 1.
    public static func supportedPIDs(base: UInt8, mask: [UInt8]) throws -> Set<UInt8> {
        guard isSupportQuery(base) else {
            throw OBDError.malformedResponse("PID \(Hex.byteString(base)) ist keine Unterstützungsabfrage")
        }
        guard mask.count >= 4 else {
            throw OBDError.malformedResponse("Unterstützungsmaske braucht 4 Bytes, erhalten \(mask.count)")
        }
        var result = Set<UInt8>()
        for (byteIndex, byte) in mask.prefix(4).enumerated() {
            for bit in 0..<8 where byte & (0x80 >> UInt8(bit)) != 0 {
                result.insert(base &+ UInt8(byteIndex * 8 + bit + 1))
            }
        }
        return result
    }

    static let catalog: [UInt8: PIDDefinition] = {
        var table: [UInt8: PIDDefinition] = [:]
        for definition in buildCatalog() {
            precondition(table[definition.pid] == nil, "duplicate PID \(definition.pid)")
            table[definition.pid] = definition
        }
        return table
    }()
}
