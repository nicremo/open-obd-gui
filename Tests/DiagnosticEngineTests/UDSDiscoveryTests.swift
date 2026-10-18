import AdapterKit
import Foundation
import Testing
import FordKnowledge
import OBDCore
import VehicleSim
@testable import DiagnosticEngine

@Suite struct UDSDiscoveryTests {
    let knowledge = KnowledgeBase.bundled

    @Test func readsPositiveNegativeAndPendingDIDs() async throws {
        let uds = UDSService(driver: try await TestRig.driver())
        #expect(try await uds.readDID(0xF190, from: 0x7E0).outcome == .positive(Array(VehicleProfile.mondeoVIN.utf8)))
        #expect(try await uds.readDID(0xF17D, from: 0x7E0).outcome == .negative(0x31))
        #expect(try await uds.readDID(0xF113, from: 0x7E0).outcome == .positive(Array("SIM1-12A650-AB".utf8)))
        #expect(try await uds.readDID(0xF190, from: 0x7A0).outcome == .noResponse)
    }

    @Test func readsModuleTroubleCodes() async throws {
        let uds = UDSService(driver: try await TestRig.driver())
        let result = try await uds.readDTCs(from: 0x760)
        #expect(result.list?.dtcs.map(\.displayCode) == ["U0100-87"])
        #expect(try await uds.readDTCs(from: 0x737).list?.dtcs.isEmpty == true)
    }

    @Test func writesAreRefusedBeforeSending() async throws {
        let uds = UDSService(driver: try await TestRig.driver())
        await #expect(throws: OBDError.self) { _ = try await uds.send([0x2E, 0xF1, 0x90, 0x00], to: 0x7E0) }
        await #expect(throws: OBDError.self) { _ = try await uds.send([0x31, 0x01, 0xFF, 0x00], to: 0x7E0) }
    }

    @Test func discoveryFindsMondeoModulesPerBus() async throws {
        let driver = try await TestRig.driver(bus: nil)
        let discovery = ModuleDiscovery(driver: driver, knowledge: knowledge)
        let hs = try await discovery.discover(on: .hsCAN, sweep: false)
        #expect(hs.map(\.requestID) == [0x720, 0x737, 0x760, 0x7E0])
        #expect(hs.map(\.catalogAcronym) == ["IPC", "RCM", "ABS", "PCM"])
        #expect(hs.allSatisfy { $0.responseID == $0.requestID + 8 && $0.probe == "3E 00" && $0.bus == .hsCAN })
        let ms = try await discovery.discover(on: .msCAN, sweep: false)
        #expect(ms.map(\.requestHex) == ["726", "727", "733", "740"])
    }

    @Test func focusHasNothingOnMSCAN() async throws {
        let discovery = ModuleDiscovery(driver: try await TestRig.driver(.focusMk4, bus: nil), knowledge: knowledge)
        #expect(try await discovery.discover(on: .msCAN, sweep: false).isEmpty)
        #expect(try await discovery.discover(on: .hsCAN, sweep: false).count == 9)
    }

    @Test func sweepFindsUncataloguedModules() async throws {
        let hidden = VirtualECU(name: "UNKNOWN", request: 0x7A2, bus: .hsCAN, dids: [0xF111: Array("SIM9-99X999-AA".utf8)])
        let profile = VehicleProfile(id: "test", title: "Test", note: "Test", batteryVoltage: 12.5,
                                     ecus: VehicleProfile.mondeoMk4.ecus + [hidden])
        let discovery = ModuleDiscovery(driver: try await TestRig.driver(profile, bus: nil), knowledge: knowledge)
        #expect(!(try await discovery.discover(on: .hsCAN, sweep: false)).contains { $0.requestID == 0x7A2 })
        let swept = try await discovery.discover(on: .hsCAN, sweep: true)
        #expect(swept.contains { $0.requestID == 0x7A2 && $0.catalogAcronym == nil })
        #expect(Set(swept.map(\.responseID)).count == swept.count)
    }

