import Foundation

/// UDS negative response codes (ISO 14229-1, Annex A) with German explanations.
public enum NegativeResponseCode {
    public static func name(_ code: UInt8) -> String {
        table[code]?.name ?? (isReserved(code) ? "reservedByExtendedDataLinkSecurityDocument" : "unknown")
    }

    public static func german(_ code: UInt8) -> String {
        table[code]?.german ?? (isReserved(code) ? "reserviert" : "unbekannter Code")
    }

    private static func isReserved(_ code: UInt8) -> Bool { (0x38...0x4F).contains(code) }

    private struct Entry: Sendable {
        let name: String
        let german: String
    }

    private static let table: [UInt8: Entry] = [
        0x10: Entry(name: "generalReject", german: "allgemein abgelehnt"),
        0x11: Entry(name: "serviceNotSupported", german: "Dienst nicht unterstützt"),
        0x12: Entry(name: "subFunctionNotSupported", german: "Unterfunktion nicht unterstützt"),
        0x13: Entry(name: "incorrectMessageLengthOrInvalidFormat", german: "falsche Länge oder ungültiges Format"),
        0x14: Entry(name: "responseTooLong", german: "Antwort zu lang"),
        0x21: Entry(name: "busyRepeatRequest", german: "beschäftigt, später erneut anfragen"),
        0x22: Entry(name: "conditionsNotCorrect", german: "Bedingungen nicht erfüllt"),
        0x24: Entry(name: "requestSequenceError", german: "falsche Reihenfolge"),
        0x25: Entry(name: "noResponseFromSubnetComponent", german: "keine Antwort von einer Teilnetz-Komponente"),
        0x26: Entry(name: "failurePreventsExecutionOfRequestedAction", german: "ein Fehler verhindert die Ausführung"),
        0x31: Entry(name: "requestOutOfRange", german: "Kennung oder Wert außerhalb des Bereichs (nicht vorhanden)"),
        0x33: Entry(name: "securityAccessDenied", german: "Sicherheitszugang verweigert"),
        0x35: Entry(name: "invalidKey", german: "ungültiger Schlüssel"),
        0x36: Entry(name: "exceedNumberOfAttempts", german: "zu viele Versuche"),
        0x37: Entry(name: "requiredTimeDelayNotExpired", german: "Wartezeit noch nicht abgelaufen"),
        0x70: Entry(name: "uploadDownloadNotAccepted", german: "Upload oder Download nicht akzeptiert"),
        0x71: Entry(name: "transferDataSuspended", german: "Datenübertragung unterbrochen"),
        0x72: Entry(name: "generalProgrammingFailure", german: "allgemeiner Programmierfehler"),
        0x73: Entry(name: "wrongBlockSequenceCounter", german: "falscher Blockzähler"),
        0x78: Entry(name: "requestCorrectlyReceivedResponsePending", german: "Anfrage erhalten, Antwort folgt"),
        0x7E: Entry(name: "subFunctionNotSupportedInActiveSession", german: "Unterfunktion in dieser Sitzung nicht unterstützt"),
        0x7F: Entry(name: "serviceNotSupportedInActiveSession", german: "Dienst in dieser Sitzung nicht unterstützt"),
        0x81: Entry(name: "rpmTooHigh", german: "Drehzahl zu hoch"),
        0x82: Entry(name: "rpmTooLow", german: "Drehzahl zu niedrig"),
        0x83: Entry(name: "engineIsRunning", german: "Motor läuft"),
        0x84: Entry(name: "engineIsNotRunning", german: "Motor läuft nicht"),
        0x85: Entry(name: "engineRunTimeTooLow", german: "Motorlaufzeit zu kurz"),
        0x86: Entry(name: "temperatureTooHigh", german: "Temperatur zu hoch"),
        0x87: Entry(name: "temperatureTooLow", german: "Temperatur zu niedrig"),
        0x88: Entry(name: "vehicleSpeedTooHigh", german: "Geschwindigkeit zu hoch"),
        0x89: Entry(name: "vehicleSpeedTooLow", german: "Geschwindigkeit zu niedrig"),
        0x8A: Entry(name: "throttlePedalTooHigh", german: "Fahrpedal zu weit betätigt"),
        0x8B: Entry(name: "throttlePedalTooLow", german: "Fahrpedal zu wenig betätigt"),
        0x8C: Entry(name: "transmissionRangeNotInNeutral", german: "Getriebe nicht in Neutral"),
        0x8D: Entry(name: "transmissionRangeNotInGear", german: "kein Gang eingelegt"),
        0x8F: Entry(name: "brakeSwitchNotClosed", german: "Bremse nicht betätigt"),
        0x90: Entry(name: "shifterLeverNotInPark", german: "Wählhebel nicht in P"),
        0x91: Entry(name: "torqueConverterClutchLocked", german: "Wandlerkupplung geschlossen"),
        0x92: Entry(name: "voltageTooHigh", german: "Spannung zu hoch"),
        0x93: Entry(name: "voltageTooLow", german: "Spannung zu niedrig"),
    ]
}
