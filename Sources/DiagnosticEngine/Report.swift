import AdapterKit
import FordKnowledge
import Foundation
import OBDCore

/// Complete result of a scan. Schema `openobd.report/1`.
public struct VehicleReport: Sendable, Codable, Equatable {
    public static let schemaName = "openobd.report/1"

    public var schema: String
    public var meta: ReportMeta
    public var adapter: ReportAdapter
    public var vehicle: ReportVehicle
    public var summary: ReportSummary
    public var obd: ReportOBD
    public var modules: [ReportModule]
    public var findings: [Finding]
    public var warnings: [String]

    public var allTroubleCodes: [ReportDTC] {
        obd.ecus.flatMap(\.troubleCodes) + modules.flatMap(\.troubleCodes)
    }
}

public struct ReportMeta: Sendable, Codable, Equatable {
    public var tool: String
    public var createdAt: Date
    public var depth: ScanDepth
    public var durationMilliseconds: Int
    public var link: String
    public var simulated: Bool
    public var steps: [StepRecord]
}

public struct StepRecord: Sendable, Codable, Equatable {
    public enum Outcome: String, Sendable, Codable {
        case ok
        case skipped
        case failed
    }

    public var step: ScanStep
    public var title: String
    public var outcome: Outcome
    public var durationMilliseconds: Int
    public var detail: String
}

public struct ReportAdapter: Sendable, Codable, Equatable {
    public var identity: AdapterIdentity?
    public var voltage: Double?
    public var buses: [BusAvailability]
}

public struct BusAvailability: Sendable, Codable, Equatable {
    public var bus: BusKind
    public var available: Bool
    public var note: String?
}

public struct ReportVehicle: Sendable, Codable, Equatable {
    public var title: String
    public var vin: String?
    public var vinSources: [VINSource]
    public var vinInfo: VINInfo?
    public var profileHint: String?
}

public struct VINSource: Sendable, Codable, Equatable {
    public var source: String
    public var vin: String
}

public struct ReportOBD: Sendable, Codable, Equatable {
    public var protocolName: String?
    public var ecus: [ReportOBDECU]
}

public struct ReportOBDECU: Sendable, Codable, Equatable, Identifiable {
    public var address: String
    public var supportedPIDs: [String] = []
    public var readiness: ReadinessReport?
    public var readinessThisCycle: ReadinessReport?
    public var troubleCodes: [ReportDTC] = []
    public var info: OBDECUInfo?
    public var freezeFrame: [MeasurementRecord] = []
    public var snapshot: [MeasurementRecord] = []

    public var id: String { address }
}

public struct ReportModule: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var bus: BusKind
    public var requestID: String
    public var responseID: String
    public var responseMilliseconds: Int
    public var acronym: String?
    public var name: String
    public var nameConfidence: Confidence
    public var nameSource: String
    public var zone: VehicleZone?
    public var identification: [DIDReading] = []
    public var unsupportedIdentifiers = 0
    public var troubleCodes: [ReportDTC] = []
    public var troubleCodeSupport: String?
    public var asBuilt: [DIDReading] = []
    public var issues: [String] = []
}

public struct Finding: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case noVehicleResponse
        case vinMismatch
        case noVehiclePower
        case lowVoltage
        case milOn
        case readinessIncomplete
        case busUnavailable
        case simulated
    }

    public var kind: Kind
    public var severity: Severity
    public var text: String
    public var evidence: String
}

public struct ReportSummary: Sendable, Codable, Equatable {
    public var headline: String
    public var highlights: [String]
    public var moduleCount: Int
    /// Raw entries, one per source (OBD stored, pending, permanent, UDS).
    public var troubleCodeCount: Int
    /// Distinct faults: same module and same code count once.
    public var faultCount: Int
    public var bySeverity: [String: Int]
    public var milOn: Bool?
    public var vin: String?
}

public enum ReportCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(_ report: VehicleReport) throws -> Data {
        try encoder().encode(report)
    }

    public static func decode(_ data: Data) throws -> VehicleReport {
        let report = try decoder().decode(VehicleReport.self, from: data)
        guard report.schema == VehicleReport.schemaName else {
            throw OBDError.malformedResponse("Unbekanntes Berichtsformat \(report.schema)")
        }
        return report
    }
}
