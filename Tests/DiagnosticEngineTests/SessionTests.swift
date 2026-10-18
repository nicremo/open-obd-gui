import AdapterKit
import Foundation
import Synchronization
import Testing
import OBDCore
import VehicleSim
@testable import DiagnosticEngine

/// Holds one adapter command until the test releases it, to make concurrency deterministic.
actor Gate {
    private var arrived = false
    private var open = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var passWaiters: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        arrived = true
        arrivalWaiters.forEach { $0.resume() }
        arrivalWaiters = []
        guard !open else { return }
        await withCheckedContinuation { passWaiters.append($0) }
    }

    func waitForArrival() async {
        guard !arrived else { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    func release() {
        open = true
        passWaiters.forEach { $0.resume() }
        passWaiters = []
    }
}

struct GatedLink: AdapterLink {
    let base: SimulatedLink
    let gate: Gate
    let trigger: String
    var label: String { base.label }

    func transact(_ command: String, timeout: Duration) async throws -> LinkReply {
        if command.uppercased().contains(trigger) { await gate.pass() }
        return try await base.transact(command, timeout: timeout)
    }

    func close() async {}
}

@Suite struct SessionTests {
    func session(_ profile: VehicleProfile = .mondeoMk4) -> DiagnosticSession {
        DiagnosticSession(link: SimulatedLink(profile: profile), simulated: true, vehicleTitle: profile.title)
    }

    @Test func quickScanCoversOBDAndHSModules() async throws {
        let report = try await session().scan(depth: .quick)
        #expect(report.modules.map(\.acronym) == ["IPC", "RCM", "ABS", "PCM"])
        #expect(report.obd.ecus.map(\.address) == ["7E8"])
        #expect(Set(report.allTroubleCodes.map(\.displayCode)) == ["P0401", "P0401-00", "U0100-87", "B1318-16"])
        #expect(report.allTroubleCodes.count == 5)
        #expect(report.vehicle.vin == VehicleProfile.mondeoVIN)
        #expect(report.meta.steps.filter { $0.outcome == .skipped }.map(\.step) == [.obdFreezeFrame, .obdSnapshot, .discoveryMS, .identification, .troubleCodeDetails, .asBuilt])
        #expect(report.meta.steps.allSatisfy { $0.outcome != .failed })
        #expect(Set(report.findings.map(\.kind)).isSuperset(of: [.milOn, .simulated, .readinessIncomplete]))
        #expect(report.vehicle.title == "Ford Mondeo Mk4 2.0 TDCi (Simulator)")
    }

    @Test func standardScanReadsBothBusesAndIdentifies() async throws {
        let report = try await session().scan(depth: .standard)
        #expect(report.modules.count == 8)
        #expect(report.modules.filter { $0.bus == .msCAN }.map(\.acronym) == ["BCM", "ACM", "HVAC", "DDM"])
        let pcm = try #require(report.modules.first { $0.acronym == "PCM" })
        #expect(pcm.nameSource == "Adresse und Teilenummer passen zusammen")
        #expect(pcm.identification.contains { $0.did == "F113" && $0.text == "SIM1-12A650-AB" })
        #expect(report.allTroubleCodes.contains { $0.displayCode == "U0155-87" })
        let ecu = try #require(report.obd.ecus.first)
        #expect(ecu.freezeFrame.first?.primaryValue == .text("P0401"))
        #expect(!ecu.snapshot.isEmpty)
        #expect(ecu.info?.calibrationIDs == ["SIM1-12A650-AA"])
        #expect(!report.findings.contains { $0.kind == .vinMismatch })
        #expect(report.vehicle.vinSources.count >= 4)
    }

    @Test func deepScanAddsDetailsAndAsBuilt() async throws {
        let report = try await session().scan(depth: .deep)
        let bcm = try #require(report.modules.first { $0.acronym == "BCM" })
        #expect(bcm.asBuilt.map(\.did) == ["DE00", "DE01"])
        let pcmCode = try #require(report.allTroubleCodes.first { $0.displayCode == "P0401-00" })
        #expect(pcmCode.snapshotHex?.hasPrefix("04") == true)
        #expect(report.meta.steps.allSatisfy { $0.outcome == .ok })
    }

    @Test func focusIsGasolineWithoutMSModules() async throws {
        let report = try await session(.focusMk4).scan(depth: .standard)
        #expect(report.modules.count == 9)
        #expect(report.modules.allSatisfy { $0.bus == .hsCAN })
        let ecu = try #require(report.obd.ecus.first)
        #expect(ecu.readiness?.ignition == .spark)
        #expect(ecu.readiness?.milOn == false)
        let odometer = try #require(ecu.snapshot.first { $0.name == "Kilometerstand" })
        #expect(odometer.primaryValue == .number(36000, unit: "km"))
        #expect(report.summary.headline == "1 Fehler in 1 Steuergerät.")
    }

    @Test func eventsDescribeTheScan() async throws {
        let session = session()
        let collector = Task { () -> [String] in
            var names: [String] = []
            for await event in session.events {
                switch event {
                case .stepStarted(let step): names.append("start:\(step.rawValue)")
                case .moduleFound(let module): names.append("module:\(module.requestHex)")
                case .scanFinished: names.append("finished"); return names
                default: continue
                }
            }
            return names
        }
        _ = try await session.scan(depth: .quick)
        let names = await collector.value
        #expect(names.first == "start:adapter")
        #expect(names.contains("module:7E0"))
        #expect(names.last == "finished")
    }

    @Test func secondOperationWhileScanningIsBusy() async throws {
        let gate = Gate()
        let session = DiagnosticSession(link: GatedLink(base: SimulatedLink(profile: .mondeoMk4), gate: gate, trigger: "D:0100"), simulated: true)
        let scan = Task { try await session.scan(depth: .quick) }
        await gate.waitForArrival()
        await #expect(throws: OBDError.busy) { _ = try await session.readDID(0xF190, request: 0x7E0, bus: .hsCAN) }
        await gate.release()
        _ = try await scan.value
        #expect(try await session.readDID(0xF190, request: 0x7E0, bus: .hsCAN).vin == VehicleProfile.mondeoVIN)
    }

    @Test func ignitionOffGivesAnHonestReport() async throws {
        let link = SimulatedLink(profile: .mondeoMk4)
        await link.adapter.setIgnition(false)
        let report = try await DiagnosticSession(link: link, simulated: true).scan(depth: .quick)
        #expect(report.summary.headline == "Keine Antwort vom Fahrzeug.")
        #expect(report.findings.first?.kind == .noVehicleResponse)
        #expect(report.warnings.contains { $0.contains("Zündung") })
    }

    @Test func individualOperations() async throws {
        let session = session()
        let summary = try await session.connect()
        #expect(summary.identity.device == "OBDLink EX (Simulator)")
        #expect(summary.msCANAvailable)
        #expect(await session.state == .connected)
        #expect(try await session.discoverModules().count == 8)
        #expect(try await session.readModuleTroubleCodes(request: 0x760, bus: .hsCAN).map(\.displayCode) == ["U0100-87"])
        #expect(try await session.readOBDTroubleCodes().map(\.source) == [.obdStored, .obdPermanent])
        #expect(try await session.identify(request: 0x726, bus: .msCAN).readings.contains { $0.did == "F111" })
        #expect(try await session.supportedPIDs()[0x7E8]?.contains(0x0C) == true)
        #expect(try await session.readPIDs([0x0C, 0x0D]).map(\.name) == ["Motordrehzahl", "Fahrzeuggeschwindigkeit"])
        await #expect(throws: OBDError.self) { _ = try await session.rawRequest([0x2E, 0xF1, 0x90, 0x00], target: .module(0x7E0), bus: .hsCAN) }
        let raw = try await session.rawRequest([0x22, 0xF1, 0x90], target: .module(0x7E0), bus: .hsCAN)
        #expect(raw.payloads(from: 0x7E8).first?.prefix(3) == [0x62, 0xF1, 0x90])
    }

    @Test func closedSessionRefusesWork() async throws {
        let session = session()
        await session.close()
        #expect(await session.state == .closed)
        await #expect(throws: OBDError.disconnected) { _ = try await session.scan(depth: .quick) }
        var iterator = session.events.makeAsyncIterator()
        while await iterator.next() != nil {}
    }
}

@Suite struct SummaryTests {
    @Test func sameFaultViaOBDAndUDSCountsOnce() async throws {
        let report = try await DiagnosticSession(link: SimulatedLink(profile: .mondeoMk4), simulated: true).scan(depth: .standard)
        #expect(report.summary.troubleCodeCount == 6)
        #expect(report.summary.faultCount == 4)
        #expect(report.summary.headline == "4 Fehler in 4 Steuergeräten. 1 davon dringend.")
        #expect(report.summary.highlights.filter { $0.hasPrefix("P0401") }.count == 1)
        #expect(Set(report.allTroubleCodes.filter { $0.code == "P0401" }.map(\.module)) == ["7E0"])
    }
}
