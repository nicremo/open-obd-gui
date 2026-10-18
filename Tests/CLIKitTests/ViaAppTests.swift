import Foundation
import Testing
import DiagnosticEngine
import VehicleSim
@testable import CLIKit

/// Stands in for the running app: a bridge server over the simulator at a socket only this test uses.
final class FakeApp: Sendable {
    let path: String
    let session: DiagnosticSession
    let server: BridgeServer

    init(_ profile: VehicleProfile = .mondeoMk4) throws {
        path = FileManager.default.temporaryDirectory.appendingPathComponent("oobd-\(UUID().uuidString.prefix(8)).sock").path
        session = DiagnosticSession(link: SimulatedLink(profile: profile), simulated: true, vehicleTitle: profile.title, vehicleHint: profile.id)
        server = try BridgeServer.start(at: path, handler: SessionBridgeHandler(session: session, appName: "Open OBD GUI (Test)"))
    }

    func stop() async {
        server.stop()
        await session.close()
    }
}

@Suite struct ViaAppTests {
    @Test func scanThroughTheAppMatchesADirectScan() async throws {
        let app = try FakeApp()
        let viaApp = await CLITest.run(ScanCommand.self, ["--via-app", "--bridge-socket", app.path, "--depth", "quick", "--json"])
        let direct = await CLITest.run(ScanCommand.self, ["--sim", "mondeo-mk4", "--depth", "quick", "--json"])
        await app.stop()
        #expect(viaApp.exit == 0)
        #expect((viaApp.json["meta"] as? [String: Any])?["link"] as? String == "app:simulator:mondeo-mk4")
        let appReport = try ReportCoding.decode(JSONSerialization.data(withJSONObject: try #require(viaApp.data)))
        let directReport = try ReportCoding.decode(JSONSerialization.data(withJSONObject: try #require(direct.data)))
        #expect(appReport.modules == directReport.modules)
        #expect(appReport.summary == directReport.summary)
        #expect(appReport.vehicle == directReport.vehicle)
        #expect(appReport.allTroubleCodes.map(\.id) == directReport.allTroubleCodes.map(\.id))
    }

    @Test func everyReadingCommandRunsInTheApp() async throws {
        let app = try FakeApp()
        let socket = ["--via-app", "--bridge-socket", app.path, "--json"]
        let codes = await CLITest.run(DTCCommand.self, ["--module", "760"] + socket)
        #expect((codes.data as? [[String: Any]])?.compactMap { $0["displayCode"] as? String } == ["U0100-87"])
        let all = await CLITest.run(DTCCommand.self, socket)
        #expect(((all.data as? [Any])?.count ?? 0) >= 4)
        let ident = await CLITest.run(IdentCommand.self, ["--module", "726", "--bus", "ms"] + socket)
        #expect(((ident.data as? [String: Any])?["readings"] as? [Any])?.isEmpty == false)
        let did = await CLITest.run(ReadDIDCommand.self, ["--module", "726", "--bus", "ms", "--did", "F190"] + socket)
        #expect((did.data as? [String: Any])?["vin"] as? String == "WF0DXXGBBDSM12345")
        let modules = await CLITest.run(ModulesCommand.self, ["--bus", "hs"] + socket)
        #expect(((modules.data as? [Any])?.count ?? 0) >= 3)
        let pids = await CLITest.run(PIDsCommand.self, socket)
        #expect((pids.data as? [[String: Any]])?.contains { $0["pid"] as? String == "0C" } == true)
        let raw = await CLITest.run(RawCommand.self, ["--module", "7E0", "22 F1 90"] + socket)
        #expect(raw.exit == 0)
        let live = await CLITest.run(LiveCommand.self, ["0C", "--interval", "20", "--count", "3"] + socket)
        #expect(live.exit == 0)
        #expect(live.out.split(separator: "\n").count == 3)
        let adapter = await CLITest.run(AdapterCommand.self, socket)
        #expect((adapter.data as? [String: Any])?["simulated"] as? Bool == true)
        await app.stop()
    }

    @Test func writesAreStillDeniedBeforeAnyConnection() async throws {
        let app = try FakeApp()
        let write = await CLITest.run(RawCommand.self, ["--module", "7E0", "2E F1 90 00", "--via-app", "--bridge-socket", app.path, "--json"])
        await app.stop()
        #expect(write.exit == 6)
        #expect(write.errorCode == "POLICY_DENIED")
        #expect((write.json["meta"] as? [String: Any])?["link"] == nil)
    }

    @Test func viaAppRefusesOwnSources() async {
        let result = await CLITest.run(AdapterCommand.self, ["--via-app", "--sim", "mondeo-mk4", "--json"])
        #expect(result.exit == 2)
        #expect(result.errorCode == "USAGE_ERROR")
        let conflict = await CLITest.run(AdapterCommand.self, ["--via-app", "--route", "direct", "--json"])
        #expect(conflict.exit == 2)
        let unknown = await CLITest.run(AdapterCommand.self, ["--route", "bluetooth", "--json"])
        #expect(unknown.errorCode == "USAGE_ERROR")
    }

    @Test func missingAppHasItsOwnExitCode() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("oobd-missing.sock").path
        let result = await CLITest.run(ScanCommand.self, ["--via-app", "--bridge-socket", path, "--json"])
        #expect(result.exit == 8)
        #expect(result.errorCode == "APP_NOT_RUNNING")
    }

    @Test func autoRouteNeverTakesSimulatorDataForTheCar() async throws {
        let app = try FakeApp(.focusMk4)
        let status = await AppCommand.perform(socket: app.path)
        #expect(status.data.reachable)
        #expect(status.data.hello?.link == "simulator:focus-mk4")
        #expect(status.data.autoRoute == "direct")
        // An explicit source wins over the app, even with route auto.
        let own = await CLITest.run(AdapterCommand.self, ["--route", "auto", "--sim", "mondeo-mk4", "--bridge-socket", app.path, "--json"])
        #expect((own.json["meta"] as? [String: Any])?["link"] as? String == "simulator:mondeo-mk4")
        await app.stop()
        let gone = await AppCommand.perform(socket: app.path)
        #expect(!gone.data.reachable)
    }

    @Test func rootLevelFlagMovesBehindTheCommand() {
        #expect(OpenOBDCommand.normalized(["--via-app", "scan", "--depth", "quick"]) == ["scan", "--depth", "quick", "--via-app"])
        #expect(OpenOBDCommand.normalized(["scan", "--via-app"]) == ["scan", "--via-app"])
        #expect(OpenOBDCommand.normalized(["devices"]) == ["devices"])
    }
}
