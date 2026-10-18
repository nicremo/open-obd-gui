import DiagnosticEngine
import Foundation

/// Arguments of one tool call, checked against the tool's schema. Wrong input is a usage error the model can fix.
struct ToolArguments {
    let values: [String: JSONValue]

    init(_ value: JSONValue?, tool: MCPTool) throws {
        switch value {
        case nil, .null:
            values = [:]
        case .object(let object):
            values = object
        default:
            throw CLIError.usage("Die Argumente von \(tool.name) müssen ein Objekt sein.")
        }
        let unknown = Set(values.keys).subtracting(tool.allowedArguments).sorted()
        guard unknown.isEmpty else {
            throw CLIError.usage("Unbekannte Argumente für \(tool.name): \(unknown.joined(separator: ", ")). Erlaubt: \(tool.allowedArguments.sorted().joined(separator: ", "))")
        }
        for key in tool.required where values[key] == nil || values[key] == .null {
            throw CLIError.usage("\(tool.name) braucht das Argument \(key).")
        }
    }

    func string(_ key: String) throws -> String? {
        switch values[key] {
        case nil, .null: return nil
        case .string(let value): return value
        default: throw CLIError.usage("\(key) muss ein Text sein.")
        }
    }

    func bool(_ key: String, default fallback: Bool = false) throws -> Bool {
        switch values[key] {
        case nil, .null: return fallback
        case .bool(let value): return value
        default: throw CLIError.usage("\(key) muss true oder false sein.")
        }
    }

    func int(_ key: String, default fallback: Int, in range: ClosedRange<Int>) throws -> Int {
        let value: Int
        switch values[key] {
        case nil, .null: return fallback
        case .int(let number): value = number
        case .double(let number) where number == number.rounded(): value = Int(number)
        default: throw CLIError.usage("\(key) muss eine ganze Zahl sein.")
        }
        guard range.contains(value) else { throw CLIError.usage("\(key) muss zwischen \(range.lowerBound) und \(range.upperBound) liegen.") }
        return value
    }

    func double(_ key: String, default fallback: Double, in range: ClosedRange<Double>) throws -> Double {
        let value: Double
        switch values[key] {
        case nil, .null: return fallback
        case .int(let number): value = Double(number)
        case .double(let number): value = number
        default: throw CLIError.usage("\(key) muss eine Zahl sein.")
        }
        guard range.contains(value) else { throw CLIError.usage("\(key) muss zwischen \(range.lowerBound) und \(range.upperBound) liegen.") }
        return value
    }

    func strings(_ key: String) throws -> [String]? {
        switch values[key] {
        case nil, .null: return nil
        case .array(let items):
            return try items.map {
                guard case .string(let text) = $0 else { throw CLIError.usage("\(key) muss eine Liste von Texten sein.") }
                return text
            }
        default: throw CLIError.usage("\(key) muss eine Liste sein.")
        }
    }

    /// Server defaults, overridden per call. A source given in the call replaces the default source.
    func connection(_ defaults: ConnectionSpec) throws -> ConnectionSpec {
        var spec = defaults
        let sim = try string("sim")
        let port = try string("port")
        let replay = try string("replay")
        if sim != nil || port != nil || replay != nil {
            spec.sim = sim
            spec.port = port
            spec.replay = replay
        }
        if let mode = try string("replay_mode") { spec.replayMode = mode }
        if let capture = try string("capture") { spec.capture = capture }
        if let vehicle = try string("vehicle") { spec.vehicle = vehicle }
        if let route = try string("route") { spec.route = try ConnectionSpec.route(route) }
        return spec
    }
}

/// Result of one tool call: the envelope, plus the scanned report for `last_report`.
struct ToolOutcome: Sendable {
    let envelope: String
    let ok: Bool
    let report: VehicleReport?
}

/// Runs MCP tools through the same `perform` functions as the CLI commands.
struct MCPToolRunner: Sendable {
    let defaults: ConnectionSpec
    let store: ReportStore

