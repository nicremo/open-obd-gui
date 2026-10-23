import Foundation

/// Every failure the diagnostic stack can report. `code` values are a stable contract for CLI and MCP consumers.
public enum OBDError: Error, Equatable, Sendable, Codable {
    case adapterNotFound
    case portBusy(String)
    case portOpenFailed(path: String, errno: Int32)
    case io(String)
    case timeout(String)
    case adapterNotResponding
    case adapterRejected(command: String, reply: String)
    case busUnavailable(String)
    case noData
    case canError
    case busBusy
    case bufferFull
    case adapterError(String)
    case policyDenied(String)
    case malformedResponse(String)
    case negativeResponse(service: UInt8, code: UInt8)
    case vehicleNotResponding
    /// Pin 16 delivers (almost) nothing. A USB adapter keeps running on USB power and only reports a bus error.
    case noVehiclePower(Double)
    case cancelled
    case disconnected
    case busy

    public var code: String {
        switch self {
        case .adapterNotFound: "ADAPTER_NOT_FOUND"
        case .portBusy: "PORT_BUSY"
        case .portOpenFailed: "PORT_OPEN_FAILED"
        case .io: "IO_ERROR"
        case .timeout: "TIMEOUT"
        case .adapterNotResponding: "ADAPTER_NOT_RESPONDING"
        case .adapterRejected: "ADAPTER_REJECTED_COMMAND"
        case .busUnavailable: "BUS_UNAVAILABLE"
        case .noData: "NO_DATA"
        case .canError: "CAN_ERROR"
        case .busBusy: "BUS_BUSY"
        case .bufferFull: "BUFFER_FULL"
        case .adapterError: "ADAPTER_ERROR"
        case .policyDenied: "POLICY_DENIED"
        case .malformedResponse: "MALFORMED_RESPONSE"
        case .negativeResponse: "NEGATIVE_RESPONSE"
        case .vehicleNotResponding: "VEHICLE_NOT_RESPONDING"
        case .noVehiclePower: "NO_VEHICLE_POWER"
        case .cancelled: "CANCELLED"
        case .disconnected: "DISCONNECTED"
        case .busy: "BUSY"
        }
    }

    /// One plain German sentence for humans.
    public var message: String {
        switch self {
        case .adapterNotFound:
            "Kein OBD-Adapter gefunden."
        case .portBusy(let path):
            "Der Adapter \(path) wird bereits von einem anderen Programm verwendet."
        case .portOpenFailed(let path, let number):
            "Der Adapter \(path) ließ sich nicht öffnen (\(String(cString: strerror(number))))."
        case .io(let detail):
            "Übertragungsfehler: \(detail)"
        case .timeout(let detail):
            "Zeitüberschreitung: \(detail)"
        case .adapterNotResponding:
            "Der Adapter antwortet nicht."
        case .adapterRejected(let command, let reply):
            "Der Adapter hat \(command) abgelehnt (Antwort: \(reply))."
        case .busUnavailable(let detail):
            "Bus nicht verfügbar: \(detail)"
        case .noData:
            "Keine Antwort vom Fahrzeug."
        case .canError:
            "CAN-Fehler: Der Adapter erreicht den Fahrzeugbus nicht."
        case .busBusy:
            "Der Fahrzeugbus ist dauerhaft belegt."
        case .bufferFull:
            "Der Pufferspeicher des Adapters ist voll."
        case .adapterError(let detail):
            "Adapterfehler: \(detail)"
        case .policyDenied(let detail):
            "Abgelehnt, nur lesende Anfragen sind erlaubt: \(detail)"
        case .malformedResponse(let detail):
            "Unerwartete Antwort: \(detail)"
        case .negativeResponse(let service, let code):
            "Das Steuergerät hat Dienst \(Hex.byteString(service)) abgelehnt (Code \(Hex.byteString(code)): \(NegativeResponseCode.german(code)))."
        case .vehicleNotResponding:
            "Das Fahrzeug antwortet nicht."
        case .noVehiclePower(let voltage):
            "Der Adapter bekommt keinen Strom vom Auto (\(MeasuredValue.format(voltage)) V an der OBD-Buchse)."
        case .cancelled:
            "Abgebrochen."
        case .disconnected:
            "Die Verbindung zum Adapter ist getrennt."
        case .busy:
            "Es läuft bereits ein Vorgang."
        }
    }

    /// What the user can do about it, if anything.
    public var hint: String? {
        switch self {
        case .adapterNotFound:
            "Stecke den OBDLink EX per USB ein und prüfe mit `openobd devices`, ob er erkannt wird."
        case .portBusy:
            "Schließe Open OBD GUI oder andere Diagnoseprogramme und versuche es erneut."
        case .adapterNotResponding, .timeout:
            "Zieh den Adapter kurz ab und steck ihn wieder ein."
        case .canError, .vehicleNotResponding, .noData:
            "Prüfe, ob die Zündung an ist und der Adapter fest in der OBD-Buchse sitzt."
        case .noVehiclePower:
            "Steck den Adapter in die OBD-Buchse und schalte die Zündung ein. Steckt er schon, prüfe die Sicherung der OBD-Buchse."
        case .busUnavailable:
            "MS-CAN ist nur mit einem OBDLink EX oder MX+ erreichbar."
        case .policyDenied:
            "Open OBD GUI liest nur. Schreibende Dienste sind gesperrt."
        case .disconnected:
            "Prüfe das USB-Kabel und verbinde neu."
        default:
            nil
        }
    }
}
