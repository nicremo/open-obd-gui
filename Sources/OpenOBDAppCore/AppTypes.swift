import AdapterKit
import DiagnosticEngine
import Foundation
import OBDCore
import VehicleSim

public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case cockpit, faults, live, modules, vehicle, history, workshop

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cockpit: "Cockpit"
        case .faults: "Fehlerspeicher"
        case .live: "Live-Daten"
        case .modules: "Steuergeräte"
        case .vehicle: "Fahrzeug"
        case .history: "Verlauf"
        case .workshop: "Werkstatt"
        }
    }

    public var symbol: String {
        switch self {
        case .cockpit: "gauge.with.dots.needle.67percent"
        case .faults: "exclamationmark.triangle"
        case .live: "waveform.path.ecg"
        case .modules: "cpu"
        case .vehicle: "car"
        case .history: "clock.arrow.circlepath"
        case .workshop: "wrench.and.screwdriver"
        }
    }
}

public enum ConnectionChoice: Hashable, Sendable, Identifiable {
    case automatic
    case port(String)
    case simulator(String)

    public var id: String {
        switch self {
        case .automatic: "auto"
        case .port(let path): "port:\(path)"
        case .simulator(let profile): "sim:\(profile)"
        }
    }

    public var title: String {
        switch self {
        case .automatic: "Automatisch (OBDLink suchen)"
        case .port(let path): path.replacingOccurrences(of: "/dev/cu.", with: "")
        case .simulator(let profile): VehicleProfile.named(profile)?.title ?? profile
        }
    }

    public var simulatorProfile: String? {
        if case .simulator(let profile) = self { profile } else { nil }
    }
}

public enum StepState: Sendable, Equatable {
    case pending
    case running
    case done(String)
    case failed(String)
    case skipped(String)
}

public struct StepProgress: Identifiable, Sendable, Equatable {
    public let step: ScanStep
    public var state: StepState

    public var id: ScanStep { step }
}

public struct TrafficLine: Identifiable, Sendable, Equatable {
    public let id: Int
    public let direction: TrafficEvent.Direction
    public let text: String
    public let time: Date
}

/// Everything the technical inspector can show.
public enum InspectorItem: Equatable, Sendable {
    case troubleCode(ReportDTC)
    case measurement(MeasurementRecord)
    case module(ReportModule)
    case reading(DIDReading)
}

public enum ReportSource: Sendable, Equatable {
    case none
    case scan
    case archive
}

public struct RawOutcome: Sendable, Equatable {
    public let request: String
    public let lines: [String]
    public let error: String?
}
