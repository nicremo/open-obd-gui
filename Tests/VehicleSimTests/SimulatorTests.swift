import Foundation
import Testing
import AdapterKit
import OBDCore
@testable import VehicleSim

@Suite struct SimulatorTests {
    func driver(_ profile: VehicleProfile, identity: VirtualAdapterIdentity = .obdLinkEX) async throws -> AdapterDriver {
        let driver = AdapterDriver(link: SimulatedLink(profile: profile, identity: identity))
        _ = try await driver.initialize()
        return driver
    }

    @Test func profilesAreRegistered() {
        #expect(VehicleProfile.all.map(\.id) == ["mondeo-mk4", "focus-mk4"])
        #expect(VehicleProfile.named("focus-mk4")?.title.contains("Focus") == true)
        #expect(VehicleProfile.named("nope") == nil)
    }

    @Test func driverInitializesAgainstTheVirtualOBDLink() async throws {
        let driver = try await driver(.mondeoMk4)
        let identity = try #require(await driver.identity)
        #expect(identity.device == "OBDLink EX (Simulator)")
        #expect(identity.isSTN)
        #expect(await driver.voltage == 12.6)
    }

    @Test func functionalSupportQueryReachesThePCM() async throws {
        let driver = try await driver(.mondeoMk4)
        try await driver.selectBus(.hsCAN)
        let result = try await driver.request([0x01, 0x00], to: .functional)
        let payload = try #require(result.payloads(from: 0x7E8).first)
        let supported = try J1979.supportedPIDs(base: 0x00, mask: Array(payload.dropFirst(2)))
        #expect(supported.isSuperset(of: [0x01, 0x04, 0x05, 0x0C, 0x0D, 0x1C, 0x20]))
    }

    @Test func multiFrameDIDOnMSCAN() async throws {
        let driver = try await driver(.mondeoMk4)
        try await driver.selectBus(.msCAN)
        let result = try await driver.request([0x22, 0xF1, 0x90], to: .module(0x726), expectedResponses: 1)
        #expect(result.payloads(from: 0x72E) == [[0x62, 0xF1, 0x90] + Array(VehicleProfile.mondeoVIN.utf8)])
    }

    @Test func slowDIDSendsPendingFirst() async throws {
        let driver = try await driver(.mondeoMk4)
        try await driver.selectBus(.hsCAN)
        let payloads = try await driver.request([0x22, 0xF1, 0x13], to: .module(0x7E0), expectedResponses: 1).payloads(from: 0x7E8)
        #expect(payloads.count == 2)
        #expect(payloads[0] == [0x7F, 0x22, 0x78])
        #expect(payloads[1].prefix(3) == [0x62, 0xF1, 0x13])
    }

    @Test func probesFindOnlyModulesOnTheActiveBus() async throws {
        let driver = try await driver(.mondeoMk4)
        try await driver.selectBus(.hsCAN)
        let abs = try await driver.request([0x3E, 0x00], to: .probe(request: 0x760), timeout: .milliseconds(80), expectedResponses: 1)
        #expect(abs.messages.map(\.source.value) == [0x768])
        let bcmOnWrongBus = try await driver.request([0x3E, 0x00], to: .probe(request: 0x726), timeout: .milliseconds(80), expectedResponses: 1)
        #expect(bcmOnWrongBus.isEmpty)
        let nothing = try await driver.request([0x3E, 0x00], to: .probe(request: 0x7A0), timeout: .milliseconds(80), expectedResponses: 1)
        #expect(nothing.isEmpty)
    }

    @Test func udsTroubleCodesDecode() async throws {
        let driver = try await driver(.mondeoMk4)
        try await driver.selectBus(.hsCAN)
        let payload = try #require(try await driver.request([0x19, 0x02, 0xFF], to: .module(0x7E0), expectedResponses: 1).payloads(from: 0x7E8).first)
        guard case .positive(let data) = try UDSResponse.classify(payload, service: 0x19) else {
            Issue.record("positive Antwort erwartet")
            return
        }
        let list = try UDSCodec.decodeDTCByStatusMask(data)
        #expect(list.dtcs.map(\.displayCode) == ["P0401-00"])
        #expect(list.dtcs[0].status.contains(.warningIndicatorRequested))
    }

