import ArgumentParser
import Foundation
import Testing
import OBDCore
@testable import CLIKit

struct RunOutcome {
    let out: String
    let err: String
    let exit: Int32

    var json: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]
    }

    var data: Any? { json["data"] }
    var errorCode: String? { (json["error"] as? [String: Any])?["code"] as? String }
}

enum CLITest {
    static func run<Command: AsyncParsableCommand>(_ type: Command.Type, _ arguments: [String]) async -> RunOutcome {
        let captured = CapturedOutput()
        var exit: Int32 = 0
        await Output.$sink.withValue(captured.sink) {
            do {
                var command = try type.parse(arguments)
                try await command.run()
            } catch let code as ExitCode {
                exit = code.rawValue
            } catch {
                exit = Command.exitCode(for: error).rawValue
            }
        }
        return RunOutcome(out: captured.stdout, err: captured.stderr, exit: exit)
    }
}

struct EchoResult: Encodable, Sendable {
    let value: Int
}

@Suite struct RuntimeTests {
    @Test func successEnvelopeIsStable() async throws {
        let captured = CapturedOutput()
        try await Output.$sink.withValue(captured.sink) {
            try await CLI.execute("echo", json: true) { _ in CLIResult(data: EchoResult(value: 7), human: "", warnings: ["w"]) }
        }
        let json = try #require(try JSONSerialization.jsonObject(with: Data(captured.stdout.utf8)) as? [String: Any])
        #expect(json["schema"] as? String == "openobd.cli/1")
        #expect(json["command"] as? String == "echo")
        #expect(json["ok"] as? Bool == true)
        #expect((json["data"] as? [String: Any])?["value"] as? Int == 7)
        #expect(json["warnings"] as? [String] == ["w"])
        #expect((json["meta"] as? [String: Any])?["tool"] as? String == "openobd 0.1.0")
        #expect(captured.stderr.isEmpty)
    }

    @Test(arguments: [
        (OBDError.adapterNotFound as any Error, Int32(3), "ADAPTER_NOT_FOUND"),
        (OBDError.portBusy("/dev/x"), 7, "PORT_BUSY"),
        (OBDError.policyDenied("2E"), 6, "POLICY_DENIED"),
        (OBDError.vehicleNotResponding, 5, "VEHICLE_NOT_RESPONDING"),
        (OBDError.negativeResponse(service: 0x19, code: 0x11), 5, "NEGATIVE_RESPONSE"),
        (OBDError.timeout("x"), 4, "TIMEOUT"),
        (OBDError.cancelled, 130, "CANCELLED"),
        (CLIError.usage("x"), 2, "USAGE_ERROR"),
        (CLIError.file("x"), 2, "FILE_ERROR"),
    ])
    func failuresMapToCodes(_ error: any Error, _ exit: Int32, _ code: String) async {
        let captured = CapturedOutput()
        var thrown: Int32 = 0
        await Output.$sink.withValue(captured.sink) {
            do {
                try await CLI.execute("fail", json: true) { _ -> CLIResult<EchoResult> in throw error }
            } catch let exitCode as ExitCode {
                thrown = exitCode.rawValue
            } catch {
                Issue.record("unexpected \(error)")
            }
        }
        #expect(thrown == exit)
        let json = (try? JSONSerialization.jsonObject(with: Data(captured.stdout.utf8))) as? [String: Any]
        #expect(json?["ok"] as? Bool == false)
        #expect((json?["error"] as? [String: Any])?["code"] as? String == code)
    }

    @Test func humanFailureGoesToStandardError() async {
        let captured = CapturedOutput()
        await Output.$sink.withValue(captured.sink) {
            _ = try? await CLI.execute("fail", json: false) { _ -> CLIResult<EchoResult> in throw OBDError.adapterNotFound }
        }
        #expect(captured.stdout.isEmpty)
        #expect(captured.stderr.contains("Fehler: Kein OBD-Adapter gefunden."))
        #expect(captured.stderr.contains("Tipp:"))
    }

    @Test func argumentParsing() throws {
        #expect(try ArgumentParsing.module("7e0") == 0x7E0)
        #expect(throws: CLIError.self) { try ArgumentParsing.module("7E") }
        #expect(throws: CLIError.self) { try ArgumentParsing.module("123") }
        #expect(try ArgumentParsing.bus("ms") == .msCAN)
        #expect(try ArgumentParsing.bus("HS-CAN") == .hsCAN)
        #expect(throws: CLIError.self) { try ArgumentParsing.bus("lin") }
        #expect(try ArgumentParsing.did("f190") == 0xF190)
        #expect(throws: CLIError.self) { try ArgumentParsing.did("F19") }
        #expect(try ArgumentParsing.pid("0c") == 0x0C)
        #expect(try ArgumentParsing.payload(["22 F1", "90"]) == [0x22, 0xF1, 0x90])
        #expect(throws: CLIError.self) { try ArgumentParsing.payload(["2"]) }
    }

    @Test func tablesAlign() {
        var table = TextTable(headers: ["Code", "Text"])
        table.add(["P0401", "Abgasrückführung"])
        table.add(["U0100-87", "Kommunikation"])
        #expect(table.render() == "  Code      Text\n  P0401     Abgasrückführung\n  U0100-87  Kommunikation")
    }
}