    @Test func partNumbersAreDecomposed() {
        #expect(FordPartNumber("BG91-12A650-AGD") == FordPartNumber(prefix: "BG91", base: "12A650", suffix: "AGD"))
        #expect(FordPartNumber("NX7T-10849-SXB")?.base == "10849")
        #expect(FordPartNumber("BG9112A650AGD") == nil)
        #expect(FordPartNumber("bg91-12a650-agd") == nil)
        #expect(FordPartNumber("BG91-12A650-AGD")?.text == "BG91-12A650-AGD")
    }

    @Test func readingsAreDecodedWithoutGuessing() {
        let vin = Identification.reading(did: 0xF190, reply: UDSReply(outcome: .positive(Array(VehicleProfile.mondeoVIN.utf8)), request: [0x22, 0xF1, 0x90], response: [0x62, 0xF1, 0x90], elapsed: .zero), knowledge: knowledge)
        #expect(vin.vin == VehicleProfile.mondeoVIN)
        #expect(vin.name == "Fahrgestellnummer (VIN)")
        #expect(vin.confidence == .standard)

        let part = Identification.reading(did: 0xF111, reply: UDSReply(outcome: .positive(Array("SIM1-12A650-AA\0\0".utf8)), request: [0x22, 0xF1, 0x11], response: nil, elapsed: .zero), knowledge: knowledge)
        #expect(part.text == "SIM1-12A650-AA")
        #expect(part.partNumber?.base == "12A650")
        #expect(part.partNumberModule == "Motorsteuergerät")

        let binary = Identification.reading(did: 0xF18B, reply: UDSReply(outcome: .positive([0x20, 0x13, 0x05, 0x01]), request: [0x22, 0xF1, 0x8B], response: nil, elapsed: .zero), knowledge: knowledge)
        #expect(binary.text == nil)
        #expect(binary.hex == "20130501")
        #expect(binary.displayValue == "20130501")

        let refused = Identification.reading(did: 0xF110, reply: UDSReply(outcome: .negative(0x22), request: [0x22, 0xF1, 0x10], response: [0x7F, 0x22, 0x22], elapsed: .zero), knowledge: knowledge)
        #expect(refused.status == .negative)
        #expect(refused.negativeResponseCode == "22")
        #expect(refused.displayValue == "abgelehnt: Bedingungen nicht erfüllt")

        let unknown = Identification.reading(did: 0xF1A5, reply: UDSReply(outcome: .positive([0x01]), request: [0x22, 0xF1, 0xA5], response: nil, elapsed: .zero), knowledge: knowledge)
        #expect(unknown.name == "Kennung F1A5")
        #expect(unknown.confidence == .unknown)
    }

    @Test func identificationReadsTheStandardSet() async throws {
        let identification = Identification(uds: UDSService(driver: try await TestRig.driver()), knowledge: knowledge)
        let result = try await identification.read(module: 0x7E0, full: false)
        #expect(result.readings.map(\.did).contains("F190"))
        #expect(result.readings.first { $0.did == "F111" }?.partNumberModule == "Motorsteuergerät")
        #expect(result.readings.first { $0.did == "F113" }?.text == "SIM1-12A650-AB")
        #expect(result.unsupportedCount == Identification.standardSet.count - result.readings.count)
        #expect(result.issues.isEmpty)
    }

    @Test func identificationStopsWhenAModuleFallsSilent() async throws {
        let identification = Identification(uds: UDSService(driver: try await TestRig.driver()), knowledge: knowledge)
        let result = try await identification.read(module: 0x7A0, full: false)
        #expect(result.readings.isEmpty)
        #expect(result.issues.count == 1)
    }

    @Test func asBuiltBlocksAreRead() async throws {
        let identification = Identification(uds: UDSService(driver: try await TestRig.driver(bus: .msCAN)), knowledge: knowledge)
        let blocks = try await identification.readAsBuilt(module: 0x726)
        #expect(blocks.readings.map(\.did) == ["DE00", "DE01"])
        #expect(blocks.readings[0].hex == "2A2A800029")
        #expect(blocks.readings[0].name == "Konfigurationsblock DE00 (As-Built)")
        #expect(blocks.readings[0].confidence == .community)
    }
}
