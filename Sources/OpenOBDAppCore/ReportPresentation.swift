import DiagnosticEngine
import Foundation
import OBDCore

/// Read helpers on the report that the screens need in several places.
extension VehicleReport {
    public var worstSeverity: Severity? {
        allTroubleCodes.map(\.severity).max()
    }

    /// False when not a single control unit answered. Zero faults then means "not read", never "no faults".
    public var vehicleAnswered: Bool {
        !findings.contains { $0.kind == .noVehicleResponse }
    }

    /// Why nothing answered, in the words the user can act on.
    public var silenceReason: String {
        (findings.first { $0.kind == .noVehiclePower } ?? findings.first { $0.kind == .noVehicleResponse })?.text
            ?? "Kein Steuergerät hat geantwortet."
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
