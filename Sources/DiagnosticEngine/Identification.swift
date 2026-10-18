import FordKnowledge
import Foundation
import OBDCore

/// Ford part number "prefix-base-suffix", for example BG91-12A650-AGD. The base names the component type.
public struct FordPartNumber: Sendable, Codable, Equatable {
    public let prefix: String
    public let base: String
    public let suffix: String

    public init(prefix: String, base: String, suffix: String) {
        self.prefix = prefix
        self.base = base
        self.suffix = suffix
    }

    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        let allowed: (Substring) -> Bool = { $0.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) } }
        guard parts.count == 3, parts[0].count == 4, (4...6).contains(parts[1].count), (1...4).contains(parts[2].count),
              parts.allSatisfy(allowed) else { return nil }
        self.init(prefix: String(parts[0]), base: String(parts[1]), suffix: String(parts[2]))
    }

    public var text: String { "\(prefix)-\(base)-\(suffix)" }
}

/// One identifier read from a module, decoded only as far as it is unambiguous.
public struct DIDReading: Sendable, Codable, Equatable, Identifiable {
    public enum Status: String, Sendable, Codable {
        case value
        case negative
        case noResponse
    }

    public var did: String
    public var name: String
    public var confidence: Confidence
    public var status: Status
    public var hex: String?
    public var text: String?
    public var vin: String?
    public var partNumber: FordPartNumber?
    public var partNumberModule: String?
    public var negativeResponseCode: String?
    public var negativeResponseText: String?
    public var requestHex: String
    public var responseHex: String?

    public var id: String { did }

    public var displayValue: String {
        switch status {
        case .value: text ?? ((hex?.isEmpty ?? true) ? "(leer)" : hex ?? "")
        case .negative: "abgelehnt: \(negativeResponseText ?? negativeResponseCode ?? "?")"
        case .noResponse: "keine Antwort"
        }
    }
}

public struct IdentificationResult: Sendable, Equatable, Codable {
    public var readings: [DIDReading] = []
    /// Identifiers the module answered with 7F 22 31 (does not exist). Not listed individually.
    public var unsupportedCount = 0
    public var issues: [String] = []

    public init(readings: [DIDReading] = [], unsupportedCount: Int = 0, issues: [String] = []) {
        self.readings = readings
        self.unsupportedCount = unsupportedCount
        self.issues = issues
    }
}

public struct Identification: Sendable {
    public static let standardSet: [UInt16] = [
        0xF190, 0xF111, 0xF113, 0xF188, 0xF187, 0xF18A, 0xF18B, 0xF18C, 0xF191, 0xF192, 0xF193, 0xF194, 0xF195,
        0xF197, 0xF110, 0xF10A, 0xF120, 0xF121, 0xF122, 0xF123, 0xF124, 0xF125, 0xF126, 0xF127, 0xF128,
        0xF16B, 0xF16C, 0xF16D, 0xF16E, 0xF17D,
    ]
    public static let fullRange: ClosedRange<UInt16> = 0xF100...0xF1FF

    let uds: UDSService
    let knowledge: KnowledgeBase

    public init(uds: UDSService, knowledge: KnowledgeBase) {
        self.uds = uds
        self.knowledge = knowledge
    }

    public func read(module: UInt32, full: Bool) async throws -> IdentificationResult {
        try await readRange(full ? Array(Self.fullRange) : Self.standardSet, module: module, stopAfterMisses: nil) { did in
            (nil, nil)
        }
    }

    /// Ford As-Built configuration blocks DE00 upward, until three identifiers in a row do not exist.
    public func readAsBuilt(module: UInt32) async throws -> IdentificationResult {
        try await readRange(Array(UInt16(0xDE00)...UInt16(0xDEFF)), module: module, stopAfterMisses: 3) { did in
            ("Konfigurationsblock \(Self.hex(did)) (As-Built)", .community)
        }
    }

    func readRange(_ dids: [UInt16], module: UInt32, stopAfterMisses: Int?,
                   naming: (UInt16) -> (String?, Confidence?)) async throws -> IdentificationResult {
        var result = IdentificationResult()
        var silent = 0
        var misses = 0
        for did in dids {
            let reply = try await uds.readDID(did, from: module)
            switch reply.outcome {
            case .noResponse:
                silent += 1
                if silent >= 3 {
                    result.issues.append("Steuergerät \(Hex.canID(module, extended: false)) antwortet nicht mehr, Lesen abgebrochen")
                    return result
                }
            case .negative(0x31):
                silent = 0
                misses += 1
                result.unsupportedCount += 1
                if let stopAfterMisses, misses >= stopAfterMisses { return result }
            default:
                silent = 0
                misses = 0
                let (name, confidence) = naming(did)
                result.readings.append(Self.reading(did: did, reply: reply, knowledge: knowledge, name: name, confidence: confidence))
            }
        }
        return result
    }

    public static func reading(did: UInt16, reply: UDSReply, knowledge: KnowledgeBase, name: String? = nil, confidence: Confidence? = nil) -> DIDReading {
        let definition = knowledge.did(did)
        var reading = DIDReading(
            did: hex(did),
            name: name ?? definition?.nameDE ?? "Kennung \(hex(did))",
            confidence: confidence ?? definition?.confidence ?? .unknown,
            status: .noResponse,
            requestHex: Hex.encode(reply.request),
            responseHex: reply.response.map { Hex.encode($0) })
        switch reply.outcome {
        case .noResponse:
            break
        case .negative(let code):
            reading.status = .negative
            reading.negativeResponseCode = Hex.byteString(code)
            reading.negativeResponseText = NegativeResponseCode.german(code)
        case .positive(let value):
            reading.status = .value
            reading.hex = Hex.encode(value)
            reading.text = printable(value)
            if let text = reading.text {
                if (did == 0xF190 || definition?.format == .vin), OBDVehicleInfo.isValidVIN(text) {
                    reading.vin = text
                }
                if let part = FordPartNumber(text) {
                    reading.partNumber = part
                    reading.partNumberModule = knowledge.partNumberBase(part.base)?.nameDE
                }
            }
        }
        return reading
    }

    static func hex(_ did: UInt16) -> String {
        Hex.encode([UInt8(did >> 8), UInt8(did & 0xFF)])
    }

    /// Text only if every byte is printable ASCII after removing zero and space padding.
    static func printable(_ bytes: [UInt8]) -> String? {
        var end = bytes.count
        while end > 0, bytes[end - 1] == 0x00 || bytes[end - 1] == 0x20 {
            end -= 1
        }
        let trimmed = bytes[..<end]
        guard !trimmed.isEmpty, trimmed.allSatisfy({ (0x20...0x7E).contains($0) }) else { return nil }
        return String(decoding: trimmed, as: UTF8.self)
    }
}
