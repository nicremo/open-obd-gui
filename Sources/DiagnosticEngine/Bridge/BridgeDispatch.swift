import Foundation
import OBDCore

/// Runs a bridge operation on any backend. Shared by the app and the session handler.
public enum BridgeDispatch {
    /// `hello` and `lastReport` belong to the handler; every other operation maps to one backend call.
    public static func perform(_ operation: BridgeOperation, on backend: some DiagnosticBackend,
                               records: @Sendable (MeasurementRecord) -> Void) async throws -> BridgeResult {
        switch operation {
        case .hello, .lastReport:
            throw BridgeError.protocolMismatch("\(operation.title) wird vom Handler beantwortet")
        case .connect:
            return .adapter(try await backend.connect())
        case .scan(let depth):
            return .report(try await backend.scan(depth: depth))
        case .discoverModules(let buses, let sweep):
            return .modules(try await backend.discoverModules(buses: buses, sweep: sweep))
        case .readModuleTroubleCodes(let request, let bus):
            return .troubleCodes(try await backend.readModuleTroubleCodes(request: request, bus: bus))
        case .readOBDTroubleCodes:
            return .troubleCodes(try await backend.readOBDTroubleCodes())
        case .identify(let request, let bus, let full):
            return .identification(try await backend.identify(request: request, bus: bus, full: full))
        case .readDID(let did, let request, let bus):
            return .reading(try await backend.readDID(did, request: request, bus: bus))
        case .supportedPIDs:
            return .supportedPIDs(try await backend.supportedPIDs().mapValues { $0.sorted() })
        case .readPIDs(let pids):
            return .records(try await backend.readPIDs(pids))
        case .raw(let payload, let target, let bus, let timeout):
            try ReadOnlyPolicy.validate(payload)
            return .raw(try await backend.rawRequest(payload, target: target, bus: bus, timeout: .milliseconds(timeout)))
        case .live(let pids, let interval):
            guard !pids.isEmpty, interval > 0 else { throw OBDError.malformedResponse("Live-Daten brauchen PIDs und ein Intervall") }
            for try await record in backend.live(pids: pids, interval: .milliseconds(interval)) {
                records(record)
            }
            return .finished
        }
    }
}

/// Serves a plain `DiagnosticSession` over the bridge. Used by tests and headless setups.
public final class SessionBridgeHandler: BridgeHandler {
    public let session: DiagnosticSession
    private let appName: String

    public init(session: DiagnosticSession, appName: String = OpenOBD.toolDescription) {
        self.session = session
        self.appName = appName
    }

    public func hello() async -> BridgeHello {
        BridgeHello(app: appName, link: session.linkLabel, simulated: session.simulated, connected: await session.adapterSummary != nil)
    }

    public func perform(_ operation: BridgeOperation, events: @escaping @Sendable (EngineEvent) -> Void,
                        records: @escaping @Sendable (MeasurementRecord) -> Void) async throws -> BridgeResult {
        if case .lastReport = operation {
            return .lastReport(await session.lastReport)
        }
        let token = session.observers.add(events)
        defer { session.observers.remove(token) }
        return try await BridgeDispatch.perform(operation, on: session, records: records)
    }
}
