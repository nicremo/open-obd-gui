import Foundation
import Synchronization
import Testing
import DiagnosticEngine
import OBDCore
@testable import OpenOBDAppCore

/// Counts events an agent receives.
final class EventLog: Sendable {
    private let events = Mutex<[EngineEvent]>([])

    func append(_ event: EngineEvent) {
        events.withLock { $0.append(event) }
    }

    var finishedSteps: [ScanStep] {
        events.withLock { $0.compactMap { if case .stepFinished(let step, _) = $0 { step } else { nil } } }
    }

    var trafficCount: Int {
        events.withLock { $0.filter { if case .traffic = $0 { true } else { false } }.count }
    }
}

@MainActor
@Suite struct AgentBridgeTests {
    func makeModel(_ profile: String = "mondeo-mk4") async -> AppModel {
        let store = ReportStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("openobd-agent-\(UUID().uuidString)"))
        let model = AppModel(store: store, discover: { [] })
        await model.select(.simulator(profile))
        return model
    }

    func waitFor(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }

    @Test func agentScanShowsInTheWindow() async throws {
        let model = await makeModel()
        let log = EventLog()
        let result = try await model.performForAgent(.scan(depth: .quick), events: { log.append($0) }, records: { _ in })
        guard case .report(let report) = result else { Issue.record("no report"); return }
        #expect(model.report == report)
        #expect(model.reportSource == .scan)
        #expect(model.phase == .connected)
        #expect(model.agentActivity == nil)
        // The window gets step updates through the event stream, a moment later.
        try await waitFor { model.steps.allSatisfy { $0.state != .pending && $0.state != .running } }
        #expect(model.archive.count == 1)
        #expect(log.finishedSteps.contains(.moduleTroubleCodes))
        #expect(log.trafficCount > 0)
    }

    @Test func agentReadsShareTheSessionAndTheConsole() async throws {
        let model = await makeModel()
        let result = try await model.performForAgent(.readDID(did: 0xF190, request: 0x726, bus: .msCAN), events: { _ in }, records: { _ in })
        guard case .reading(let reading) = result else { Issue.record("no reading"); return }
        #expect(reading.vin == "WF0DXXGBBDSM12345")
        #expect(model.adapter != nil)
        // The console gets traffic through the event stream, a moment later.
        try await waitFor { model.traffic.contains { $0.text.replacingOccurrences(of: " ", with: "").contains("22F190") } }
        #expect(model.agentActivity == nil)
    }

    @Test func busyAppTurnsAgentsAway() async throws {
        let model = await makeModel()
        await model.startLive()
        #expect(model.phase == .live)
        await #expect(throws: BridgeError.appBusy("Live-Daten laufen")) {
            _ = try await model.performForAgent(.readOBDTroubleCodes, events: { _ in }, records: { _ in })
        }
        model.stopLive()
        #expect(!model.isOccupied)
    }

    @Test func greetingTellsSimulatorFromCar() async {
        let model = await makeModel("focus-mk4")
        let hello = model.bridgeHello()
        #expect(hello.simulated)
        #expect(hello.link == "simulator:focus-mk4")
        #expect(!hello.connected)
        #expect(hello.activity == nil)
        let real = AppModel(store: ReportStore(directory: FileManager.default.temporaryDirectory), discover: { [] })
        #expect(!real.bridgeHello().simulated)
    }

    @Test func rejectedReadsDoNotTurnTheWindowRed() async throws {
        let model = await makeModel()
        await model.connect()
        await #expect(throws: OBDError.self) {
            _ = try await model.performForAgent(.raw(payload: [0x2E, 0xF1, 0x90, 0x00], target: .module(0x7E0), bus: .hsCAN, timeoutMilliseconds: 500),
                                                events: { _ in }, records: { _ in })
        }
        #expect(model.phase == .connected)
    }

    @Test func bridgeEndToEnd() async throws {
        let model = await makeModel()
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("oobd-\(UUID().uuidString.prefix(8)).sock").path
        model.startAgentBridge(at: path)
        #expect(model.agentBridge == .ready(path: path))
        let client = try await BridgeClient.connect(at: path)
        #expect(client.hello.app.hasPrefix("Open OBD GUI"))
        let report = try await client.scan(depth: .quick)
        #expect(model.report == report)
        let shown = try await client.lastReport()
        #expect(shown == report)
        await client.close()
        model.stopAgentBridge()
        #expect(model.agentBridge == .off)
        #expect(!BridgeClient.isReachable(at: path))
    }
}
