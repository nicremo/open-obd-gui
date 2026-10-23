import AdapterKit
import Foundation
import Testing
import OBDCore
@testable import DiagnosticEngine

/// Strict replays of captures from the real OBDLink EX (serial number redacted).
/// They pin the exact command sequence the hardware accepted.
@Suite struct HardwareReplayTests {
    static func fixture(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
    }

    @Test func identityOfTheRealOBDLinkEX() async throws {
        let replay = try ReplayLink.load(Self.fixture("obdlink-ex-identity"), mode: .strict)
        let driver = AdapterDriver(link: replay)
        let identity = try await driver.initialize()
        #expect(identity == AdapterIdentity(elmVersion: "ELM327 v1.4b", stnFirmware: "STN2232 v5.12.4", device: "OBDLink EX r2.7.1",
                                            manufacturer: "OBD Solutions LLC", serialNumber: "REDACTED"))
        #expect(await driver.isBusAvailable(.msCAN))
        // At the desk the EX runs on USB power alone, pin 16 carries nothing.
        #expect(await driver.voltage == 0)
        #expect(await replay.remaining == 0)
    }

    @Test func scanAtTheDeskReportsMissingVehiclePower() async throws {
        let replay = try ReplayLink.load(Self.fixture("obdlink-ex-no-vehicle-scan"), mode: .strict)
        let session = DiagnosticSession(link: replay)
        let report = try await session.scan(depth: .standard)
        let kinds = report.findings.map(\.kind)
        #expect(kinds.contains(.noVehiclePower))
        #expect(kinds.contains(.noVehicleResponse))
        #expect(!kinds.contains(.lowVoltage))
        #expect(report.modules.isEmpty)
        #expect(report.warnings.allSatisfy { $0.contains(OBDError.noVehiclePower(0).message) })
        #expect(await replay.remaining == 0)
    }
}
