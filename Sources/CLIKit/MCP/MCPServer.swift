import DiagnosticEngine
import Foundation
import Synchronization

/// Model Context Protocol over newline delimited JSON-RPC 2.0. One tool call at a time, because one adapter
/// answers one request at a time; cancellation and progress follow the MCP base protocol.
public final class MCPServer: Sendable {
    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    static let instructions = """
        Open OBD GUI liest Ford-Fahrzeuge (Mondeo Mk4, Focus Mk4) über einen OBDLink EX nur lesend aus. \
        Ablauf: app_status oder adapter_status prüfen, dann scan_vehicle mit digest true für den Überblick, \
        Einzelheiten mit read_dtcs, read_identification, read_did und read_live, Erklärungen ohne Fahrzeug mit explain_dtc und den übrigen explain-Werkzeugen. \
        Ohne Hardware sim mondeo-mk4 oder focus-mk4 angeben, die Daten sind dann synthetisch. \
        Läuft die App mit echtem Adapter, gehen Aufrufe über die App (route auto) und die App zeigt mit, was gelesen wird. \
        Werte mit confidence community oder unknown sind keine Tatsachen. Schreibende Dienste sind gesperrt.
        """

    private struct State: Sendable {
        var lastReport: VehicleReport?
        var running: [String: Task<Void, Never>] = [:]
    }

    private let runner: MCPToolRunner
    private let output: @Sendable (String) -> Void
    private let writeLock = Mutex(())
    private let state = Mutex(State())
    private let gate = SerialGate()

    public init(defaults: MCPDefaults = MCPDefaults(), store: ReportStore = ReportStore(), write: @escaping @Sendable (String) -> Void) {
        runner = MCPToolRunner(defaults: defaults.spec, store: store)
        output = write
    }

    /// Reads requests until the input ends, then finishes the calls still running.
    public func run<Lines: AsyncSequence>(lines: Lines) async where Lines.Element == String {
        do {
            for try await line in lines {
                await handle(line: line)
            }
        } catch {
            FileHandle.standardError.write(Data("openobd mcp: Eingabe abgebrochen: \(error)\n".utf8))
        }
        await drain()
    }

    /// Waits until every queued tool call has finished.
    func drain() async {
        await gate.drain()
    }

    func handle(line: String) async {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let request: RPCRequest
        switch RPCRequest.parse(line) {
        case .failure(let failure):
            send(RPC.error(id: failure.id, failure.error))
            return
        case .success(nil):
            return
        case .success(let parsed?):
            request = parsed
        }
        switch request.method {
        case "initialize":
            reply(request, result: initializeResult(request.params))
        case "notifications/initialized", "initialized":
            return
        case "notifications/cancelled":
            cancel(request.params?["requestId"])
        case "ping":
            reply(request, result: .object([:]))
        case "tools/list":
            reply(request, result: .object(["tools": .array(MCPTools.catalog.map(\.definition))]))
        case "tools/call":
            await call(request)
        default:
            if request.id != nil {
                fail(request, RPCError(code: RPCError.methodNotFound, message: "Method not found: \(request.method)"))
            }
        }
    }

    private func initializeResult(_ params: JSONValue?) -> JSONValue {
        let requested = params?["protocolVersion"]?.string
        let version = requested.flatMap { Self.protocolVersions.contains($0) ? $0 : nil } ?? Self.protocolVersions[0]
        return .object([
            "protocolVersion": .string(version),
            "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
            "serverInfo": .object(["name": .string(OpenOBD.toolName), "title": .string("Open OBD GUI"), "version": .string(OpenOBD.version)]),
            "instructions": .string(Self.instructions),
        ])
    }

    private func call(_ request: RPCRequest) async {
        guard let id = request.id else { return }
        guard let params = request.params?.object, let name = params["name"]?.string else {
            fail(request, RPCError(code: RPCError.invalidParams, message: "tools/call braucht params.name"))
            return
        }
        guard let tool = MCPTools.tool(named: name) else {
            fail(request, RPCError(code: RPCError.invalidParams, message: "Unknown tool: \(name)"))
            return
        }
        let arguments = params["arguments"]
        let token = params["_meta"]?["progressToken"]
        let key = id.line
        let task = await gate.enqueue { [self] in
            let session = state.withLock { $0.lastReport }
            let outcome = await runner.run(tool, arguments: arguments, session: session, observer: token.map { progress(token: $0, tool: tool) })
            state.withLock { state in
                state.running[key] = nil
                if let report = outcome.report { state.lastReport = report }
            }
            // A cancelled request gets no response (MCP cancellation).
            guard !Task.isCancelled else { return }
            let envelope = (try? JSONValue.parse(outcome.envelope)) ?? .object([:])
            reply(request, result: .object([
                "content": .array([.object(["type": .string("text"), "text": .string(outcome.envelope)])]),
                "structuredContent": envelope,
                "isError": .bool(!outcome.ok),
            ]))
        }
        state.withLock { $0.running[key] = task }
    }

    /// Progress of a scan: one notification per finished, skipped or failed step. The pipeline reports every step,
    /// steps outside the chosen depth as skipped, so a scan has `ScanStep.allCases.count` steps.
    private func progress(token: JSONValue, tool: MCPTool) -> @Sendable (EngineEvent) -> Void {
        let total = tool.name == "scan_vehicle" ? ScanStep.allCases.count : nil
        let done = Atomic(0)
        return { [self] event in
            let message: String
            switch event {
            case .stepFinished(let step, let summary): message = "\(step.title): \(summary)"
            case .stepSkipped(let step, let reason): message = "\(step.title) übersprungen: \(reason)"
            case .stepFailed(let step, let failure): message = "\(step.title) fehlgeschlagen: \(failure)"
            default: return
            }
            let count = done.wrappingAdd(1, ordering: .relaxed).newValue
            var params: [String: JSONValue] = ["progressToken": token, "progress": .int(count), "message": .string(message)]
            if let total { params["total"] = .int(max(total, count)) }
            send(RPC.notification("notifications/progress", .object(params)))
        }
    }

    private func cancel(_ requestID: JSONValue?) {
        guard let requestID else { return }
        state.withLock { $0.running[requestID.line] }?.cancel()
    }

    private func reply(_ request: RPCRequest, result: JSONValue) {
        guard let id = request.id else { return }
        send(RPC.result(id: id, result))
    }

    private func fail(_ request: RPCRequest, _ error: RPCError) {
        guard let id = request.id else { return }
        send(RPC.error(id: id, error))
    }

    private func send(_ message: JSONValue) {
        let line = message.line
        writeLock.withLock { _ in output(line) }
    }
}

/// Defaults of `openobd mcp`, applied to every call unless the call says otherwise.
public struct MCPDefaults: Sendable {
    var spec: ConnectionSpec

    public init(sim: String? = nil, port: String? = nil, vehicle: String? = nil, route: String = "auto", bridgeSocket: String? = nil) {
        spec = ConnectionSpec(port: port, sim: sim, vehicle: vehicle, route: ConnectionSpec.Route(rawValue: route) ?? .auto, bridgeSocket: bridgeSocket)
    }
}

/// Runs work strictly one after another. Each item is its own task, so it can be cancelled alone.
actor SerialGate {
    private var tail: Task<Void, Never>?

    func enqueue(_ work: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        let previous = tail
        let task = Task {
            await previous?.value
            await work()
        }
        tail = task
        return task
    }

    func drain() async {
        while let current = tail {
            await current.value
            if tail == current { return }
        }
    }
}
