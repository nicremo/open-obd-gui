import Foundation

/// Failure type byte categories (SAE J2012-DA). The high nibble is the category, known values have a detail text.
public enum FailureType {
    public struct Description: Sendable, Equatable {
        public let category: String
        public let detail: String?

        public init(category: String, detail: String?) {
            self.category = category
            self.detail = detail
        }
    }

    public static func describe(_ byte: UInt8) -> Description {
        Description(category: category(byte >> 4), detail: details[byte])
    }

    static func category(_ nibble: UInt8) -> String {
        switch nibble {
        case 0x0: "Allgemeine Fehlerart"
        case 0x1: "Elektrischer Fehler"
        case 0x2: "Signalfehler"
        case 0x3: "Frequenz- oder PWM-Fehler"
        case 0x4: "Interner Fehler im Steuergerät"
        case 0x5: "Programmierung oder Konfiguration"
        case 0x6: "Algorithmusbasierter Fehler"
        case 0x7: "Mechanischer Fehler"
        case 0x8: "Busnachricht oder Kommunikation"
        case 0x9: "Bauteilfehler"
        case 0xF: "herstellerspezifisch"
        default: "reserviert"
        }
    }

    static let details: [UInt8: String] = [
        0x00: "keine Unterart angegeben",
        0x01: "allgemeiner elektrischer Fehler",
        0x02: "allgemeiner Signalfehler",
        0x03: "Frequenz- oder PWM-Fehler",
        0x04: "interner Systemfehler",
        0x05: "Programmierfehler",
        0x06: "algorithmusbasierter Fehler",
        0x07: "mechanischer Fehler",
        0x08: "Busnachricht fehlerhaft",
        0x09: "Bauteilfehler",
        0x11: "Kurzschluss nach Masse",
        0x12: "Kurzschluss nach Plus (Batterie)",
        0x13: "Stromkreis unterbrochen",
        0x14: "Kurzschluss nach Masse oder Unterbrechung",
        0x15: "Kurzschluss nach Plus oder Unterbrechung",
        0x16: "Spannung unter Schwellenwert",
        0x17: "Spannung über Schwellenwert",
        0x18: "Strom unter Schwellenwert",
        0x19: "Strom über Schwellenwert",
        0x1A: "Widerstand unter Schwellenwert",
        0x1B: "Widerstand über Schwellenwert",
        0x1C: "Spannung außerhalb des Bereichs",
        0x1D: "Strom außerhalb des Bereichs",
        0x1E: "Widerstand außerhalb des Bereichs",
        0x1F: "Stromkreis sporadisch unterbrochen",
        0x21: "Signalamplitude unter Minimum",
        0x22: "Signalamplitude über Maximum",
        0x23: "Signal dauerhaft niedrig",
        0x24: "Signal dauerhaft hoch",
        0x25: "Signalform fehlerhaft",
        0x26: "Signal ändert sich zu langsam",
        0x27: "Signal ändert sich zu schnell",
        0x28: "Signal-Nullpunkt außerhalb des Bereichs",
        0x29: "Signal ungültig",
        0x2A: "Signal hängt im Bereich fest",
        0x2B: "Signal mit anderem Signal gekoppelt",
        0x2F: "Signal unregelmäßig",
        0x31: "kein Signal",
        0x32: "Low-Zeit des Signals zu kurz",
        0x33: "Low-Zeit des Signals zu lang",
        0x34: "High-Zeit des Signals zu kurz",
        0x35: "High-Zeit des Signals zu lang",
        0x36: "Signalfrequenz zu niedrig",
        0x37: "Signalfrequenz zu hoch",
        0x38: "Signalfrequenz falsch",
        0x39: "zu wenige Impulse",
        0x3A: "zu viele Impulse",
        0x41: "allgemeiner Prüfsummenfehler",
        0x42: "allgemeiner Speicherfehler",
        0x43: "spezieller Speicherfehler",
        0x44: "Datenspeicherfehler",
        0x45: "Programmspeicherfehler",
        0x46: "Kalibrier- oder Parameterspeicherfehler",
        0x47: "Watchdog- oder Sicherheitsrechnerfehler",
        0x48: "Überwachungssoftware fehlerhaft",
        0x49: "interner elektronischer Fehler",
        0x4A: "falsches Bauteil eingebaut",
        0x4B: "Übertemperatur",
        0x51: "nicht programmiert",
        0x52: "nicht aktiviert",
        0x53: "deaktiviert",
        0x54: "Kalibrierung fehlt",
        0x55: "nicht konfiguriert",
        0x56: "ungültige oder unpassende Konfiguration",
        0x57: "ungültige oder unpassende Softwarekomponente",
        0x61: "Signalberechnung fehlerhaft",
        0x62: "Signalvergleich fehlerhaft",
        0x63: "Schutzzeit für Stromkreis oder Bauteil abgelaufen",
        0x64: "Signal nicht plausibel",
        0x65: "Signal mit zu wenigen Wechseln oder Ereignissen",
        0x66: "Signal mit zu vielen Wechseln oder Ereignissen",
        0x67: "Signal nach Ereignis falsch",
        0x68: "Ereignisinformation",
        0x71: "Stellglied blockiert",
        0x72: "Stellglied klemmt offen",
        0x73: "Stellglied klemmt geschlossen",
        0x74: "Stellglied rutscht durch",
        0x75: "Notlaufposition nicht erreichbar",
        0x76: "falsche Einbaulage",
        0x77: "Sollposition nicht erreichbar",
        0x78: "Ausrichtung oder Einstellung falsch",
        0x79: "mechanische Verbindung fehlerhaft",
        0x7A: "Flüssigkeitsleck oder Dichtung defekt",
        0x7B: "Flüssigkeitsstand zu niedrig",
        0x81: "ungültige serielle Daten empfangen",
        0x82: "Botschaftszähler falsch oder nicht aktualisiert",
        0x83: "Prüfwert der Botschaft falsch",
        0x84: "Signal unter zulässigem Bereich",
        0x85: "Signal über zulässigem Bereich",
        0x86: "Signal ungültig",
        0x87: "Nachricht fehlt",
        0x88: "Bus abgeschaltet (Bus Off)",
        0x8F: "unregelmäßig",
        0x91: "Parameterabweichung",
        0x92: "Leistung oder Funktion fehlerhaft",
        0x93: "keine Funktion",
        0x94: "unerwartete Funktion",
        0x95: "falsch montiert",
        0x96: "interner Bauteilfehler",
        0x97: "Funktion behindert oder blockiert",
        0x98: "Bauteil oder System überhitzt",
    ]
}
