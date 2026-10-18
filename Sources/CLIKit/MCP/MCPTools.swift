import DiagnosticEngine
import Foundation
import VehicleSim

/// One MCP tool. Each maps to exactly one CLI command and returns the same `data`.
struct MCPTool: Sendable {
    let name: String
    let title: String
    let command: String
    let description: String
    let properties: [String: JSONValue]
    let required: [String]
    /// Adds the connection arguments (sim, port, route, ...).
    let reachesVehicle: Bool
    let idempotent: Bool

    var allowedArguments: Set<String> {
        Set(properties.keys).union(reachesVehicle ? Set(MCPTools.connectionProperties.keys) : [])
    }

    var definition: JSONValue {
        let all = reachesVehicle ? properties.merging(MCPTools.connectionProperties) { own, _ in own } : properties
        return .object([
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": Schema.object(all, required: required),
            "outputSchema": Schema.envelope,
            "annotations": .object([
                "title": .string(title),
                "readOnlyHint": .bool(true),
                "destructiveHint": .bool(false),
                "idempotentHint": .bool(idempotent),
                "openWorldHint": .bool(false),
            ]),
        ])
    }
}

enum MCPTools {
    static let profiles = VehicleProfile.all.map(\.id)
    static let modulePattern = "^[7][0-9A-Fa-f]{2}$"

    static let connectionProperties: [String: JSONValue] = [
        "sim": Schema.string("Simulator statt Adapter. Die Daten sind synthetisch und im Bericht als simulated markiert.", values: profiles),
        "port": Schema.string("Serieller Port des Adapters, zum Beispiel /dev/cu.usbserial-A1B2. Ohne Angabe wählt openobd den besten Kandidaten."),
        "replay": Schema.string("Mitschnitt (JSON Lines, openobd.capture/1) abspielen statt Adapter."),
        "replay_mode": Schema.string("Abspielmodus für replay.", values: ["strict", "lookup"]),
        "capture": Schema.string("Adapterverkehr in diese Datei mitschneiden. Mitschnitte echter Fahrzeuge nur unter captures/private/ ablegen."),
        "vehicle": Schema.string("Fahrzeugprofil als Namenshinweis.", values: profiles),
        "route": Schema.string("""
            Weg zum Fahrzeug. auto (Standard): über die laufende App, wenn sie mit einem echten Adapter verbunden ist, sonst direkt. \
            app: immer über die App, die mitzeigt, was gelesen wird. direct: eigene Verbindung.
            """, values: ConnectionSpec.Route.allCases.map(\.rawValue)),
    ]

    static let module = Schema.string("Steuergerät als Anfrage-ID, drei Hex-Ziffern von 700 bis 7FF, zum Beispiel 7E0 (Motor) oder 726.", pattern: modulePattern)
    static let bus = Schema.string("Bus des Steuergeräts: hs (HS-CAN) oder ms (MS-CAN).", values: ["hs", "ms"])
    static let digest = Schema.boolean("true: Kurzfassung openobd.digest/1 (Fehler, Module, Befunde) statt des vollständigen Berichts openobd.report/1.")

