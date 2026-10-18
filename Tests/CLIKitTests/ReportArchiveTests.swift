import Foundation
import Testing
import DiagnosticEngine
@testable import CLIKit

@Suite struct ReportArchiveTests {
    func temporaryStore() -> ReportStore {
        ReportStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("openobd-archive-\(UUID().uuidString)"))
    }

    func scan(_ store: ReportStore, archive: Bool, digest: Bool, profile: String = "mondeo-mk4") async throws -> CLIResult<ReportPayload> {
        let context = CLIContext()
        let result = try await ScanCommand.perform({ try await ConnectionSpec(sim: profile).open(context) }, depth: .quick, out: nil, markdown: nil,
                                                   archive: archive, digest: digest, store: store)
        await context.cleanup()
        return result
    }

    @Test func archivedScansAppearInTheList() async throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        _ = try await scan(store, archive: false, digest: false)
        #expect(store.list().isEmpty)
        let archived = try await scan(store, archive: true, digest: false)
        #expect(archived.human.contains("Im Verlauf gespeichert"))
        _ = try await scan(store, archive: true, digest: false, profile: "focus-mk4")
        let listing = try ReportListCommand.perform(store: store)
        #expect(listing.data.count == 2)
        #expect(try ReportListCommand.perform(store: store, limit: 1).data.first?.title == listing.data.first?.title)
        #expect(try ReportListCommand.perform(store: store, limit: 1).data.count == 1)
        #expect(listing.data.first?.simulated == true)
        #expect(listing.data.first?.path.hasSuffix(".json") == true)
    }

    @Test func digestKeepsFaultsAndConfidence() async throws {
        let result = try await scan(temporaryStore(), archive: false, digest: true)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(CLI.encode(result.data).utf8)) as? [String: Any])
        #expect(json["schema"] as? String == "openobd.digest/1")
        #expect(json["vin"] as? String == "WF0DXXGBBDSM12345")
        let faults = try #require(json["faults"] as? [[String: Any]])
        #expect(faults.count == json["faultCount"] as? Int)
        let egr = try #require(faults.first { ($0["code"] as? String)?.hasPrefix("P0401") == true })
        #expect(egr["module"] as? String == "7E0")
        #expect((egr["sources"] as? [String])?.contains("uds") == true)
        #expect(faults.allSatisfy { $0["severity"] != nil && $0["state"] != nil })
        #expect((json["modules"] as? [Any])?.count == 4)
    }

    @Test func lastReportPrefersSessionThenAppThenArchive() async throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("oobd-none.sock").path
        await #expect(throws: CLIError.noReport) {
            _ = try await ReportLastCommand.perform(source: "auto", digest: false, socket: missing, store: store, session: nil)
        }
        _ = try await scan(store, archive: true, digest: false, profile: "focus-mk4")
        let archived = try await ReportLastCommand.perform(source: "auto", digest: true, socket: missing, store: store, session: nil)
        #expect(archived.data.source == "archive")
        #expect(archived.data.path != nil)

        let app = try FakeApp()
        _ = try await app.session.scan(depth: .quick)
        let fromApp = try await ReportLastCommand.perform(source: "auto", digest: false, socket: app.path, store: store, session: nil)
        #expect(fromApp.data.source == "app")
        if case .full(let report) = fromApp.data.report {
            #expect(report.vehicle.vin == "WF0DXXGBBDSM12345")
        } else {
            Issue.record("expected the full report")
        }
        let session = try store.load(URL(fileURLWithPath: try #require(archived.data.path)))
        let fromSession = try await ReportLastCommand.perform(source: "auto", digest: false, socket: app.path, store: store, session: session)
        #expect(fromSession.data.source == "session")
        await app.stop()
        await #expect(throws: BridgeError.appNotRunning(path: app.path)) {
            _ = try await ReportLastCommand.perform(source: "app", digest: false, socket: app.path, store: store, session: nil)
        }
    }

    @Test func showReadsADigestFromAFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("openobd-show-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("bericht.json").path
        _ = await CLITest.run(ScanCommand.self, ["--sim", "focus-mk4", "--depth", "quick", "--out", path])
        let shown = await CLITest.run(ReportShowCommand.self, [path, "--digest", "--json"])
        #expect((shown.data as? [String: Any])?["schema"] as? String == "openobd.digest/1")
        let broken = await CLITest.run(ReportShowCommand.self, [directory.path, "--json"])
        #expect(broken.errorCode == "FILE_ERROR")
    }
}
