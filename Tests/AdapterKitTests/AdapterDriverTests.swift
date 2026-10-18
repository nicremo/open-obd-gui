import Foundation
import Synchronization
import Testing
import OBDCore
@testable import AdapterKit

extension ReplayExchange {
    static func ok(_ command: String) -> ReplayExchange { ReplayExchange(command: command, reply: "OK\r\r") }
    static func text(_ command: String, _ reply: String) -> ReplayExchange { ReplayExchange(command: command, reply: reply + "\r\r") }
}

enum Script {
    static let stnInit: [ReplayExchange] = [
        .text("ATZ", "ATZ\r\r\rELM327 v1.4b"),
        .text("ATE0", "ATE0\rOK"),
        .ok("ATL0"), .ok("ATS1"), .ok("ATH1"), .ok("ATCAF1"), .ok("ATAT1"),
        .text("ATI", "ELM327 v1.4b"),
        .text("STI", "STN2232 v5.10.3"),
        .text("STDI", "OBDLink EX r1.1"),
        .text("STMFR", "OBD Solutions LLC"),
        .text("STSN", "112233445566"),
        .text("ATRV", "12.4V"),
    ]
    static let elmInit: [ReplayExchange] = [
        .text("ATZ", "ELM327 v1.5"),
        .ok("ATE0"), .ok("ATL0"), .ok("ATS1"), .ok("ATH1"), .ok("ATCAF1"), .ok("ATAT1"),
        .text("ATI", "ELM327 v1.5"),
        .text("STI", "?"),
        .text("ATRV", "12.1V"),
    ]
    static let hsCAN: [ReplayExchange] = [.ok("STP33"), .text("STPR", "33"), .ok("ATCRA")]
}