    static let catalog: [MCPTool] = [
        MCPTool(name: "list_devices", title: "Adapter suchen", command: "devices",
                description: "Listet serielle Geräte und bewertet, wie wahrscheinlich jedes ein OBD-Adapter ist. rank ab 80 ist sehr wahrscheinlich der OBDLink EX. Kein Fahrzeugkontakt.",
                properties: [:], required: [], reachesVehicle: false, idempotent: true),
        MCPTool(name: "app_status", title: "App prüfen", command: "app",
                description: "Prüft, ob die App Open OBD GUI läuft und Aufträge annimmt, womit sie verbunden ist (echter Adapter oder Simulator) und wohin route auto gerade führt.",
                properties: [:], required: [], reachesVehicle: false, idempotent: true),
        MCPTool(name: "adapter_status", title: "Adapter prüfen", command: "adapter",
                description: "Initialisiert den OBD-Adapter und liefert Identität, Firmware, Batteriespannung und ob MS-CAN verfügbar ist. Guter erster Schritt, um die Verbindung zu prüfen.",
                properties: [:], required: [], reachesVehicle: true, idempotent: true),
        MCPTool(name: "scan_vehicle", title: "Fahrzeug auslesen", command: "scan",
                description: """
                    Liest das Fahrzeug vollständig und nur lesend aus: Fahrzeugdaten und VIN, alle Steuergeräte, alle Fehlerspeicher mit Dringlichkeit, \
                    Bereitschaftstests, Messwerte. Liefert den Bericht openobd.report/1 oder mit digest die Kurzfassung openobd.digest/1. \
                    depth quick dauert Sekunden, standard ist der Normalfall, deep liest zusätzlich alle Adressen, alle Kennungen und Fehlerdetails. \
                    Werte mit confidence community oder unknown sind keine Tatsachen.
                    """,
                properties: [
                    "depth": Schema.string("Tiefe des Scans.", values: ScanDepth.allCases.map(\.rawValue)),
                    "digest": digest,
                    "archive": Schema.boolean("true: Bericht zusätzlich im Verlauf der App speichern. Über die App speichert die App selbst."),
                    "out": Schema.string("Bericht zusätzlich als JSON-Datei an diesem Pfad speichern."),
                    "markdown": Schema.string("Bericht zusätzlich als Markdown-Datei an diesem Pfad speichern."),
                ], required: [], reachesVehicle: true, idempotent: false),
        MCPTool(name: "list_modules", title: "Steuergeräte suchen", command: "modules",
                description: "Sucht Steuergeräte auf HS-CAN und MS-CAN und nennt Adresse, Antwortadresse, Name mit Vertrauensstufe und Antwortzeit.",
                properties: [
                    "bus": Schema.string("Bus: all, hs oder ms.", values: ["all", "hs", "ms"]),
                    "sweep": Schema.boolean("true: alle Adressen 700 bis 7F7 prüfen statt nur bekannter Ford-Adressen. Dauert länger."),
                ], required: [], reachesVehicle: true, idempotent: true),
        MCPTool(name: "read_dtcs", title: "Fehlerspeicher lesen", command: "dtc",
                description: """
                    Liest Fehlerspeicher. Ohne module: OBD-Speicher (Dienste 03, 07, 0A) und die Fehlerspeicher aller gefundenen Steuergeräte. \
                    Mit module nur dieses Steuergerät (UDS 19 02). Jeder Eintrag hat Code, Zustand, Dringlichkeit mit Begründung und, falls bekannt, \
                    einen Titel mit Vertrauensstufe.
                    """,
                properties: ["module": module, "bus": bus, "obd_only": Schema.boolean("true: nur die OBD-Fehlerspeicher.")],
                required: [], reachesVehicle: true, idempotent: true),
        MCPTool(name: "read_identification", title: "Kennungen lesen", command: "ident",
                description: "Liest die Kennungen eines Steuergeräts: Teilenummern, Software- und Hardwarestände, VIN. full liest alle Kennungen F100 bis F1FF.",
                properties: ["module": module, "bus": bus, "full": Schema.boolean("true: alle Kennungen F100 bis F1FF statt des Standardsatzes.")],
                required: ["module"], reachesVehicle: true, idempotent: true),
        MCPTool(name: "read_did", title: "Kennung lesen", command: "read-did",
                description: "Liest eine einzelne Kennung (DID, UDS-Dienst 22) roh und, wenn die Bedeutung belegt ist, dekodiert.",
                properties: ["module": module, "bus": bus, "did": Schema.string("Kennung, vier Hex-Ziffern, zum Beispiel F190 (VIN).", pattern: "^[0-9A-Fa-f]{4}$")],
                required: ["module", "did"], reachesVehicle: true, idempotent: true),
        MCPTool(name: "list_pids", title: "Messwerte auflisten", command: "pids",
                description: "Listet die OBD-Messwerte (PIDs), die das Fahrzeug meldet, mit Name und Formel. catalog zeigt den eingebauten Katalog ohne Fahrzeugkontakt.",
                properties: ["catalog": Schema.boolean("true: eingebauter Katalog statt Fahrzeugabfrage.")],
                required: [], reachesVehicle: true, idempotent: true),
        MCPTool(name: "read_live", title: "Live-Daten lesen", command: "live",
                description: """
                    Liest OBD-Messwerte wiederholt und liefert eine Liste von Messungen (openobd.live/1) mit Zeit, Wert, Einheit und Rohbytes. \
                    Endet nach count Messungen oder duration_s Sekunden. Beispiel: pids ["0C", "0D", "05"] für Drehzahl, Geschwindigkeit und Kühlmitteltemperatur.
                    """,
                properties: [
                    "pids": Schema.array("PIDs als zwei Hex-Ziffern.", items: Schema.string("PID", pattern: "^[0-9A-Fa-f]{2}$")),
                    "interval_ms": Schema.integer("Abfrageintervall in Millisekunden, Standard 500.", minimum: 20, maximum: 10_000),
                    "count": Schema.integer("Höchstzahl an Messungen, Standard 20.", minimum: 1, maximum: MCPLimits.liveCount),
                    "duration_s": Schema.number("Höchstdauer in Sekunden, Standard 10.", minimum: 0.1, maximum: MCPLimits.liveSeconds),
                ], required: ["pids"], reachesVehicle: true, idempotent: false),
        MCPTool(name: "raw_request", title: "Rohanfrage senden", command: "raw",
                description: """
                    Expertenanfrage mit Hex-Nutzdaten an ein Steuergerät oder funktional an 7DF. Nur lesende Dienste sind erlaubt \
                    (01 02 03 06 07 09 0A 22, 19 mit 01 02 03 04 06 0A, 3E 00/80, 10 01). Alles andere wird vor dem Senden abgelehnt (POLICY_DENIED).
                    """,
                properties: [
                    "payload": Schema.string("Nutzdaten als Hex, zum Beispiel \"22 F1 90\"."),
                    "module": module, "bus": bus,
                    "functional": Schema.boolean("true: funktionale OBD-Anfrage an 7DF statt an ein Modul."),
                    "timeout_ms": Schema.integer("Wartezeit auf Antworten in Millisekunden, Standard 500.", minimum: 50, maximum: 10_000),
                ], required: ["payload"], reachesVehicle: true, idempotent: false),
        MCPTool(name: "explain_dtc", title: "Fehlercode erklären", command: "explain dtc",
                description: """
                    Erklärt einen Fehlercode aus der Wissensbasis, ohne Fahrzeug: System, Herkunft, Titel mit Quelle und Vertrauensstufe, \
                    Fehlerart (FTB), Ursachen. Herstellerspezifische Codes ohne Beleg werden nicht geraten.
                    """,
                properties: ["code": Schema.string("Fehlercode, optional mit Fehlerart, zum Beispiel P0401 oder U0100-87.")],
                required: ["code"], reachesVehicle: false, idempotent: true),
        MCPTool(name: "explain_pid", title: "PID erklären", command: "explain pid",
                description: "Erklärt eine OBD-PID mit Name, Kategorie, Formel und Normquelle. Ohne Fahrzeug.",
                properties: ["pid": Schema.string("PID als zwei Hex-Ziffern, zum Beispiel 0C.", pattern: "^[0-9A-Fa-f]{2}$")],
                required: ["pid"], reachesVehicle: false, idempotent: true),
        MCPTool(name: "explain_nrc", title: "Antwortcode erklären", command: "explain nrc",
                description: "Erklärt einen UDS-Negativantwortcode (NRC) nach ISO 14229, zum Beispiel 31 (Kennung existiert nicht). Ohne Fahrzeug.",
                properties: ["code": Schema.string("Antwortcode als zwei Hex-Ziffern.", pattern: "^[0-9A-Fa-f]{2}$")],
                required: ["code"], reachesVehicle: false, idempotent: true),
        MCPTool(name: "explain_did", title: "Kennung erklären", command: "explain did",
                description: "Erklärt eine Kennung (DID) aus der Wissensbasis mit Format, Quelle und Vertrauensstufe. Ohne Fahrzeug.",
                properties: ["did": Schema.string("Kennung, vier Hex-Ziffern, zum Beispiel F111.", pattern: "^[0-9A-Fa-f]{4}$")],
                required: ["did"], reachesVehicle: false, idempotent: true),
        MCPTool(name: "explain_module", title: "Moduladresse erklären", command: "explain module",
                description: "Erklärt eine Ford-Moduladresse: Kürzel, Name, Busse, Quelle und Vertrauensstufe. Ohne Fahrzeug.",
                properties: ["module": module], required: ["module"], reachesVehicle: false, idempotent: true),
        MCPTool(name: "last_report", title: "Letzten Bericht holen", command: "report last",
                description: """
                    Liefert den neuesten Bericht: zuerst den letzten Scan dieses Servers, dann den Bericht, den die App gerade zeigt, \
                    dann den neuesten aus dem Verlauf. source schränkt die Quelle ein.
                    """,
                properties: ["source": Schema.string("Quelle.", values: ["auto", "session", "app", "archive"]), "digest": digest],
                required: [], reachesVehicle: false, idempotent: true),
        MCPTool(name: "read_report", title: "Bericht öffnen", command: "report show",
                description: "Liest einen gespeicherten Bericht (openobd.report/1) aus einer Datei, zum Beispiel einen Pfad aus list_reports.",
                properties: ["path": Schema.string("Pfad zur Berichtsdatei."), "digest": digest], required: ["path"], reachesVehicle: false, idempotent: true),
        MCPTool(name: "list_reports", title: "Verlauf auflisten", command: "report list",
                description: "Listet die Berichte im Verlauf der App, neueste zuerst, mit Pfad, Fahrzeug, Datum und Fehlerzahl.",
                properties: ["limit": Schema.integer("Höchstens so viele Berichte, Standard 20, 0 bedeutet alle.", minimum: 0, maximum: 10_000)],
                required: [], reachesVehicle: false, idempotent: true),
        MCPTool(name: "capabilities", title: "Fähigkeiten", command: "capabilities",
                description: "Maschinenlesbare Übersicht aller Befehle, Werkzeuge, Schemata, Exitcodes, Fehlercodes, Wege und Vertrauensstufen.",
                properties: [:], required: [], reachesVehicle: false, idempotent: true),
    ]

    static func tool(named name: String) -> MCPTool? {
        catalog.first { $0.name == name }
    }
}

enum MCPLimits {
    static let liveCount = 2_000
    static let liveSeconds = 120.0
}
