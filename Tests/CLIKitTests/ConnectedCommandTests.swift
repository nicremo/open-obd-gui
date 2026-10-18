import Foundation
import Testing
import DiagnosticEngine
@testable import CLIKit

@Suite struct ConnectedCommandTests {
    @Test func devicesAlwaysAnswers() async {
        let result = await CLITest.run(DevicesCommand.self, ["--json"])
        #expect(result.exit == 0)
        #expect(result.data is [Any])
    }

    @Test func adapterIdentityFromSimulator() async {
        let result = await CLITest.run(AdapterCommand.self, ["--sim", "mondeo-mk4", "--json"])
        #expect(result.exit == 0)
        let data = result.data as? [String: Any]
        #expect((data?["identity"] as? [String: Any])?["device"] as? String == "OBDLink EX (Simulator)")
        #expect(data?["msCANAvailable"] as? Bool == true)
        #expect((result.json["meta"] as? [String: Any])?["link"] as? String == "simulator:mondeo-mk4")
    }

    @Test func scanReturnsTheFullReport() async throws {
        let result = await CLITest.run(ScanCommand.self, ["--sim", "mondeo-mk4", "--depth", "quick", "--json"])
        #expect(result.exit == 0)
        let report = try ReportCoding.decode(JSONSerialization.data(withJSONObject: try #require(result.data)))
        #expect(report.modules.count == 4)
        #expect(report.vehicle.vin == "WF0DXXGBBDSM12345")
    }

    @Test func scanWritesReportFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("openobd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = directory.appendingPathComponent("bericht.json").path
        let markdown = directory.appendingPathComponent("bericht.md").path
        let capture = directory.appendingPathComponent("mitschnitt.jsonl").path
        let result = await CLITest.run(ScanCommand.self, ["--sim", "focus-mk4", "--depth", "quick", "--out", json, "--markdown", markdown, "--capture", capture])
        #expect(result.exit == 0)
        #expect(result.out.contains("Fahrzeug: Ford Focus Mk4 1.5 EcoBoost (Simulator)"))
        #expect(result.err.contains("✓ Adapter prüfen"))
        #expect(try ReportCoding.decode(Data(contentsOf: URL(fileURLWithPath: json))).modules.count == 9)
        #expect(try String(contentsOfFile: markdown, encoding: .utf8).hasPrefix("# Fahrzeugbericht"))
        #expect(try String(contentsOfFile: capture, encoding: .utf8).contains("\"type\":\"sent\""))
    }

    @Test func troubleCodesAcrossAllModules() async {
        let result = await CLITest.run(DTCCommand.self, ["--sim", "mondeo-mk4", "--json"])
        let codes = (result.data as? [[String: Any]])?.compactMap { $0["displayCode"] as? String } ?? []
        #expect(Set(codes).isSuperset(of: ["P0401", "P0401-00", "U0100-87", "U0155-87"]))
    }

    @Test func troubleCodesOfOneModule() async {
        let result = await CLITest.run(DTCCommand.self, ["--sim", "mondeo-mk4", "--module", "760", "--json"])
        #expect((result.data as? [[String: Any]])?.compactMap { $0["displayCode"] as? String } == ["U0100-87"])
        let obdOnly = await CLITest.run(DTCCommand.self, ["--sim", "mondeo-mk4", "--obd", "--json"])
        #expect((obdOnly.data as? [Any])?.count == 2)
    }

    @Test func modulesPerBus() async {
        let result = await CLITest.run(ModulesCommand.self, ["--sim", "focus-mk4", "--bus", "hs", "--json"])
        let modules = result.data as? [[String: Any]]
        #expect(modules?.count == 9)
        #expect(modules?.first?["request"] as? String == "706")
        #expect(modules?.first?["name"] as? String == "Frontkamera")
    }

    @Test func identificationAndSingleDID() async {
        let ident = await CLITest.run(IdentCommand.self, ["--sim", "mondeo-mk4", "--module", "726", "--bus", "ms", "--json"])
        let readings = (ident.data as? [String: Any])?["readings"] as? [[String: Any]]
        #expect(readings?.contains { $0["did"] as? String == "F111" } == true)
        let did = await CLITest.run(ReadDIDCommand.self, ["--sim", "mondeo-mk4", "--module", "726", "--bus", "ms", "--did", "F190", "--json"])
        #expect((did.data as? [String: Any])?["vin"] as? String == "WF0DXXGBBDSM12345")
    }

    @Test func pidsFromVehicleAndCatalog() async {
        let vehicle = await CLITest.run(PIDsCommand.self, ["--sim", "mondeo-mk4", "--json"])
        let pids = (vehicle.data as? [[String: Any]])?.compactMap { $0["pid"] as? String } ?? []
        #expect(pids.contains("0C"))
        let catalog = await CLITest.run(PIDsCommand.self, ["--catalog", "--json"])
        #expect(((catalog.data as? [Any])?.count ?? 0) >= 85)
        #expect((catalog.json["meta"] as? [String: Any])?["link"] == nil)
    }

    @Test func rawReadIsAllowedAndWriteIsDenied() async {
        let read = await CLITest.run(RawCommand.self, ["--sim", "mondeo-mk4", "--module", "7E0", "22 F1 90", "--json"])
        let messages = (read.data as? [String: Any])?["messages"] as? [[String: Any]]
        #expect((messages?.first?["payload"] as? String)?.hasPrefix("62F190") == true)
        #expect(messages?.first?["interpretation"] as? String == "positive Antwort auf Dienst 22")
        let write = await CLITest.run(RawCommand.self, ["--sim", "mondeo-mk4", "--module", "7E0", "2E F1 90 00", "--json"])
        #expect(write.exit == 6)
        #expect(write.errorCode == "POLICY_DENIED")
        #expect((write.json["meta"] as? [String: Any])?["link"] == nil)
        let missing = await CLITest.run(RawCommand.self, ["--sim", "mondeo-mk4", "22F190", "--json"])
        #expect(missing.exit == 2)
    }

    @Test func liveStreamsNDJSON() async {
        let result = await CLITest.run(LiveCommand.self, ["0C", "0D", "--sim", "mondeo-mk4", "--interval", "20", "--count", "4", "--json"])
        #expect(result.exit == 0)
        let lines = result.out.split(separator: "\n")
        #expect(lines.count == 4)
        let first = (try? JSONSerialization.jsonObject(with: Data(lines[0].utf8))) as? [String: Any]
        #expect(first?["schema"] as? String == "openobd.live/1")
        #expect(first?["name"] as? String == "Motordrehzahl")
        #expect(first?["pid"] as? String == "0C")
    }

    @Test func liveCSVHasHeader() async {
        let result = await CLITest.run(LiveCommand.self, ["05", "--sim", "mondeo-mk4", "--interval", "20", "--count", "2", "--format", "csv"])
        let lines = result.out.split(separator: "\n")
        #expect(lines.first == "zeit,steuergeraet,pid,name,wert,einheit,roh")
        #expect(lines.count == 3)
    }

    @Test func usageErrorsAreReported() async {
        let badModule = await CLITest.run(DTCCommand.self, ["--sim", "mondeo-mk4", "--module", "XYZ", "--json"])
        #expect(badModule.exit == 2)
        #expect(badModule.errorCode == "USAGE_ERROR")
        let badProfile = await CLITest.run(ScanCommand.self, ["--sim", "nope", "--json"])
        #expect(badProfile.exit == 2)
        let missingPort = await CLITest.run(AdapterCommand.self, ["--port", "/dev/cu.does-not-exist-openobd", "--json"])
        #expect(missingPort.exit == 4)
        #expect(missingPort.errorCode == "PORT_OPEN_FAILED")
    }
}
