import AdapterKit
import DiagnosticEngine
import Foundation
import OBDCore
import VehicleSim

/// Opens a backend only after a command validated its own arguments, so input errors never touch the adapter.
typealias Connector = () async throws -> any DiagnosticBackend

/// How a command reaches the vehicle. Built from CLI options or MCP arguments.
struct ConnectionSpec: Sendable, Equatable {
    enum Route: String, Sendable, CaseIterable {
        /// Own connection: adapter, simulator or capture.
        case direct
        /// The session of the running app over the bridge socket.
        case app
        /// The app when it holds a real adapter, otherwise direct. Never mistakes app simulator data for the car.
        case auto
    }

    var port: String?
    var sim: String?
    var replay: String?
    var replayMode = "lookup"
    var capture: String?
    var vehicle: String?
    var verbose = false
    var route: Route = .direct
    var bridgeSocket: String?

    var socketPath: String { bridgeSocket ?? BridgeEndpoint.defaultPath }

    /// A source of its own, which the app cannot provide.
    var needsOwnConnection: Bool { sim != nil || replay != nil || port != nil || capture != nil }

    func open(_ context: CLIContext, progress: Bool = false, observer: (@Sendable (EngineEvent) -> Void)? = nil) async throws -> any DiagnosticBackend {
        if route == .app, needsOwnConnection {
            throw CLIError.usage("Über die App gehen --sim, --replay, --port und --capture nicht. Die App nutzt ihre eigene Verbindung.")
        }
        let backend = try await choose(context)
        context.attach(backend, verbose: verbose, progress: progress, observer: observer)
        return backend
    }

    private func choose(_ context: CLIContext) async throws -> any DiagnosticBackend {
        switch route {
        case .direct:
            return try makeSession(context)
        case .app:
            return try await BridgeClient.connect(at: socketPath)
        case .auto:
            if !needsOwnConnection, BridgeClient.isReachable(at: socketPath), let client = try? await BridgeClient.connect(at: socketPath) {
                if !client.hello.simulated { return client }
                await client.close()
            }
            return try makeSession(context)
        }
    }

    private func makeSession(_ context: CLIContext) throws -> DiagnosticSession {
        var link: any AdapterLink
        var simulated = false
        var title: String?
        if let sim {
            guard let profile = VehicleProfile.named(sim) else {
                throw CLIError.usage("Unbekanntes Simulatorprofil \(sim). Verfügbar: \(VehicleProfile.all.map(\.id).joined(separator: ", "))")
            }
            link = SimulatedLink(profile: profile)
            simulated = true
            title = profile.title
        } else if let replay {
            guard let mode = ReplayLink.Mode(rawValue: replayMode) else {
                throw CLIError.usage("Unbekannter Abspielmodus \(replayMode). Erlaubt: strict, lookup")
            }
            do {
                link = try ReplayLink.load(URL(fileURLWithPath: replay), mode: mode)
            } catch let error as OBDError {
                throw error
            } catch {
                throw CLIError.file("Mitschnitt \(replay) konnte nicht gelesen werden: \(error.localizedDescription)")
            }
        } else {
            link = try SerialLink.open(path: port ?? Self.automaticPort())
        }
        if let capture {
            let recorder = try CaptureRecorder(url: URL(fileURLWithPath: capture), tool: OpenOBD.toolDescription, link: link.label)
            link = CapturingLink(base: link, recorder: recorder)
            context.capturePath = capture
        }
        return DiagnosticSession(link: link, simulated: simulated, vehicleTitle: title, vehicleHint: vehicle ?? sim)
    }

    static func automaticPort() throws -> String {
        guard let best = DeviceDiscovery.candidates().first(where: \.isLikelyOBDAdapter) else {
            throw OBDError.adapterNotFound
        }
        return best.path
    }

    static func route(_ text: String) throws -> Route {
        guard let route = Route(rawValue: text.lowercased()) else {
            throw CLIError.usage("Unbekannter Weg \(text). Erlaubt: \(Route.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return route
    }
}
