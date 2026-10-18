import Foundation
import Synchronization
import Testing
import DiagnosticEngine
@testable import CLIKit

/// Collects every line the server writes.
final class LineSink: Sendable {
    private let storage = Mutex<[String]>([])

    func append(_ line: String) {
        storage.withLock { $0.append(line) }
    }

    var lines: [String] { storage.withLock { $0 } }

    var messages: [[String: Any]] {
        lines.compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
    }
}

/// An MCP server in process, fed line by line like stdio.
struct MCPHarness {
    let sink = LineSink()
    let server: MCPServer
    let store: ReportStore

    init(defaults: MCPDefaults = MCPDefaults()) {
        store = ReportStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("openobd-mcp-\(UUID().uuidString)"))
        let sink = sink
        server = MCPServer(defaults: defaults, store: store, write: { sink.append($0) })
    }

    func send(_ message: [String: Any]) async {
        let data = try! JSONSerialization.data(withJSONObject: message)
        await server.handle(line: String(decoding: data, as: UTF8.self))
    }

    func sendRaw(_ line: String) async {
        await server.handle(line: line)
    }

    /// Sends a request, waits for queued tool calls and returns the response with this id.
    func request(_ id: Int, _ method: String, _ params: [String: Any]? = nil) async -> [String: Any] {
        var message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { message["params"] = params }
        await send(message)
        await server.drain()
        return response(id) ?? [:]
    }

    func call(_ id: Int, _ tool: String, _ arguments: [String: Any] = [:], meta: [String: Any]? = nil) async -> [String: Any] {
        var params: [String: Any] = ["name": tool, "arguments": arguments]
        if let meta { params["_meta"] = meta }
        return (await request(id, "tools/call", params))["result"] as? [String: Any] ?? [:]
    }

    func response(_ id: Int) -> [String: Any]? {
        sink.messages.first { ($0["id"] as? Int) == id }
    }
}

extension Dictionary where Key == String, Value == Any {
    var envelope: [String: Any] { self["structuredContent"] as? [String: Any] ?? [:] }
    var isError: Bool { self["isError"] as? Bool ?? false }
    var errorCode: String? { (envelope["error"] as? [String: Any])?["code"] as? String }
}

@Suite struct MCPServerTests {
    @Test(arguments: [("2025-06-18", "2025-06-18"), ("2025-03-26", "2025-03-26"), ("2024-11-05", "2024-11-05"), ("1999-01-01", "2025-06-18")])
    func initializeNegotiatesTheRevision(_ requested: String, _ expected: String) async {
        let mcp = MCPHarness()
        let response = await mcp.request(1, "initialize", ["protocolVersion": requested, "capabilities": [:], "clientInfo": ["name": "test", "version": "1"]])
        let result = response["result"] as? [String: Any]
        #expect(result?["protocolVersion"] as? String == expected)
        #expect((result?["serverInfo"] as? [String: Any])?["name"] as? String == "openobd")
        #expect(((result?["capabilities"] as? [String: Any])?["tools"] as? [String: Any])?["listChanged"] as? Bool == false)
        #expect((result?["instructions"] as? String)?.contains("nur lesend") == true)
    }

    @Test func listsEveryToolWithObjectSchemas() async {
        let mcp = MCPHarness()
        #expect((await mcp.request(1, "ping"))["result"] as? [String: Any] != nil)
        let tools = ((await mcp.request(2, "tools/list"))["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
        #expect(tools.count == 20)
        let names = tools.compactMap { $0["name"] as? String }
        #expect(Set(names).count == names.count)
        for name in ["adapter_status", "scan_vehicle", "list_modules", "read_dtcs", "read_identification", "read_did", "read_live", "explain_dtc", "last_report"] {
            #expect(names.contains(name), "\(name)")
        }
        for tool in tools {
            let schema = tool["inputSchema"] as? [String: Any]
            #expect(schema?["type"] as? String == "object")
            #expect(schema?["additionalProperties"] as? Bool == false)
            let annotations = tool["annotations"] as? [String: Any]
            #expect(annotations?["readOnlyHint"] as? Bool == true)
            #expect(annotations?["destructiveHint"] as? Bool == false)
            #expect((tool["description"] as? String)?.isEmpty == false)
        }
        let scan = tools.first { $0["name"] as? String == "scan_vehicle" }
        let properties = (scan?["inputSchema"] as? [String: Any])?["properties"] as? [String: Any]
        #expect(properties?["sim"] != nil)
        #expect(properties?["route"] != nil)
        let explain = tools.first { $0["name"] as? String == "explain_dtc" }
        #expect(((explain?["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])?["sim"] == nil)
    }

    @Test func protocolErrorsUseJSONRPCCodes() async {
        let mcp = MCPHarness()
        await mcp.sendRaw("{nicht json")
        await mcp.sendRaw("[{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"ping\"}]")
        await mcp.sendRaw("{\"jsonrpc\":\"2.0\",\"id\":10}")
        let unknown = await mcp.request(11, "resources/list")
        let tool = await mcp.request(12, "tools/call", ["name": "flash_ecu", "arguments": [:]])
        let noName = await mcp.request(13, "tools/call", ["arguments": [:]])
        let codes = mcp.sink.messages.compactMap { ($0["error"] as? [String: Any])?["code"] as? Int }
        #expect(codes.prefix(3) == [-32700, -32600, -32600])
        #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32601)
        #expect((tool["error"] as? [String: Any])?["code"] as? Int == -32602)
        #expect((noName["error"] as? [String: Any])?["code"] as? Int == -32602)
    }

    @Test func notificationsGetNoAnswer() async {
        let mcp = MCPHarness()
        await mcp.send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        await mcp.send(["jsonrpc": "2.0", "method": "notifications/unknown"])
        await mcp.send(["jsonrpc": "2.0", "id": 5, "result": [:]])
        await mcp.server.drain()
        #expect(mcp.sink.lines.isEmpty)
    }

    @Test func cancelledCallsStayUnanswered() async throws {
        let mcp = MCPHarness()
        await mcp.send(["jsonrpc": "2.0", "id": 21, "method": "tools/call",
                        "params": ["name": "read_live", "arguments": ["sim": "mondeo-mk4", "pids": ["0C"], "interval_ms": 20, "count": 2000, "duration_s": 60]]])
        try await Task.sleep(for: .milliseconds(150))
        await mcp.send(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 21, "reason": "Test"]])
        let ping = await mcp.request(22, "ping")
        #expect(ping["result"] != nil)
        #expect(mcp.response(21) == nil)
    }

    @Test func stdioRoundTripOverPipes() async throws {
        let input = Pipe()
        let mcp = MCPHarness()
        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"pipe","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"explain_nrc","arguments":{"code":"31"}}}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"adapter_status","arguments":{"sim":"focus-mk4"}}}"#,
        ]
        input.fileHandleForWriting.write(Data((requests.joined(separator: "\n") + "\n").utf8))
        try input.fileHandleForWriting.close()
        await mcp.server.run(lines: input.fileHandleForReading.bytes.lines)
        let messages = mcp.sink.messages
        #expect(messages.count == 3)
        #expect(mcp.sink.lines.allSatisfy { !$0.contains("\n") })
        let nrc = (mcp.response(2)?["result"] as? [String: Any])?.envelope
        #expect((nrc?["data"] as? [String: Any])?["name"] as? String == "requestOutOfRange")
        let adapter = (mcp.response(3)?["result"] as? [String: Any])?.envelope
        #expect((adapter?["meta"] as? [String: Any])?["link"] as? String == "simulator:focus-mk4")
    }
}
