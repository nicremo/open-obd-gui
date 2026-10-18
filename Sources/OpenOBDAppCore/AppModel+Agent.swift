import DiagnosticEngine
import Foundation
import OBDCore

public enum AgentBridgeStatus: Equatable, Sendable {
    case off
    case ready(path: String)
    case failed(String)
}

/// Agents read through the app's own session, so the window shows progress, traffic and the report.
extension AppModel {
    /// Something runs that a second request would disturb: a scan, a connection attempt or an agent request.
    public var isOccupied: Bool { phase.isBusy || agentActivity != nil }

    public func startAgentBridge(at path: String = BridgeEndpoint.defaultPath) {
        guard bridgeServer == nil else { return }
        do {
            bridgeServer = try BridgeServer.start(at: path, handler: AppBridgeHandler(model: self))
            agentBridge = .ready(path: path)
        } catch let error as BridgeError {
            agentBridge = .failed(error.message)
        } catch {
            agentBridge = .failed(String(describing: error))
        }
    }

    public func stopAgentBridge() {
        bridgeServer?.stop()
        bridgeServer = nil
        agentBridge = .off
    }

    func bridgeHello() -> BridgeHello {
        let link: String
        if let session {
            link = session.linkLabel
        } else {
            switch choice {
            case .simulator(let profile): link = "simulator:\(profile)"
            case .port(let path): link = path
            case .automatic: link = "automatisch"
            }
        }
        return BridgeHello(app: "Open OBD GUI \(OpenOBD.version)", link: link, simulated: choice.simulatorProfile != nil,
                           connected: adapter != nil, activity: occupation)
    }

    func performForAgent(_ operation: BridgeOperation, events: @escaping @Sendable (EngineEvent) -> Void,
                         records: @escaping @Sendable (MeasurementRecord) -> Void) async throws -> BridgeResult {
        switch operation {
        case .hello: return .hello(bridgeHello())
        case .lastReport: return .lastReport(report)
        default: break
        }
        if let occupation { throw BridgeError.appBusy(occupation) }
        agentActivity = operation.title
        defer { agentActivity = nil }
        let session: DiagnosticSession
        do {
            session = try ensureSession()
        } catch {
            await fail(error)
            throw error
        }
        let token = session.observers.add(events)
        defer { session.observers.remove(token) }
        do {
            switch operation {
            case .scan(let depth):
                return .report(try await runScan(depth: depth))
            case .connect:
                let summary = try await retryingBusy { try await session.connect() }
                adapter = summary
                phase = .connected
                return .adapter(summary)
            default:
                if adapter == nil {
                    adapter = try await retryingBusy { try await session.connect() }
                    phase = .connected
                }
                return try await BridgeDispatch.perform(operation, on: session, records: records)
            }
        } catch {
            if Self.showsInWindow(error, during: operation) { await fail(error) }
            throw error
        }
    }

    /// Why the app cannot take a request right now, if it cannot.
    var occupation: String? {
        if let agentActivity { return "Agent: \(agentActivity)" }
        switch phase {
        case .connecting: return "Verbindung wird aufgebaut"
        case .scanning: return "Fahrzeug wird ausgelesen"
        case .live: return "Live-Daten laufen"
        default: return nil
        }
    }

    /// A failed scan and a lost connection belong in the window. A module that rejects one request does not.
    static func showsInWindow(_ error: any Error, during operation: BridgeOperation) -> Bool {
        if error is CancellationError { return false }
        guard let error = error as? OBDError else { return true }
        if error == .cancelled { return false }
        if case .scan = operation { return true }
        switch error {
        case .adapterNotFound, .portBusy, .portOpenFailed, .disconnected, .adapterNotResponding, .io: return true
        default: return false
        }
    }
}

/// Bridge requests run on the main actor through the model.
struct AppBridgeHandler: BridgeHandler {
    let model: AppModel

    func hello() async -> BridgeHello {
        await model.bridgeHello()
    }

    func perform(_ operation: BridgeOperation, events: @escaping @Sendable (EngineEvent) -> Void,
                 records: @escaping @Sendable (MeasurementRecord) -> Void) async throws -> BridgeResult {
        try await model.performForAgent(operation, events: events, records: records)
    }
}
