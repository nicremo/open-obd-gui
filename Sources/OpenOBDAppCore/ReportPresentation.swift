import DiagnosticEngine
import Foundation
import OBDCore

/// Read helpers on the report that the screens need in several places.
extension VehicleReport {
    public var worstSeverity: Severity? {
        allTroubleCodes.map(\.severity).max()
    }

    public var primaryReadiness: ReadinessReport? {
        obd.ecus.compactMap(\.readiness).first
    }

    /// Odometer from PID A6, only if the vehicle reports it.
    public var odometer: Double? {
        obd.ecus.flatMap(\.snapshot).first { $0.id.hasSuffix(":01:A6") }?.primaryValue?.numericValue
    }

    public var snapshot: [MeasurementRecord] {
        obd.ecus.flatMap(\.snapshot)
    }

    public func module(for address: String) -> ReportModule? {
        modules.first { $0.requestID == address }
    }

    /// Trouble codes filed under a module address, OBD and UDS together.
    public func faults(of address: String) -> [ReportDTC] {
        allTroubleCodes.filter { $0.module == address }
    }

    public func moduleLabel(for address: String) -> String {
        if let module = module(for: address) {
            return module.acronym.map { "\($0) \(module.name)" } ?? module.name
        }
        return "OBD-Steuergerät \(address)"
    }
}
