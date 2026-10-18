import ArgumentParser
import Foundation
import Testing
@testable import CLIKit

extension CLITest {
    static func runRoot(_ arguments: [String]) async -> RunOutcome {
        let captured = CapturedOutput()
        var exit: Int32 = 0
        await Output.$sink.withValue(captured.sink) {
            do {
                let parsed = try OpenOBDCommand.parseAsRoot(arguments)
                if var command = parsed as? AsyncParsableCommand {
                    try await command.run()
                } else {
                    var command = parsed
                    try command.run()
                }
            } catch let code as ExitCode {
                exit = code.rawValue
            } catch {
                exit = OpenOBDCommand.exitCode(for: error).rawValue
            }
        }
        return RunOutcome(out: captured.stdout, err: captured.stderr, exit: exit)
    }
}

@Suite struct OfflineCommandTests {
    @Test func explainsAStandardCode() async {
        let result = await CLITest.runRoot(["explain", "dtc", "P0401-00", "--json"])
        let data = result.data as? [String: Any]
        #expect(data?["title"] as? String == "Abgasrückführung \"A\": Durchfluss zu gering")
        #expect(data?["failureTypeDetail"] as? String == "keine Unterart angegeben")
        #expect((data?["explanation"] as? [String: Any])?["what"] != nil)
    }

    @Test func neverGuessesManufacturerCodes() async {
        let result = await CLITest.runRoot(["explain", "dtc", "B1A00", "--json"])
        let data = result.data as? [String: Any]
        #expect(data?["title"] == nil)
        #expect(data?["origin"] as? String == "herstellerspezifischer Code")
        #expect((data?["note"] as? String)?.contains("nicht geraten") == true)
        #expect(await CLITest.runRoot(["explain", "dtc", "XYZ", "--json"]).exit == 2)
    }

    @Test func explainsPIDsNRCsDIDsAndModules() async {
        #expect((await CLITest.runRoot(["explain", "pid", "0C", "--json"]).data as? [String: Any])?["name"] as? String == "Motordrehzahl")
        #expect((await CLITest.runRoot(["explain", "nrc", "31", "--json"]).data as? [String: Any])?["german"] as? String
            == "Kennung oder Wert außerhalb des Bereichs (nicht vorhanden)")
        #expect((await CLITest.runRoot(["explain", "did", "F190", "--json"]).data as? [String: Any])?["name"] as? String == "Fahrgestellnummer (VIN)")
        #expect((await CLITest.runRoot(["explain", "did", "F1A5", "--json"]).data as? [String: Any])?["known"] as? Bool == false)
        let module = await CLITest.runRoot(["explain", "module", "726", "--json"]).data as? [String: Any]
        #expect(module?["acronym"] as? String == "BCM")
        #expect(module?["response"] as? String == "72E")
    }

    @Test func showsSavedReports() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("openobd-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(await CLITest.runRoot(["scan", "--sim", "mondeo-mk4", "--depth", "quick", "--out", path, "--json"]).exit == 0)
        let markdown = await CLITest.runRoot(["report", "show", path, "--markdown"])
        #expect(markdown.out.hasPrefix("# Fahrzeugbericht"))
        let json = await CLITest.runRoot(["report", "show", path, "--json"])
        #expect((json.data as? [String: Any])?["schema"] as? String == "openobd.report/1")
        let missing = await CLITest.runRoot(["report", "show", "/tmp/does-not-exist-openobd.json", "--json"])
        #expect(missing.exit == 2)
        #expect(missing.errorCode == "FILE_ERROR")
    }

    @Test func capabilitiesDescribeEverything() async {
        let result = await CLITest.runRoot(["capabilities", "--json"])
        let data = result.data as? [String: Any]
        #expect(data?["readOnly"] as? Bool == true)
        let names = (data?["commands"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        for name in ["devices", "adapter", "scan", "dtc", "modules", "ident", "read-did", "pids", "live", "raw", "explain dtc", "report show",
                     "report list", "report last", "app", "mcp", "capabilities"] {
            #expect(names.contains(name), "\(name)")
        }
        let exits = (data?["exitCodes"] as? [[String: Any]])?.compactMap { $0["code"] as? Int } ?? []
        #expect(exits == [0, 1, 2, 3, 4, 5, 6, 7, 8, 64, 130])
        let errors = data?["errorCodes"] as? [String] ?? []
        for code in ["POLICY_DENIED", "APP_NOT_RUNNING", "APP_BUSY", "NO_REPORT"] {
            #expect(errors.contains(code), "\(code)")
        }
        #expect((data?["routes"] as? [String: String])?.keys.sorted() == ["app", "auto", "direct"])
    }

    @Test func rootDispatchesAndReportsVersion() async {
        let scan = await CLITest.runRoot(["scan", "--sim", "focus-mk4", "--depth", "quick", "--json"])
        #expect(scan.exit == 0)
        #expect(scan.json["command"] as? String == "scan")
        do {
            _ = try OpenOBDCommand.parseAsRoot(["--version"])
            Issue.record("--version muss beenden")
        } catch {
            #expect(OpenOBDCommand.message(for: error) == "0.1.0")
        }
        #expect(await CLITest.runRoot(["nope"]).exit == 64)
    }
}
