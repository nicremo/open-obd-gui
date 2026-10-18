import AdapterKit
import Foundation
import Testing
import OBDCore
import VehicleSim
@testable import DiagnosticEngine

@Suite struct OBDServiceTests {
    @Test func supportedPIDsFollowTheChainAndDropQueries() async throws {
        let supported = try await OBDService(driver: TestRig.driver()).supportedPIDs()
        #expect(supported.keys.sorted() == [0x7E8])
        let pcm = try #require(supported[0x7E8])
        #expect(pcm.isSuperset(of: [0x01, 0x04, 0x05, 0x0C, 0x0D, 0x23, 0x42, 0x49]))
        #expect(!pcm.contains(0x20) && !pcm.contains(0x40))
    }

    @Test func measurementCarriesProvenance() async throws {
        let rpm = try #require(try await OBDService(driver: TestRig.driver()).readPID(0x0C).first)
        #expect(rpm.name == "Motordrehzahl")
        #expect((790...2350).contains(try #require(TestRig.value(rpm))))
        #expect(rpm.provenance.ecu == "7E8")
        #expect(rpm.provenance.bus == .hsCAN)
        #expect(rpm.provenance.requestHex == "010C")
        #expect(rpm.provenance.responseHex.hasPrefix("410C"))
        #expect(rpm.definition.confidence == .standard)
        #expect(rpm.id == "7E8:01:0C")
    }

    @Test func undecodableDataStaysRaw() {
        let service = OBDService(driver: AdapterDriver(link: SimulatedLink(profile: .mondeoMk4)), now: { Date(timeIntervalSince1970: 0) })
        let measurement = service.measurement(service: 0x01, pid: 0x0C, data: [0x1A], source: CANIdentifier(0x7E8), request: [0x01, 0x0C], response: [0x41, 0x0C, 0x1A])
        #expect(measurement.primaryValue == .raw([0x1A]))
        #expect(measurement.definition.confidence == .unknown)
    }

    @Test func dieselReadinessWithMIL() async throws {
        let readiness = try #require(try await OBDService(driver: TestRig.driver()).readReadiness()[0x7E8])
        #expect(readiness.ignition == .compression)
        #expect(readiness.milOn == true)
        #expect(readiness.incompleteMonitors.map(\.name) == ["Ladedruck"])
    }

    @Test func troubleCodesPerService() async throws {
        let obd = OBDService(driver: try await TestRig.driver())
        #expect(try await obd.readTroubleCodes(service: 0x03)[0x7E8] == [DTCCode("P0401")!])
        #expect(try await obd.readTroubleCodes(service: 0x07)[0x7E8] == [])
        #expect(try await obd.readTroubleCodes(service: 0x0A)[0x7E8] == [DTCCode("P0401")!])
    }

    @Test func vehicleInformationFullAndQuick() async throws {
        let obd = OBDService(driver: try await TestRig.driver())
        let full = try #require(try await obd.readVehicleInfo(full: true)[0x7E8])
        #expect(full.vin == VehicleProfile.mondeoVIN)
        #expect(full.calibrationIDs == ["SIM1-12A650-AA"])
        #expect(full.calibrationVerificationNumbers == ["5A3C1108"])
        #expect(full.ecuName == "ECM-EngineControl")
        #expect(full.supportedInfoTypes == [0x02, 0x04, 0x06, 0x0A])
        let quick = try #require(try await obd.readVehicleInfo(full: false)[0x7E8])
        #expect(quick.vin == VehicleProfile.mondeoVIN)
        #expect(quick.calibrationIDs.isEmpty)
    }

    @Test func freezeFrameNamesTheTrigger() async throws {
        let frame = try #require(try await OBDService(driver: TestRig.driver()).readFreezeFrame()[0x7E8])
        #expect(frame.first?.primaryValue == .text("P0401"))
        #expect(TestRig.value(frame.first { $0.id.hasSuffix(":02:0C") }) == 750)
        #expect(frame.allSatisfy { $0.definition.reference.contains("Dienst 02") })
    }

    @Test func snapshotReadsEverySupportedPIDOnce() async throws {
        let obd = OBDService(driver: try await TestRig.driver())
        let supported = try await obd.supportedPIDs()
        let snapshot = try #require(try await obd.readSnapshot(supported: supported)[0x7E8])
        #expect(snapshot.count == supported[0x7E8]!.subtracting([0x01, 0x02, 0x41]).count)
        #expect(Set(snapshot.map(\.id)).count == snapshot.count)
    }
}
