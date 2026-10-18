import Foundation
import Testing
import DiagnosticEngine
@testable import CLIKit

@Suite struct MCPToolTests {
    @Test func explainReturnsTheCLIData() async throws {
        let mcp = MCPHarness()
        let result = await mcp.call(1, "explain_dtc", ["code": "P0401"])
        #expect(!result.isError)
        #expect((result.envelope["data"] as? [String: Any])?["code"] as? String == "P0401")
        let text = try #require(((result["content"] as? [[String: Any]])?.first)?["text"] as? String)
        let parsed = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(parsed["command"] as? String == "explain dtc")
        let cli = await CLITest.run(ExplainDTCCommand.self, ["P0401", "--json"])
        #expect(NSDictionary(dictionary: try #require(cli.data as? [String: Any])) == NSDictionary(dictionary: try #require(result.envelope["data"] as? [String: Any])))
    }

    @Test func scanDigestReportsProgress() async {
        let mcp = MCPHarness()
        let result = await mcp.call(2, "scan_vehicle", ["sim": "mondeo-mk4", "depth": "quick", "digest": true], meta: ["progressToken": "scan-1"])
        #expect(!result.isError)
        let data = result.envelope["data"] as? [String: Any]
        #expect(data?["schema"] as? String == "openobd.digest/1")
        #expect(data?["vin"] as? String == "WF0DXXGBBDSM12345")
        let progress = mcp.sink.messages.filter { $0["method"] as? String == "notifications/progress" }.compactMap { $0["params"] as? [String: Any] }
        #expect(progress.count == 13)
        #expect(progress.allSatisfy { $0["progressToken"] as? String == "scan-1" && $0["total"] as? Int == 13 })
        #expect(progress.last?["progress"] as? Int == 13)
        // Progress arrives before the response.
        let order = mcp.sink.messages.map { $0["id"] as? Int ?? 0 }
        #expect(order.last == 2)
    }

    @Test func troubleCodesMatchTheCLI() async throws {
        let mcp = MCPHarness()
        let result = await mcp.call(3, "read_dtcs", ["sim": "mondeo-mk4", "module": "760"])
        let cli = await CLITest.run(DTCCommand.self, ["--sim", "mondeo-mk4", "--module", "760", "--json"])
        let fromMCP = try #require(result.envelope["data"] as? [[String: Any]])
        let fromCLI = try #require(cli.data as? [[String: Any]])
        #expect(NSArray(array: fromMCP) == NSArray(array: fromCLI))
    }

    @Test func writeRequestsAreToolErrors() async {
        let mcp = MCPHarness()
        let result = await mcp.call(4, "raw_request", ["sim": "mondeo-mk4", "module": "7E0", "payload": "2E F1 90 00"])
        #expect(result.isError)
        #expect(result.errorCode == "POLICY_DENIED")
        #expect((result.envelope["meta"] as? [String: Any])?["link"] == nil)
        let read = await mcp.call(5, "raw_request", ["sim": "mondeo-mk4", "module": "7E0", "payload": "22 F1 90"])
        #expect(!read.isError)
    }

    @Test func liveIsBounded() async {
        let mcp = MCPHarness()
        let result = await mcp.call(6, "read_live", ["sim": "mondeo-mk4", "pids": ["0C", "05"], "interval_ms": 20, "count": 3])
        let samples = result.envelope["data"] as? [[String: Any]]
        #expect(samples?.count == 3)
        #expect(samples?.first?["schema"] as? String == "openobd.live/1")
        let tooMany = await mcp.call(7, "read_live", ["sim": "mondeo-mk4", "pids": ["0C"], "count": 100_000])
        #expect(tooMany.errorCode == "USAGE_ERROR")
    }

    @Test func wrongArgumentsAreUsageErrors() async {
        let mcp = MCPHarness()
        let unknown = await mcp.call(8, "explain_dtc", ["code": "P0401", "verbose": true])
        #expect(unknown.isError)
        #expect(unknown.errorCode == "USAGE_ERROR")
        let wrongType = await mcp.call(9, "scan_vehicle", ["sim": "mondeo-mk4", "depth": 5])
        #expect(wrongType.errorCode == "USAGE_ERROR")
        let missing = await mcp.call(10, "read_did", ["sim": "mondeo-mk4", "module": "726"])
        #expect(missing.errorCode == "USAGE_ERROR")
        let badModule = await mcp.call(11, "read_did", ["sim": "mondeo-mk4", "module": "ABC", "did": "F190"])
        #expect(badModule.errorCode == "USAGE_ERROR")
    }

    @Test func lastReportRemembersTheScan() async {
        let mcp = MCPHarness(defaults: MCPDefaults(bridgeSocket: FileManager.default.temporaryDirectory.appendingPathComponent("oobd-none.sock").path))
        let empty = await mcp.call(12, "last_report", ["source": "session"])
        #expect(empty.errorCode == "NO_REPORT")
        _ = await mcp.call(13, "scan_vehicle", ["sim": "focus-mk4", "depth": "quick", "digest": true])
        let last = await mcp.call(14, "last_report", ["digest": true])
        let data = last.envelope["data"] as? [String: Any]
        #expect(data?["source"] as? String == "session")
        #expect((data?["report"] as? [String: Any])?["vin"] as? String == "WF0NXXGCHNSM67890")
    }

    @Test func serverDefaultsApplyAndCallsOverrideThem() async {
        let mcp = MCPHarness(defaults: MCPDefaults(sim: "focus-mk4"))
        let defaulted = await mcp.call(15, "adapter_status")
        #expect((defaulted.envelope["meta"] as? [String: Any])?["link"] as? String == "simulator:focus-mk4")
        let overridden = await mcp.call(16, "adapter_status", ["sim": "mondeo-mk4"])
        #expect((overridden.envelope["meta"] as? [String: Any])?["link"] as? String == "simulator:mondeo-mk4")
    }

    @Test func scanThroughTheApp() async throws {
        let app = try FakeApp()
        let mcp = MCPHarness(defaults: MCPDefaults(bridgeSocket: app.path))
        let status = await mcp.call(17, "app_status")
        #expect((status.envelope["data"] as? [String: Any])?["reachable"] as? Bool == true)
        let result = await mcp.call(18, "scan_vehicle", ["route": "app", "depth": "quick", "digest": true])
        await app.stop()
        #expect(!result.isError)
        #expect((result.envelope["meta"] as? [String: Any])?["link"] as? String == "app:simulator:mondeo-mk4")
        #expect((result.envelope["data"] as? [String: Any])?["faultCount"] as? Int ?? 0 > 0)
    }

    @Test func capabilitiesNameEveryTool() async {
        let mcp = MCPHarness()
        let result = await mcp.call(19, "capabilities")
        let tools = ((result.envelope["data"] as? [String: Any])?["mcpTools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        #expect(tools?.count == MCPTools.catalog.count)
        let reports = await mcp.call(20, "list_reports")
        #expect((reports.envelope["data"] as? [Any])?.isEmpty == true)
        let devices = await mcp.call(21, "list_devices")
        #expect(!devices.isError)
    }
}