@Suite struct AdapterDriverTests {
    @Test func initializesAnSTNAdapter() async throws {
        let driver = AdapterDriver(link: ReplayLink(exchanges: Script.stnInit))
        let identity = try await driver.initialize()
        #expect(identity == AdapterIdentity(elmVersion: "ELM327 v1.4b", stnFirmware: "STN2232 v5.10.3", device: "OBDLink EX r1.1",
                                            manufacturer: "OBD Solutions LLC", serialNumber: "112233445566"))
        #expect(identity.isSTN)
        #expect(identity.displayName == "OBDLink EX r1.1")
        #expect(await driver.voltage == 12.4)
    }

    @Test func functionalRequestCollectsAllOBDResponders() async throws {
        let replay = ReplayLink(exchanges: Script.stnInit + Script.hsCAN + [
            .text("STPX h:7DF, d:0100, t:300", "7E8 06 41 00 BE 3F A8 13\r7E9 06 41 00 98 18 80 11"),
        ])
        let driver = AdapterDriver(link: replay)
        _ = try await driver.initialize()
        try await driver.selectBus(.hsCAN)
        #expect(await driver.activeBus == .hsCAN)
        let result = try await driver.request([0x01, 0x00], to: .functional)
        #expect(result.messages.count == 2)
        #expect(result.payloads(from: 0x7E8) == [[0x41, 0x00, 0xBE, 0x3F, 0xA8, 0x13]])
        #expect(await replay.remaining == 0)
    }

    @Test func physicalRequestSetsTheFilterOnceAndReassembles() async throws {
        let replay = ReplayLink(exchanges: Script.stnInit + Script.hsCAN + [
            .ok("ATCRA72E"),
            .text("STPX h:726, d:22F190, t:300, r:1",
                  "72E 10 14 62 F1 90 57 46 30\r72E 21 44 58 58 47 42 42 44\r72E 22 53 4D 31 32 33 34 35"),
            .text("STPX h:726, d:22F188, t:300, r:1", "72E 07 62 F1 88 53 49 4D 31"),
        ])
        let driver = AdapterDriver(link: replay)
        _ = try await driver.initialize()
        try await driver.selectBus(.hsCAN)
        let vin = try await driver.request([0x22, 0xF1, 0x90], to: .module(0x726), expectedResponses: 1)
        #expect(vin.payloads(from: 0x72E) == [[0x62, 0xF1, 0x90] + Array("WF0DXXGBBDSM12345".utf8)])
        let software = try await driver.request([0x22, 0xF1, 0x88], to: .module(0x726), expectedResponses: 1)
        #expect(software.payloads(from: 0x72E) == [[0x62, 0xF1, 0x88, 0x53, 0x49, 0x4D, 0x31]])
        #expect(await replay.remaining == 0)
    }

    @Test func probeAcceptsAnyDiagnosticResponder() async throws {
        let replay = ReplayLink(exchanges: Script.stnInit + Script.hsCAN + [
            .ok("ATCF700"), .ok("ATCM700"),
            .text("STPX h:7A0, d:3E00, t:80, r:1", "7A8 02 7E 00 00 00 00 00"),
            .text("STPX h:7A1, d:3E00, t:80, r:1", "NO DATA"),
        ])
        let driver = AdapterDriver(link: replay)
        _ = try await driver.initialize()
        try await driver.selectBus(.hsCAN)
        let found = try await driver.request([0x3E, 0x00], to: .probe(request: 0x7A0), timeout: .milliseconds(80), expectedResponses: 1)
        #expect(found.messages == [ISOTPMessage(source: CANIdentifier(0x7A8), payload: [0x7E, 0x00])])
        let silent = try await driver.request([0x3E, 0x00], to: .probe(request: 0x7A1), timeout: .milliseconds(80), expectedResponses: 1)
        #expect(silent.isEmpty)
    }

    @Test func writeRequestsNeverReachTheAdapter() async throws {
        let replay = ReplayLink(exchanges: Script.stnInit + Script.hsCAN)
        let driver = AdapterDriver(link: replay)
        _ = try await driver.initialize()
        try await driver.selectBus(.hsCAN)
        await #expect(throws: OBDError.self) { _ = try await driver.request([0x2E, 0xF1, 0x90, 0x00], to: .module(0x7E0)) }
        await #expect(throws: OBDError.self) { _ = try await driver.request([0x27, 0x01], to: .module(0x7E0)) }
        #expect(await replay.remaining == 0)
    }

    @Test func timeoutResynchronizesAndRethrows() async throws {
        let replay = ReplayLink(exchanges: Script.stnInit + Script.hsCAN + [
            ReplayExchange(command: "STPX h:7DF, d:0100, t:300", reply: "", failure: "TIMEOUT"),
            .text("ATI", "STOPPED"),
            .text("ATI", "ELM327 v1.4b"),
        ])
        let driver = AdapterDriver(link: replay)
        _ = try await driver.initialize()
        try await driver.selectBus(.hsCAN)
        await #expect(throws: OBDError.self) { _ = try await driver.request([0x01, 0x00], to: .functional) }
        #expect(await replay.remaining == 0)
    }

    @Test func adapterErrorsBecomeTypedErrors() async throws {
        let replay = ReplayLink(exchanges: Script.stnInit + Script.hsCAN + [
            .text("STPX h:7DF, d:0100, t:300", "CAN ERROR"),
            .text("STPX h:7DF, d:0101, t:300", "BUFFER FULL"),
            .text("STPX h:7DF, d:0105, t:300", "?"),
            .text("STPX h:7DF, d:010C, t:300", "NO DATA"),
        ])
        let driver = AdapterDriver(link: replay)
        _ = try await driver.initialize()
        try await driver.selectBus(.hsCAN)
        await #expect(throws: OBDError.canError) { _ = try await driver.request([0x01, 0x00], to: .functional) }
        await #expect(throws: OBDError.bufferFull) { _ = try await driver.request([0x01, 0x01], to: .functional) }
        await #expect(throws: OBDError.self) { _ = try await driver.request([0x01, 0x05], to: .functional) }
        #expect(try await driver.request([0x01, 0x0C], to: .functional).isEmpty)
    }

    @Test func missingMSCANIsReported() async throws {
        let replay = ReplayLink(exchanges: Script.stnInit + [.text("STP53", "?")])
        let driver = AdapterDriver(link: replay)
        _ = try await driver.initialize()
        #expect(await driver.isBusAvailable(.msCAN))
        await #expect(throws: OBDError.self) { try await driver.selectBus(.msCAN) }
        #expect(await driver.isBusAvailable(.msCAN) == false)
        #expect(await driver.activeBus == nil)
    }

    @Test func genericELMUsesHeadersAndOnlyHSCAN() async throws {
        let replay = ReplayLink(exchanges: Script.elmInit + [
            .ok("ATSP6"), .ok("ATCRA"), .ok("ATSH7DF"),
            .text("0100", "7E8 06 41 00 BE 3F A8 13"),
        ])
        let driver = AdapterDriver(link: replay)
        let identity = try await driver.initialize()
        #expect(!identity.isSTN)
        #expect(await driver.isBusAvailable(.msCAN) == false)
        await #expect(throws: OBDError.self) { try await driver.selectBus(.msCAN) }
        try await driver.selectBus(.hsCAN)
        #expect(try await driver.request([0x01, 0x00], to: .functional).messages.count == 1)
        #expect(await replay.remaining == 0)
    }

    @Test func trafficIsReported() async throws {
        let events = Mutex<[TrafficEvent.Direction]>([])
        let driver = AdapterDriver(link: ReplayLink(exchanges: Script.stnInit)) { event in
            events.withLock { $0.append(event.direction) }
        }
        _ = try await driver.initialize()
        let directions = events.withLock { $0 }
        #expect(directions.count == Script.stnInit.count * 2)
        #expect(directions.first == .sent)
        #expect(directions.last == .received)
    }

    @Test func requestsBeforeInitializationFail() async throws {
        let driver = AdapterDriver(link: ReplayLink(exchanges: []))
        await #expect(throws: OBDError.adapterNotResponding) { _ = try await driver.request([0x01, 0x00], to: .functional) }
    }

    @Test func stnFirmwareDetection() {
        #expect(AdapterIdentity.isSTNFirmware("STN2232 v5.10.3"))
        #expect(AdapterIdentity.isSTNFirmware("STN1170 v4.2.0 [2019.01.01]"))
        #expect(!AdapterIdentity.isSTNFirmware("?"))
        #expect(!AdapterIdentity.isSTNFirmware("ELM327 v1.5"))
        #expect(!AdapterIdentity.isSTNFirmware("STN22 v5.10.3"))
        #expect(!AdapterIdentity.isSTNFirmware("STN2232 5.10.3"))
    }
}
