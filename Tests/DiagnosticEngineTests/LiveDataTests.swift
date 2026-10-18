import Foundation
import Testing
import OBDCore
import VehicleSim
@testable import DiagnosticEngine

@Suite struct LiveDataTests {
    @Test func streamsMeasurementsUntilTheConsumerStops() async throws {
        let session = DiagnosticSession(link: SimulatedLink(profile: .mondeoMk4), simulated: true)
        var names: [String] = []
        for try await record in session.live(pids: [0x0C, 0x0D], interval: .milliseconds(20)) {
            names.append(record.name)
            if names.count == 6 { break }
        }
        #expect(names == ["Motordrehzahl", "Fahrzeuggeschwindigkeit", "Motordrehzahl", "Fahrzeuggeschwindigkeit", "Motordrehzahl", "Fahrzeuggeschwindigkeit"])
        try await waitUntilIdle(session)
        #expect(try await session.readPIDs([0x05]).first?.name == "Kühlmitteltemperatur")
    }

    @Test func sessionIsBusyWhileStreaming() async throws {
        let session = DiagnosticSession(link: SimulatedLink(profile: .mondeoMk4), simulated: true)
        let stream = session.live(pids: [0x0C], interval: .milliseconds(50))
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()
        await #expect(throws: OBDError.busy) { _ = try await session.readPIDs([0x05]) }
    }

    @Test func valuesChangeOverTime() async throws {
        let session = DiagnosticSession(link: SimulatedLink(profile: .mondeoMk4), simulated: true)
        var values = Set<Double>()
        var count = 0
        for try await record in session.live(pids: [0x0C], interval: .milliseconds(150)) {
            if let value = record.primaryValue?.numericValue { values.insert(value) }
            count += 1
            if count == 4 { break }
        }
        #expect(values.count > 1)
    }

    func waitUntilIdle(_ session: DiagnosticSession) async throws {
        for _ in 0..<100 {
            if case .working = await session.state {
                try await Task.sleep(for: .milliseconds(10))
            } else {
                return
            }
        }
        Issue.record("Sitzung wurde nicht frei")
    }
}
