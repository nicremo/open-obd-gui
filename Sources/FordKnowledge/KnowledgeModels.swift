import Foundation
import OBDCore

/// Rough position of a module in the car, used for the vehicle map in the app.
public enum VehicleZone: String, Codable, Sendable, CaseIterable {
    case engineBay, front, cabinFront, cabinCenter, cabinRear, doorsLeft, doorsRight, rear, roof
}

public struct ModuleDefinition: Codable, Sendable, Equatable, Identifiable {
    /// 11-bit request identifier as three hex digits, for example "7E0".
    public var request: String
    public var acronym: String
    public var nameDE: String
    public var nameEN: String
    public var buses: [BusKind]
    public var zone: VehicleZone
    public var confidence: Confidence
    public var source: String

    public var id: String { request }
    public var requestID: UInt32 { Hex.parseCANID(request) ?? 0 }
    /// Ford convention: response = request + 8.
    public var responseID: UInt32 { requestID + 8 }
}

public enum DIDFormat: String, Codable, Sendable {
    case text, vin, partNumber, hex
}

public struct DIDDefinition: Codable, Sendable, Equatable {
    /// Four hex digits, for example "F190".
    public var did: String
    public var nameDE: String
    public var nameEN: String
    public var format: DIDFormat
    public var confidence: Confidence
    public var source: String

    public var identifier: UInt16 { UInt16(did, radix: 16) ?? 0 }
}

public struct DTCTitle: Codable, Sendable, Equatable {
    public var code: String
    public var titleDE: String
    public var source: String
    public var confidence: Confidence

    public init(code: String, titleDE: String, source: String, confidence: Confidence) {
        self.code = code
        self.titleDE = titleDE
        self.source = source
        self.confidence = confidence
    }
}

/// Editorial explanation for people. Never a diagnosis.
public struct DTCExplanation: Codable, Sendable, Equatable {
    public var code: String
    public var what: String
    public var urgency: String
    public var causes: [String]
    public var source: String
    public var confidence: Confidence

    public init(code: String, what: String, urgency: String, causes: [String], source: String, confidence: Confidence) {
        self.code = code
        self.what = what
        self.urgency = urgency
        self.causes = causes
        self.source = source
        self.confidence = confidence
    }
}

public struct PartNumberBase: Codable, Sendable, Equatable {
    public var base: String
    public var acronym: String
    public var nameDE: String
    public var confidence: Confidence
    public var source: String
}

public struct WMIEntry: Codable, Sendable, Equatable {
    public var wmi: String
    public var manufacturerDE: String
    public var confidence: Confidence
    public var source: String
}

public struct VehicleHint: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var nameDE: String
    public var years: String
    public var platform: String
    public var expectedBuses: [BusKind]
    public var hints: [String]
    public var confidence: Confidence
    public var source: String
}

public struct KnowledgeError: Error, CustomStringConvertible, Equatable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
