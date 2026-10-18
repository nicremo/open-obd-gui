import AdapterKit
import Foundation
import OBDCore
import VehicleSim
@testable import DiagnosticEngine

enum TestRig {
    static func driver(_ profile: VehicleProfile = .mondeoMk4, bus: BusKind? = .hsCAN) async throws -> AdapterDriver {
        let driver = AdapterDriver(link: SimulatedLink(profile: profile))
        _ = try await driver.initialize()
        if let bus {
            try await driver.selectBus(bus)
        }
        return driver
    }

    static func value(_ measurement: MeasurementRecord?) -> Double? {
        measurement?.primaryValue?.numericValue
    }
}
