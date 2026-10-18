import AdapterKit
import Foundation
import Testing
import OBDCore
import VehicleSim
@testable import DiagnosticEngine

/// A bridge server over the simulator at a short socket path that only this test uses.
struct BridgeRig {
    let path: String
    let session: DiagnosticSession
    let server: BridgeServer

    static func socketPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("oobd-\(UUID().uuidString.prefix(8)).sock").path
    }

    static func start(_ profile: VehicleProfile = .mondeoMk4) throws -> BridgeRig {
        let path = socketPath()
        let session = DiagnosticSession(link: SimulatedLink(profile: profile), simulated: true, vehicleTitle: profile.title, vehicleHint: profile.id)
        let server = try BridgeServer.start(at: path, handler: SessionBridgeHandler(session: session, appName: "Testbrücke"))
        return BridgeRig(path: path, session: session, server: server)
    }

    func stop() async {
        server.stop()
        await session.close()
    }
}

@Suite struct BridgeTests {
    @Test func greetingNamesTheAppAndItsLink() async throws {
        let rig = try BridgeRig.start()
        let client = try await BridgeClient.connect(at: rig.path)
        #expect(client.hello.app == "Testbrücke")
        #expect(client.hello.link == "simulator:mondeo-mk4")
        #expect(client.hello.simulated)
        #expect(!client.hello.connected)
        #expect(client.linkLabel == "app:simulator:mondeo-mk4")
        await client.close()
        await rig.stop()
    }

    @Test func scanRunsInTheServingSessionWithProgress() async throws {
        let rig = try BridgeRig.start()
        let client = try await BridgeClient.connect(at: rig.path)
        let collector = Task {
            var finished: [ScanStep] = []
            for await event in client.events {
                if case .stepFinished(let step, _) = event { finished.append(step) }
            }
            return finished
        }
        let report = try await client.scan(depth: .quick)
        #expect(report.modules.count == 4)
        #expect(report.vehicle.vin == "WF0DXXGBBDSM12345")
        #expect(await rig.session.lastReport == report)
        #expect(try await client.lastReport() == report)
        await client.close()
        let finished = await collector.value
        #expect(finished.contains(.adapter))
        #expect(finished.contains(.moduleTroubleCodes))
        await rig.stop()
    }

    @Test func readsMatchADirectSession() async throws {
        let rig = try BridgeRig.start()
        let client = try await BridgeClient.connect(at: rig.path)
        let reading = try await client.readDID(0xF190, request: 0x726, bus: .msCAN)
        #expect(reading.vin == "WF0DXXGBBDSM12345")
        let codes = try await client.readModuleTroubleCodes(request: 0x760, bus: .hsCAN)
        #expect(codes.map(\.displayCode) == ["U0100-87"])
        let pids = try await client.supportedPIDs()
        #expect(pids[0x7E8]?.contains(0x0C) == true)
        let identification = try await client.identify(request: 0x726, bus: .msCAN, full: false)
        #expect(identification.readings.contains { $0.did == "F111" })
        let raw = try await client.rawRequest([0x22, 0xF1, 0x90], target: .module(0x7E0), bus: .hsCAN, timeout: .milliseconds(500))
        let answer = Hex.encode(raw.messages.first?.payload ?? [])
        #expect(answer.hasPrefix("62F190"))
        await client.close()
        await rig.stop()
    }

    @Test func writeRequestsAreDeniedBeforeTheAdapter() async throws {
        let rig = try BridgeRig.start()
        let client = try await BridgeClient.connect(at: rig.path)
        await #expect(throws: OBDError.self) {
            _ = try await client.rawRequest([0x2E, 0xF1, 0x90, 0x00], target: .module(0x7E0), bus: .hsCAN, timeout: .milliseconds(500))
        }
        do {
            _ = try await client.rawRequest([0x2E, 0xF1, 0x90, 0x00], target: .module(0x7E0), bus: .hsCAN, timeout: .milliseconds(500))
        } catch let error as OBDError {
            #expect(error.code == "POLICY_DENIED")
        }
        await client.close()
        await rig.stop()
    }

    @Test func liveStopsWhenTheConsumerStops() async throws {
        let rig = try BridgeRig.start()
        let client = try await BridgeClient.connect(at: rig.path)
        var names: [String] = []
        for try await record in client.live(pids: [0x0C, 0x0D], interval: .milliseconds(20)) {
            names.append(record.name)
            if names.count == 3 { break }
        }
        #expect(names.first == "Motordrehzahl")
        // The session is free again once the cancelled stream ended in the app.
        var reading: DIDReading?
        for _ in 0..<40 where reading == nil {
            reading = try? await client.readDID(0xF190, request: 0x726, bus: .msCAN)
            if reading == nil { try await Task.sleep(for: .milliseconds(25)) }
        }
        #expect(reading?.vin == "WF0DXXGBBDSM12345")
        await client.close()
        await rig.stop()
    }

    @Test func reachabilityFollowsTheServer() async throws {
        let rig = try BridgeRig.start()
        #expect(BridgeClient.isReachable(at: rig.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: rig.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        await rig.stop()
        #expect(!BridgeClient.isReachable(at: rig.path))
        await #expect(throws: BridgeError.appNotRunning(path: rig.path)) {
            _ = try await BridgeClient.connect(at: rig.path)
        }
    }

    @Test func staleSocketIsReplacedAndALiveOneIsKept() async throws {
        let rig = try BridgeRig.start()
        #expect(throws: BridgeError.alreadyRunning(path: rig.path)) {
            _ = try BridgeServer.start(at: rig.path, handler: SessionBridgeHandler(session: rig.session))
        }
        await rig.stop()
        // A leftover file without a listener, as after a crash.
        FileManager.default.createFile(atPath: rig.path, contents: Data())
        let session = DiagnosticSession(link: SimulatedLink(profile: .focusMk4), simulated: true)
        let second = try BridgeServer.start(at: rig.path, handler: SessionBridgeHandler(session: session))
        let client = try await BridgeClient.connect(at: rig.path)
        #expect(client.hello.link == "simulator:focus-mk4")
        await client.close()
        second.stop()
        await session.close()
    }

    @Test func callsFailWhenTheAppGoesAway() async throws {
        let rig = try BridgeRig.start()
        let client = try await BridgeClient.connect(at: rig.path)
        let stream = client.live(pids: [0x0C], interval: .milliseconds(20))
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()
        rig.server.stop()
        do {
            while try await iterator.next() != nil {}
            Issue.record("stream ended without an error")
        } catch let error as BridgeError {
            #expect(error == .disconnected)
        } catch let error as OBDError {
            #expect(error == .cancelled)
        }
        await #expect(throws: BridgeError.disconnected) {
            _ = try await client.connect()
        }
        await client.close()
        await rig.session.close()
    }
}
