import AdapterKit
import Foundation
import OBDCore

public enum ScanDepth: String, Sendable, Codable, CaseIterable {
    case quick
    case standard
    case deep

    public var german: String {
        switch self {
        case .quick: "Schnell"
        case .standard: "Standard"
        case .deep: "Tief"
        }
    }

    public var explanation: String {
        switch self {
        case .quick: "OBD-Daten und Fehlerspeicher der Steuergeräte am HS-CAN."
        case .standard: "Zusätzlich MS-CAN, Kennungen, Freeze Frame und eine Momentaufnahme aller Messwerte."
        case .deep: "Zusätzlich alle Adressen, alle Kennungen F100 bis F1FF, Fehlerdetails und Konfigurationsblöcke."
        }
    }
}

public enum ScanStep: String, Sendable, Codable, CaseIterable {
    case adapter
    case obdSupport
    case obdReadiness
    case obdTroubleCodes
    case obdVehicleInfo
    case obdFreezeFrame
    case obdSnapshot
    case discoveryHS
    case discoveryMS
    case identification
    case moduleTroubleCodes
    case troubleCodeDetails
    case asBuilt

    public var title: String {
        switch self {
        case .adapter: "Adapter prüfen"
        case .obdSupport: "OBD-Steuergeräte finden"
        case .obdReadiness: "Bereitschaftstests lesen"
        case .obdTroubleCodes: "OBD-Fehlerspeicher lesen"
        case .obdVehicleInfo: "Fahrzeugdaten lesen"
        case .obdFreezeFrame: "Freeze Frame lesen"
        case .obdSnapshot: "Messwerte erfassen"
        case .discoveryHS: "Steuergeräte am HS-CAN suchen"
        case .discoveryMS: "Steuergeräte am MS-CAN suchen"
        case .identification: "Steuergeräte identifizieren"
        case .moduleTroubleCodes: "Fehlerspeicher der Steuergeräte lesen"
        case .troubleCodeDetails: "Fehlerdetails lesen"
        case .asBuilt: "Konfigurationsblöcke lesen"
        }
    }

    public func isIncluded(in depth: ScanDepth) -> Bool {
        switch self {
        case .adapter, .obdSupport, .obdReadiness, .obdTroubleCodes, .obdVehicleInfo, .discoveryHS, .moduleTroubleCodes:
            true
        case .obdFreezeFrame, .obdSnapshot, .discoveryMS, .identification:
            depth != .quick
        case .troubleCodeDetails, .asBuilt:
            depth == .deep
        }
    }
}

/// Progress and traffic of a session, for the GUI, verbose CLI output and agents.
public enum EngineEvent: Sendable, Codable {
    case stepStarted(ScanStep)
    case stepFinished(ScanStep, summary: String)
    case stepSkipped(ScanStep, reason: String)
    case stepFailed(ScanStep, message: String)
    case moduleFound(DiscoveredModule)
    case troubleCodeFound(ReportDTC)
    case traffic(TrafficEvent)
    case scanFinished(ReportSummary)
}

public struct AdapterSummary: Sendable, Codable, Equatable {
    public var link: String
    public var identity: AdapterIdentity
    public var voltage: Double?
    public var msCANAvailable: Bool
    public var simulated: Bool
}

public enum SessionState: Sendable, Equatable {
    case idle
    case connected
    case working(String)
    case closed
}
