import Foundation

/// Ford diagnostic buses reachable through the OBD connector.
public enum BusKind: String, Codable, Sendable, CaseIterable {
    case hsCAN = "hs-can"
    case msCAN = "ms-can"

    public var shortName: String {
        switch self {
        case .hsCAN: "HS-CAN"
        case .msCAN: "MS-CAN"
        }
    }

    public var german: String {
        switch self {
        case .hsCAN: "HS-CAN (500 kbit/s, Pins 6 und 14)"
        case .msCAN: "MS-CAN (125 kbit/s, Pins 3 und 11)"
        }
    }
}

/// How sure we are about the meaning of a value.
public enum Confidence: String, Codable, Sendable, CaseIterable {
    /// Defined by a standard (SAE, ISO).
    case standard
    /// Meaning confirmed on this vehicle.
    case verifiedOnVehicle = "verified-on-vehicle"
    /// Public but non-normative source, not confirmed on this vehicle.
    case community
    /// Raw data without known meaning.
    case unknown

    public var german: String {
        switch self {
        case .standard: "genormt"
        case .verifiedOnVehicle: "am Fahrzeug bestätigt"
        case .community: "unbestätigt (Community-Quelle)"
        case .unknown: "Bedeutung unbekannt"
        }
    }

    /// Only these may be presented as facts.
    public var isFact: Bool { self == .standard || self == .verifiedOnVehicle }
}

/// A decoded value. Numbers stay in metric units, formatting happens in `displayText` or the UI.
public enum MeasuredValue: Sendable, Equatable {
    case number(Double, unit: String)
    case text(String)
    case enumeration(code: Int, label: String)
    case flags([Flag])
    case unavailable(String)
    case raw([UInt8])

    public struct Flag: Sendable, Equatable, Codable {
        public let label: String
        public let isSet: Bool

        public init(label: String, isSet: Bool) {
            self.label = label
            self.isSet = isSet
        }
    }

    public var numericValue: Double? {
        if case .number(let value, _) = self { value } else { nil }
    }

    public var displayText: String {
        switch self {
        case .number(let value, let unit):
            unit.isEmpty ? Self.format(value) : "\(Self.format(value)) \(unit)"
        case .text(let text):
            text
        case .enumeration(_, let label):
            label
        case .flags(let flags):
            flags.filter(\.isSet).map(\.label).joined(separator: ", ").nonEmpty ?? "keine"
        case .unavailable(let reason):
            reason
        case .raw(let bytes):
            bytes.isEmpty ? "(leer)" : Hex.encode(bytes, separator: " ")
        }
    }

    public static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(Locale(identifier: "de_DE")))
    }
}

extension MeasuredValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, value, unit, code, label, flags, reason, hex
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "number":
            self = .number(try container.decode(Double.self, forKey: .value), unit: try container.decode(String.self, forKey: .unit))
        case "text":
            self = .text(try container.decode(String.self, forKey: .value))
        case "enumeration":
            self = .enumeration(code: try container.decode(Int.self, forKey: .code), label: try container.decode(String.self, forKey: .label))
        case "flags":
            self = .flags(try container.decode([Flag].self, forKey: .flags))
        case "unavailable":
            self = .unavailable(try container.decode(String.self, forKey: .reason))
        case "raw":
            self = .raw(try Hex.decode(container.decode(String.self, forKey: .hex)))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unbekannte Werteart \(other)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .number(let value, let unit):
            try container.encode("number", forKey: .kind)
            try container.encode(value, forKey: .value)
            try container.encode(unit, forKey: .unit)
        case .text(let text):
            try container.encode("text", forKey: .kind)
            try container.encode(text, forKey: .value)
        case .enumeration(let code, let label):
            try container.encode("enumeration", forKey: .kind)
            try container.encode(code, forKey: .code)
            try container.encode(label, forKey: .label)
        case .flags(let flags):
            try container.encode("flags", forKey: .kind)
            try container.encode(flags, forKey: .flags)
        case .unavailable(let reason):
            try container.encode("unavailable", forKey: .kind)
            try container.encode(reason, forKey: .reason)
        case .raw(let bytes):
            try container.encode("raw", forKey: .kind)
            try container.encode(Hex.encode(bytes), forKey: .hex)
        }
    }
}

/// One labelled value. Multi-value PIDs produce several fields.
public struct DecodedField: Sendable, Equatable, Codable {
    public var label: String
    public var value: MeasuredValue

    public init(label: String, value: MeasuredValue) {
        self.label = label
        self.value = value
    }
}

/// Where a value came from, byte for byte.
public struct Provenance: Sendable, Equatable, Codable {
    public var ecu: String
    public var bus: BusKind?
    public var requestHex: String
    public var responseHex: String
    public var timestamp: Date

    public init(ecu: String, bus: BusKind?, requestHex: String, responseHex: String, timestamp: Date) {
        self.ecu = ecu
        self.bus = bus
        self.requestHex = requestHex
        self.responseHex = responseHex
        self.timestamp = timestamp
    }
}

/// How a value was interpreted and how sure we are.
public struct DefinitionReference: Sendable, Equatable, Codable {
    public var reference: String
    public var formula: String
    public var confidence: Confidence

    public init(reference: String, formula: String, confidence: Confidence) {
        self.reference = reference
        self.formula = formula
        self.confidence = confidence
    }
}

public struct MeasurementRecord: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var fields: [DecodedField]
    public var rawHex: String
    public var provenance: Provenance
    public var definition: DefinitionReference

    public init(id: String, name: String, fields: [DecodedField], rawHex: String, provenance: Provenance, definition: DefinitionReference) {
        self.id = id
        self.name = name
        self.fields = fields
        self.rawHex = rawHex
        self.provenance = provenance
        self.definition = definition
    }

    public var primaryValue: MeasuredValue? { fields.first?.value }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
