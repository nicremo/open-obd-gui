import AdapterKit
import ArgumentParser
import DiagnosticEngine
import Foundation
import OBDCore

enum CLIError: Error, Equatable {
    /// Wrong input by the caller.
    case usage(String)
    /// File could not be read or written.
    case file(String)
    /// No report exists yet in the session, the app or the archive.
    case noReport
}

struct CLIErrorPayload: Codable, Equatable, Sendable {
    let code: String
    let message: String
    let hint: String?
}

struct CLIMeta: Codable, Sendable {
    let tool: String
    let durationMs: Int
    let link: String?
    let capture: String?
}

struct Envelope<Payload: Encodable>: Encodable {
    let schema: String
    let command: String
    let ok: Bool
    let data: Payload?
    let warnings: [String]
    let error: CLIErrorPayload?
    let meta: CLIMeta
}

struct NoPayload: Encodable, Sendable {}

struct CLIResult<Payload: Encodable & Sendable> {
    var data: Payload
    var human: String
    var warnings: [String] = []
}

/// Resources of one command run. Confined to that run.
final class CLIContext {
    var backend: (any DiagnosticBackend)?
    var link: String?
    var capturePath: String?
    private var eventTask: Task<Void, Never>?

    /// Takes ownership of the backend. Verbose traffic and step progress go to stderr, `observer` sees every event.
    func attach(_ backend: any DiagnosticBackend, verbose: Bool, progress: Bool, observer: (@Sendable (EngineEvent) -> Void)? = nil) {
        self.backend = backend
        link = backend.linkLabel
        guard verbose || progress || observer != nil else { return }
        let events = backend.events
        eventTask = Task {
            for await event in events {
                observer?(event)
                switch event {
                case .traffic(let traffic) where verbose:
                    let text = traffic.text.replacingOccurrences(of: "\r", with: " ").trimmingCharacters(in: .whitespaces)
                    switch traffic.direction {
                    case .sent: Output.errorLine("-> \(text)")
                    case .received: Output.errorLine("<- \(text)")
                    case .failed: Output.errorLine("!! \(text)")
                    }
                case .stepFinished(let step, let summary) where progress:
                    Output.errorLine("✓ \(step.title): \(summary)")
                case .stepFailed(let step, let message) where progress:
                    Output.errorLine("✗ \(step.title): \(message)")
                default:
                    continue
                }
            }
        }
    }

    /// Closes the backend, then waits until every event of the run was handled.
    func cleanup() async {
        if let backend {
            await backend.close()
        }
        await eventTask?.value
        backend = nil
        eventTask = nil
    }
}

enum CLI {
    static let schema = "openobd.cli/1"

    /// Runs one command: body, cleanup, then exactly one JSON envelope (or human text) and the right exit code.
    static func execute<Payload: Encodable & Sendable>(_ command: String, json: Bool,
                                                       _ body: (CLIContext) async throws -> CLIResult<Payload>) async throws {
        let (outcome, meta) = await run(body)
        switch outcome {
        case .success(let result):
            if json {
                Output.line(try envelope(command, outcome, meta: meta))
            } else {
                if !result.human.isEmpty { Output.line(result.human) }
                result.warnings.forEach { Output.errorLine("Hinweis: \($0)") }
            }
        case .failure(let error):
            if let exit = error as? ExitCode { throw exit }
            if json {
                Output.line(try envelope(command, outcome, meta: meta))
            } else {
                let payload = errorPayload(error)
                Output.errorLine("Fehler: \(payload.message)")
                if let hint = payload.hint { Output.errorLine("Tipp: \(hint)") }
            }
            throw ExitCode(exitCode(for: error))
        }
    }

    /// Body and cleanup without any output. Shared by the CLI and the MCP server.
    static func run<Payload: Encodable & Sendable>(_ body: (CLIContext) async throws -> CLIResult<Payload>) async
        -> (Result<CLIResult<Payload>, any Error>, CLIMeta) {
        let context = CLIContext()
        let started = ContinuousClock.now
        let outcome: Result<CLIResult<Payload>, any Error>
        do {
            outcome = .success(try await body(context))
        } catch {
            outcome = .failure(error)
        }
        await context.cleanup()
        let meta = CLIMeta(tool: OpenOBD.toolDescription, durationMs: Int((ContinuousClock.now - started).wholeMilliseconds),
                           link: context.link, capture: context.capturePath)
        return (outcome, meta)
    }

    /// The `openobd.cli/1` envelope of one outcome.
    static func envelope<Payload: Encodable & Sendable>(_ command: String, _ outcome: Result<CLIResult<Payload>, any Error>,
                                                        meta: CLIMeta, pretty: Bool = true) throws -> String {
        switch outcome {
        case .success(let result):
            return try encode(Envelope(schema: schema, command: command, ok: true, data: result.data, warnings: result.warnings, error: nil, meta: meta),
                              pretty: pretty)
        case .failure(let error):
            return try encode(Envelope<NoPayload>(schema: schema, command: command, ok: false, data: nil, warnings: [], error: errorPayload(error), meta: meta),
                              pretty: pretty)
        }
    }

    static func errorPayload(_ error: any Error) -> CLIErrorPayload {
        if let error = error as? OBDError {
            if case .portBusy = error, BridgeClient.isReachable() {
                return CLIErrorPayload(code: error.code, message: error.message,
                                       hint: "Open OBD GUI hält den Adapter. Mit --via-app läuft der Befehl in der App.")
            }
            return CLIErrorPayload(code: error.code, message: error.message, hint: error.hint)
        }
        if let error = error as? BridgeError {
            return CLIErrorPayload(code: error.code, message: error.message, hint: error.hint)
        }
        if let error = error as? CLIError {
            switch error {
            case .usage(let message): return CLIErrorPayload(code: "USAGE_ERROR", message: message, hint: "Hilfe: openobd <befehl> --help")
            case .file(let message): return CLIErrorPayload(code: "FILE_ERROR", message: message, hint: nil)
            case .noReport: return CLIErrorPayload(code: "NO_REPORT", message: "Es gibt noch keinen Bericht.", hint: "Erst auslesen: openobd scan oder das Werkzeug scan_vehicle.")
            }
        }
        return CLIErrorPayload(code: "INTERNAL_ERROR", message: String(describing: error), hint: nil)
    }

    static func exitCode(for error: any Error) -> Int32 {
        if let error = error as? OBDError {
            switch error {
            case .adapterNotFound: return 3
            case .portBusy: return 7
            case .policyDenied: return 6
            case .vehicleNotResponding, .noData, .canError, .negativeResponse, .noVehiclePower: return 5
            case .cancelled: return 130
            case .malformedResponse, .busy: return 1
            case .portOpenFailed, .io, .timeout, .adapterNotResponding, .adapterRejected, .busUnavailable,
                 .busBusy, .bufferFull, .adapterError, .disconnected: return 4
            }
        }
        if let error = error as? BridgeError {
            switch error.code {
            case "APP_NOT_RUNNING": return 8
            case "APP_BUSY": return 7
            case "INTERNAL_ERROR": return 1
            default: return 4
            }
        }
        if error is CLIError { return 2 }
        return 1
    }

    /// Errors after which further requests to the adapter make no sense.
    static func isFatal(_ error: OBDError) -> Bool {
        switch error {
        case .disconnected, .cancelled, .adapterNotResponding: true
        default: false
        }
    }

    static func encode<T: Encodable>(_ value: T, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func write(_ data: Data, to path: String) throws {
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            throw CLIError.file("\(path) konnte nicht geschrieben werden: \(error.localizedDescription)")
        }
    }
}

