import AdapterKit
import Foundation
import OBDCore

/// Where the running app offers its session to agents.
public enum BridgeEndpoint {
    public static let environmentKey = "OPENOBD_BRIDGE_SOCKET"
    public static let protocolVersion = 1

    /// `OPENOBD_BRIDGE_SOCKET` if set, otherwise `~/Library/Application Support/Open OBD GUI/agent.sock`.
    public static var defaultPath: String {
        if let override = ProcessInfo.processInfo.environment[environmentKey], !override.isEmpty {
            return override
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Open OBD GUI/agent.sock").path
    }
}

/// One request an agent can send to the app. Mirrors `DiagnosticBackend`.
public enum BridgeOperation: Codable, Sendable, Equatable {
    case hello
    case connect
    case scan(depth: ScanDepth)
    case discoverModules(buses: [BusKind], sweep: Bool)
    case readModuleTroubleCodes(request: UInt32, bus: BusKind)
    case readOBDTroubleCodes
    case identify(request: UInt32, bus: BusKind, full: Bool)
    case readDID(did: UInt16, request: UInt32, bus: BusKind)
    case supportedPIDs
    case readPIDs(pids: [UInt8])
    case raw(payload: [UInt8], target: RequestTarget, bus: BusKind, timeoutMilliseconds: Int)
    case live(pids: [UInt8], intervalMilliseconds: Int)
    case lastReport

    /// What the app shows while it runs the request for an agent.
    public var title: String {
        switch self {
        case .hello: "Begrüßung"
        case .connect: "Adapter verbinden"
        case .scan(let depth): "Fahrzeug auslesen (\(depth.german))"
        case .discoverModules: "Steuergeräte suchen"
        case .readModuleTroubleCodes(let request, _): "Fehlerspeicher \(Hex.canID(request, extended: false)) lesen"
        case .readOBDTroubleCodes: "OBD-Fehlerspeicher lesen"
        case .identify(let request, _, _): "Kennungen \(Hex.canID(request, extended: false)) lesen"
        case .readDID(let did, let request, _): "Kennung \(String(format: "%04X", did)) von \(Hex.canID(request, extended: false)) lesen"
        case .supportedPIDs: "Unterstützte Messwerte abfragen"
        case .readPIDs: "Messwerte lesen"
        case .raw(let payload, _, _, _): "Rohanfrage \(Hex.encode(payload, separator: " "))"
        case .live: "Live-Daten für den Agenten"
        case .lastReport: "Letzten Bericht abgeben"
        }
    }
}

public enum BridgeResult: Codable, Sendable {
    case hello(BridgeHello)
    case adapter(AdapterSummary)
    case report(VehicleReport)
    case modules([DiscoveredModule])
    case troubleCodes([ReportDTC])
    case identification(IdentificationResult)
    case reading(DIDReading)
    case supportedPIDs([UInt32: [UInt8]])
    case records([MeasurementRecord])
    case raw(RequestResult)
    case lastReport(VehicleReport?)
    /// End of a live stream.
    case finished
}

/// First answer of the app: who it is and what it is connected to.
public struct BridgeHello: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var app: String
    /// Label of the app's connection, for example `simulator:mondeo-mk4` or `/dev/cu.usbserial-A1`.
    public var link: String
    public var simulated: Bool
    public var connected: Bool
    /// What the app is doing right now, if anything.
    public var activity: String?

    public init(protocolVersion: Int = BridgeEndpoint.protocolVersion, app: String, link: String, simulated: Bool, connected: Bool, activity: String? = nil) {
        self.protocolVersion = protocolVersion
        self.app = app
        self.link = link
        self.simulated = simulated
        self.connected = connected
        self.activity = activity
    }
}

/// Client to app.
public enum BridgeCommand: Codable, Sendable {
    case call(id: Int, operation: BridgeOperation)
    case cancel(id: Int)
}

/// App to client. Every call ends with exactly one `result` or `failure`.
public enum BridgeFrame: Codable, Sendable {
    case event(id: Int, event: EngineEvent)
    case record(id: Int, record: MeasurementRecord)
    case result(id: Int, result: BridgeResult)
    case failure(id: Int, failure: BridgeFailure)
}

/// Errors keep their identity across the socket, so exit codes match a local run.
public enum BridgeFailure: Codable, Sendable, Equatable {
    case obd(OBDError)
    case bridge(BridgeError)

    public init(_ error: any Error) {
        if let error = error as? OBDError {
            self = .obd(error)
        } else if let error = error as? BridgeError {
            self = .bridge(error)
        } else if error is CancellationError {
            self = .obd(.cancelled)
        } else {
            self = .bridge(.internalError(String(describing: error)))
        }
    }

    public var error: any Error {
        switch self {
        case .obd(let error): error
        case .bridge(let error): error
        }
    }
}

/// Failures of the bridge itself. Codes are stable for agents.
public struct BridgeError: Error, Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var hint: String?

    public init(code: String, message: String, hint: String? = nil) {
        self.code = code
        self.message = message
        self.hint = hint
    }

    public static func appNotRunning(path: String) -> BridgeError {
        BridgeError(code: "APP_NOT_RUNNING", message: "Open OBD GUI läuft nicht oder bietet keinen Agent-Zugang an.",
                    hint: "Starte die App oder lies ohne --via-app direkt über den Adapter. Socket: \(path)")
    }

    public static func appBusy(_ activity: String) -> BridgeError {
        BridgeError(code: "APP_BUSY", message: "Die App ist gerade beschäftigt: \(activity).",
                    hint: "Warte, bis der Vorgang fertig ist, oder pausiere die Live-Daten in der App.")
    }

    public static let disconnected = BridgeError(code: "BRIDGE_DISCONNECTED", message: "Die Verbindung zur App ist abgebrochen.",
                                                 hint: "Prüfe, ob Open OBD GUI noch läuft.")

    public static func protocolMismatch(_ detail: String) -> BridgeError {
        BridgeError(code: "BRIDGE_PROTOCOL", message: "App und openobd verstehen sich nicht: \(detail).",
                    hint: "Baue App und openobd aus demselben Stand.")
    }

    public static func alreadyRunning(path: String) -> BridgeError {
        BridgeError(code: "BRIDGE_ALREADY_RUNNING", message: "Eine andere Instanz bietet den Agent-Zugang schon an.", hint: "Socket: \(path)")
    }

    public static func socket(_ detail: String) -> BridgeError {
        BridgeError(code: "BRIDGE_SOCKET", message: "Der Agent-Zugang konnte nicht eingerichtet werden: \(detail).")
    }

    public static func internalError(_ detail: String) -> BridgeError {
        BridgeError(code: "INTERNAL_ERROR", message: detail)
    }
}

/// One JSON object per line. Dates stay numbers, so live timestamps keep their milliseconds.
enum BridgeCoding {
    static func line<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, from line: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(line.utf8))
    }
}
