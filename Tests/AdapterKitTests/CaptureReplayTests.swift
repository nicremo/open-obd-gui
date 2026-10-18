import Foundation
import Testing
import OBDCore
@testable import AdapterKit

@Suite struct CaptureReplayTests {
    func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("openobd-\(UUID().uuidString).jsonl")
    }

    @Test func strictReplayEnforcesOrder() async throws {
        let replay = ReplayLink(exchanges: [
            ReplayExchange(command: "ATZ", reply: "ELM327 v1.4b\r\r"),
            ReplayExchange(command: "ATE0", reply: "OK\r\r"),
        ])
        #expect(try await replay.transact("ATZ", timeout: .seconds(1)).text == "ELM327 v1.4b\r\r")
        await #expect(throws: OBDError.self) { _ = try await replay.transact("ATL0", timeout: .seconds(1)) }
    }

    @Test func strictReplayIgnoresSpacingAndCase() async throws {
        let replay = ReplayLink(exchanges: [ReplayExchange(command: "STPX h:7E0, d:22F190", reply: "NO DATA\r")])
        #expect(try await replay.transact("stpx h:7e0,d:22f190", timeout: .seconds(1)).text == "NO DATA\r")
        #expect(await replay.remaining == 0)
        await #expect(throws: OBDError.self) { _ = try await replay.transact("ATI", timeout: .seconds(1)) }
    }

    @Test func lookupReplayAnswersRepeatedCommands() async throws {
        let replay = ReplayLink(exchanges: [
            ReplayExchange(command: "010C", reply: "7E8 04 41 0C 0B B8\r"),
            ReplayExchange(command: "010D", reply: "7E8 03 41 0D 00\r"),
        ], mode: .lookup)
        for _ in 0..<3 {
            #expect(try await replay.transact("010D", timeout: .seconds(1)).text == "7E8 03 41 0D 00\r")
            #expect(try await replay.transact("010C", timeout: .seconds(1)).text == "7E8 04 41 0C 0B B8\r")
        }
        await #expect(throws: OBDError.self) { _ = try await replay.transact("0105", timeout: .seconds(1)) }
    }

    @Test func replayedFailuresAreThrown() async throws {
        let replay = ReplayLink(exchanges: [ReplayExchange(command: "0100", reply: "", failure: "TIMEOUT")])
        await #expect(throws: OBDError.timeout("Wiedergabe: 0100")) { _ = try await replay.transact("0100", timeout: .seconds(1)) }
    }

    @Test func captureWritesHeaderAndExchangesThatReplayExactly() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let source = ReplayLink(exchanges: [
            ReplayExchange(command: "ATI", reply: "ELM327 v1.4b\r\r"),
            ReplayExchange(command: "0100", reply: "", failure: "TIMEOUT"),
        ])
        let recorder = try CaptureRecorder(url: url, tool: "openobd test", link: "replay")
        let link = CapturingLink(base: source, recorder: recorder)
        _ = try await link.transact("ATI", timeout: .seconds(1))
        await #expect(throws: OBDError.self) { _ = try await link.transact("0100", timeout: .seconds(1)) }
        await recorder.note("bus=hs-can")
        await link.close()

        let entries = try CaptureRecorder.load(url)
        #expect(entries.first?.type == .header)
        #expect(entries.first?.format == "openobd.capture/1")
        #expect(entries.map(\.type) == [.header, .sent, .received, .sent, .failure, .note])

        let replay = try ReplayLink.load(url, mode: .strict)
        #expect(try await replay.transact("ATI", timeout: .seconds(1)).text == "ELM327 v1.4b\r\r")
        await #expect(throws: OBDError.self) { _ = try await replay.transact("0100", timeout: .seconds(1)) }
    }

    @Test func loadRejectsFilesWithoutHeader() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"type\":\"sent\",\"line\":\"ATI\"}\n".utf8).write(to: url)
        #expect(throws: OBDError.self) { _ = try CaptureRecorder.load(url) }
    }
}