    @Test func freezeFrameSupportIsAnswered() {
        let pcm = VehicleProfile.mondeoMk4.ecus[0]
        let support = pcm.respond(to: [0x02, 0x00, 0x00], functional: true, time: 0)
        #expect(support.count == 1)
        let mask = Array(support[0].dropFirst(3))
        #expect((try? J1979.supportedPIDs(base: 0x00, mask: mask)) == [0x02, 0x04, 0x05, 0x0C, 0x0D])
        #expect(pcm.respond(to: [0x02, 0x0C, 0x00], functional: true, time: 0) == [[0x42, 0x0C, 0x00, 0x0B, 0xB8]])
    }

    @Test func ignitionOffSilencesTheVehicle() async throws {
        let link = SimulatedLink(profile: .mondeoMk4)
        let driver = AdapterDriver(link: link)
        _ = try await driver.initialize()
        try await driver.selectBus(.hsCAN)
        await link.adapter.setIgnition(false)
        #expect(try await driver.request([0x01, 0x00], to: .functional).isEmpty)
    }

    @Test func receiveFilterIsEnforcedLikeARealAdapter() async throws {
        let adapter = VirtualAdapter(profile: .mondeoMk4, identity: .obdLinkEX)
        for command in ["ATE0", "ATH1", "STP33", "ATSH760"] {
            _ = await adapter.handle(command)
        }
        #expect(await adapter.handle("22F190").contains("NO DATA"))
        _ = await adapter.handle("ATCRA768")
        #expect(await adapter.handle("22F190").contains("768 10 14 62 F1 90"))
    }

    @Test func genericELMHasNoMSCAN() async throws {
        let driver = try await driver(.mondeoMk4, identity: .genericELM)
        #expect(await driver.identity?.isSTN == false)
        await #expect(throws: OBDError.self) { try await driver.selectBus(.msCAN) }
        try await driver.selectBus(.hsCAN)
        #expect(try await driver.request([0x09, 0x02], to: .functional).payloads(from: 0x7E8).first?.count == 20)
    }

    @Test func focusHasNoModulesOnMSCAN() async throws {
        let driver = try await driver(.focusMk4)
        try await driver.selectBus(.msCAN)
        let probe = try await driver.request([0x3E, 0x00], to: .probe(request: 0x726), timeout: .milliseconds(80), expectedResponses: 1)
        #expect(probe.isEmpty)
        try await driver.selectBus(.hsCAN)
        let bcm = try await driver.request([0x3E, 0x00], to: .probe(request: 0x726), timeout: .milliseconds(80), expectedResponses: 1)
        #expect(bcm.messages.map(\.source.value) == [0x72E])
    }

    @Test(arguments: [1, 6, 7, 8, 13, 20, 62, 100, 4095])
    func segmentationRoundTrips(_ length: Int) throws {
        let message = (0..<length).map { UInt8($0 & 0xFF) }
        let frames = VirtualAdapter.segment(message).map { CANFrame(id: CANIdentifier(0x7E8), data: $0) }
        #expect(frames.allSatisfy { $0.data.count == 8 })
        #expect(try ISOTPReassembler.reassemble(frames) == [ISOTPMessage(source: CANIdentifier(0x7E8), payload: message)])
    }

    @Test func signalsStayWithinTheirRange() throws {
        let rpm = SimSignal.wave(800, 2400, period: 10, encode: SimEncode.rpm)
        for time in stride(from: 0.0, through: 20.0, by: 0.7) {
            let value = try #require(try J1979.decode(pid: 0x0C, data: rpm.bytes(at: time)).first?.value.numericValue)
            #expect((800...2400).contains(value))
        }
    }

    @Test func everyProfileECUAnswersTesterPresent() async throws {
        for profile in VehicleProfile.all {
            for ecu in profile.ecus {
                #expect(ecu.respond(to: [0x3E, 0x00], functional: false, time: 0) == [[0x7E, 0x00]], "\(profile.id) \(ecu.name)")
                #expect(ecu.response == ecu.request + 8)
            }
        }
    }
}
