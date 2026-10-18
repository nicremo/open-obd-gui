import AdapterKit
import Foundation
import Testing
import OBDCore
import VehicleSim
@testable import DiagnosticEngine

/// Types that cross the app bridge must survive a JSON round trip unchanged.
@Suite struct WireCodingTests {
    func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    @Test func everyErrorSurvives() throws {
        let errors: [OBDError] = [
            .adapterNotFound, .portBusy("/dev/x"), .portOpenFailed(path: "/dev/y", errno: 16), .io("kaputt"), .timeout("ATZ"),
            .adapterNotResponding, .adapterRejected(command: "ATX", reply: "?"), .busUnavailable("ms"), .noData, .canError, .busBusy,
            .bufferFull, .adapterError("x"), .policyDenied("2E"), .malformedResponse("z"), .negativeResponse(service: 0x22, code: 0x31),
            .vehicleNotResponding, .cancelled, .disconnected, .busy,
        ]
        for error in errors {
            #expect(try roundTrip(error) == error)
        }
    }

    @Test func eventsAndResultsSurvive() async throws {
        let session = DiagnosticSession(link: SimulatedLink(profile: .mondeoMk4), simulated: true)
        let report = try await session.scan(depth: .quick)
        let raw = try await session.rawRequest([0x22, 0xF1, 0x90], target: .module(0x7E0), bus: .hsCAN, timeout: .milliseconds(500))
        let identification = try await session.identify(request: 0x726, bus: .msCAN, full: false)
        await session.close()

        let events: [EngineEvent] = [
            .stepStarted(.adapter), .stepFinished(.adapter, summary: "ok"), .stepSkipped(.discoveryMS, reason: "kein MS-CAN"),
            .stepFailed(.asBuilt, message: "x"), .troubleCodeFound(try #require(report.allTroubleCodes.first)),
            .traffic(TrafficEvent(direction: .sent, text: "0100", timestamp: Date(timeIntervalSince1970: 12.345), elapsed: .milliseconds(7))),
            .scanFinished(report.summary),
        ]
        let decoded = try roundTrip(events)
        #expect(decoded.count == events.count)
        guard case .traffic(let traffic) = decoded[5] else { Issue.record("traffic lost"); return }
        #expect(traffic.timestamp == Date(timeIntervalSince1970: 12.345))
        #expect(traffic.elapsed == .milliseconds(7))

        let rawCopy = try roundTrip(raw)
        #expect(rawCopy.messages == raw.messages)
        #expect(rawCopy.elapsed == raw.elapsed)
        #expect(rawCopy.target == raw.target)
        #expect(try roundTrip(identification) == identification)
        #expect(try roundTrip(report) == report)
    }

    @Test func storeFindsTheNewestReport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("openobd-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReportStore(directory: directory)
        #expect(store.latest() == nil)
        let session = DiagnosticSession(link: SimulatedLink(profile: .focusMk4), simulated: true)
        var older = try await session.scan(depth: .quick)
        await session.close()
        var newer = older
        older.meta.createdAt = Date(timeIntervalSince1970: 1_000)
        newer.meta.createdAt = Date(timeIntervalSince1970: 2_000)
        try store.save(older)
        let url = try store.save(newer)
        let latest = try #require(store.latest())
        #expect(latest.entry.url.lastPathComponent == url.lastPathComponent)
        #expect(latest.report.meta.createdAt == newer.meta.createdAt)
        #expect(try roundTrip(latest.entry) == latest.entry)
    }
}