    func run(_ tool: MCPTool, arguments: JSONValue?, session: VehicleReport?,
             observer: (@Sendable (EngineEvent) -> Void)?) async -> ToolOutcome {
        var scanned: VehicleReport?
        let outcome: ToolOutcome
        switch tool.name {
        case "list_devices":
            outcome = await envelope(tool, arguments, observer) { _, _ in DevicesCommand.perform() }
        case "app_status":
            outcome = await envelope(tool, arguments, observer) { _, _ in await AppCommand.perform(socket: defaults.socketPath) }
        case "adapter_status":
            outcome = await envelope(tool, arguments, observer) { arguments, connect in try await AdapterCommand.perform(connect(arguments)) }
        case "scan_vehicle":
            outcome = await envelope(tool, arguments, observer) { arguments, connect in
                let depth = try arguments.string("depth").map { text in
                    guard let depth = ScanDepth(rawValue: text) else { throw CLIError.usage("Unbekannte Tiefe \(text). Erlaubt: quick, standard, deep") }
                    return depth
                } ?? .standard
                return try await ScanCommand.perform(connect(arguments), depth: depth, out: arguments.string("out"), markdown: arguments.string("markdown"),
                                                     archive: arguments.bool("archive"), digest: arguments.bool("digest"), store: store) { scanned = $0 }
            }
        case "list_modules":
            outcome = await envelope(tool, arguments, observer) { arguments, connect in
                try await ModulesCommand.perform(connect(arguments), bus: arguments.string("bus") ?? "all", sweep: arguments.bool("sweep"))
            }
        case "read_dtcs":
            outcome = await envelope(tool, arguments, observer) { arguments, connect in
                try await DTCCommand.perform(connect(arguments), module: arguments.string("module"), bus: arguments.string("bus") ?? "hs",
                                             obdOnly: arguments.bool("obd_only"))
            }
        case "read_identification":
            outcome = await envelope(tool, arguments, observer) { arguments, connect in
                try await IdentCommand.perform(connect(arguments), module: arguments.string("module") ?? "", bus: arguments.string("bus") ?? "hs",
                                               full: arguments.bool("full"))
            }
        case "read_did":
            outcome = await envelope(tool, arguments, observer) { arguments, connect in
                try await ReadDIDCommand.perform(connect(arguments), module: arguments.string("module") ?? "", bus: arguments.string("bus") ?? "hs",
                                                 did: arguments.string("did") ?? "")
            }
        case "list_pids":
            outcome = await envelope(tool, arguments, observer) { arguments, connect in try await PIDsCommand.perform(connect(arguments), catalog: arguments.bool("catalog")) }
        case "read_live":
            outcome = await envelope(tool, arguments, observer) { arguments, connect in
                try await LiveCommand.collect(connect(arguments), pids: arguments.strings("pids") ?? [],
                                              interval: arguments.int("interval_ms", default: 500, in: 20...10_000),
                                              count: arguments.int("count", default: 20, in: 1...MCPLimits.liveCount),
                                              duration: arguments.double("duration_s", default: 10, in: 0.1...MCPLimits.liveSeconds))
            }
        case "raw_request":
            outcome = await envelope(tool, arguments, observer) { arguments, connect in
                try await RawCommand.perform(connect(arguments), payload: arguments.string("payload") ?? "", module: arguments.string("module"),
                                             functional: arguments.bool("functional"), bus: arguments.string("bus") ?? "hs",
                                             timeout: arguments.int("timeout_ms", default: 500, in: 50...10_000))
            }
        case "explain_dtc":
            outcome = await envelope(tool, arguments, observer) { arguments, _ in try ExplainDTCCommand.perform(arguments.string("code") ?? "") }
        case "explain_pid":
            outcome = await envelope(tool, arguments, observer) { arguments, _ in try ExplainPIDCommand.perform(arguments.string("pid") ?? "") }
        case "explain_nrc":
            outcome = await envelope(tool, arguments, observer) { arguments, _ in try ExplainNRCCommand.perform(arguments.string("code") ?? "") }
        case "explain_did":
            outcome = await envelope(tool, arguments, observer) { arguments, _ in try ExplainDIDCommand.perform(arguments.string("did") ?? "") }
        case "explain_module":
            outcome = await envelope(tool, arguments, observer) { arguments, _ in try ExplainModuleCommand.perform(arguments.string("module") ?? "") }
        case "last_report":
            outcome = await envelope(tool, arguments, observer) { arguments, _ in
                try await ReportLastCommand.perform(source: arguments.string("source") ?? "auto", digest: arguments.bool("digest"),
                                                    socket: defaults.socketPath, store: store, session: session)
            }
        case "read_report":
            outcome = await envelope(tool, arguments, observer) { arguments, _ in
                try ReportShowCommand.perform(path: arguments.string("path") ?? "", markdown: false, digest: arguments.bool("digest"))
            }
        case "list_reports":
            outcome = await envelope(tool, arguments, observer) { arguments, _ in
                try ReportListCommand.perform(store: store, limit: arguments.int("limit", default: 20, in: 0...10_000))
            }
        default:
            outcome = await envelope(tool, arguments, observer) { _, _ in CapabilitiesCommand.perform() }
        }
        return ToolOutcome(envelope: outcome.envelope, ok: outcome.ok, report: outcome.ok ? scanned : nil)
    }

    /// Parses the arguments inside the run, so their errors become envelopes too.
    private func envelope<Payload: Encodable & Sendable>(
        _ tool: MCPTool, _ arguments: JSONValue?, _ observer: (@Sendable (EngineEvent) -> Void)?,
        _ body: (ToolArguments, (ToolArguments) throws -> Connector) async throws -> CLIResult<Payload>
    ) async -> ToolOutcome {
        let (result, meta) = await CLI.run { context in
            let parsed = try ToolArguments(arguments, tool: tool)
            return try await body(parsed) { arguments in
                let spec = try arguments.connection(defaults)
                return { try await spec.open(context, observer: observer) }
            }
        }
        let text = (try? CLI.envelope(tool.command, result, meta: meta, pretty: false)) ?? "{}"
        if case .success = result { return ToolOutcome(envelope: text, ok: true, report: nil) }
        return ToolOutcome(envelope: text, ok: false, report: nil)
    }
}
