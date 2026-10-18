import ArgumentParser
import DiagnosticEngine
import OBDCore
import VehicleSim

struct CapabilityOption: Encodable, Sendable {
    let name: String
    let summary: String
}

struct CapabilityCommand: Encodable, Sendable {
    let name: String
    let usage: String
    let summary: String
    let output: String
    let needsVehicle: Bool
}

struct CapabilityExit: Encodable, Sendable {
    let code: Int32
    let meaning: String
}

struct Capabilities: Encodable, Sendable {
    let tool: String
    let version: String
    let readOnly: Bool
    let allowedVehicleServices: [String]
    let schemas: [String: String]
    let connectionOptions: [CapabilityOption]
    let commands: [CapabilityCommand]
    let exitCodes: [CapabilityExit]
    let errorCodes: [String]
    let simulatorProfiles: [String]
    let confidenceLevels: [String: String]
    let routes: [String: String]
    let mcpTools: [CapabilityTool]
    let notes: [String]
}

struct CapabilityTool: Encodable, Sendable {
    let name: String
    let command: String
    let summary: String
}

struct CapabilitiesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capabilities",
        abstract: "Maschinenlesbare Beschreibung aller Befehle, Optionen, Schemata und Exitcodes.")

    @OptionGroup var output: OutputOptions

    func run() async throws {
        try await CLI.execute("capabilities", json: output.json) { _ in Self.perform() }
    }

    static func perform() -> CLIResult<Capabilities> {
        let data = capabilities
        var table = TextTable(headers: ["Befehl", "Zweck"])
        data.commands.forEach { table.add([$0.name, $0.summary]) }
        return CLIResult(data: data, human: table.render())
    }

    static var capabilities: Capabilities {
        let errors: [OBDError] = [
            .adapterNotFound, .portBusy(""), .portOpenFailed(path: "", errno: 0), .io(""), .timeout(""), .adapterNotResponding,
            .adapterRejected(command: "", reply: ""), .busUnavailable(""), .noData, .canError, .busBusy, .bufferFull, .adapterError(""),
            .policyDenied(""), .malformedResponse(""), .negativeResponse(service: 0, code: 0), .vehicleNotResponding, .cancelled, .disconnected, .busy,
        ]
        return Capabilities(
            tool: OpenOBD.toolName,
            version: OpenOBD.version,
            readOnly: true,
            allowedVehicleServices: ["01", "02", "03", "06", "07", "09", "0A", "22", "19 01/02/03/04/06/0A", "3E 00/80", "10 01"],
            schemas: ["output": "openobd.cli/1", "report": VehicleReport.schemaName, "digest": "openobd.digest/1", "live": "openobd.live/1",
                      "capture": "openobd.capture/1"],
            connectionOptions: [
                CapabilityOption(name: "--port <pfad>", summary: "Serieller Port, sonst automatische Wahl"),
                CapabilityOption(name: "--sim <profil>", summary: "Simulator: \(VehicleProfile.all.map(\.id).joined(separator: ", "))"),
                CapabilityOption(name: "--replay <datei>", summary: "Mitschnitt abspielen"),
                CapabilityOption(name: "--replay-mode strict|lookup", summary: "Abspielmodus"),
                CapabilityOption(name: "--capture <datei>", summary: "Adapterverkehr mitschneiden"),
                CapabilityOption(name: "--vehicle <profil>", summary: "Fahrzeugprofil als Namenshinweis"),
                CapabilityOption(name: "--verbose", summary: "Adapterverkehr auf stderr"),
                CapabilityOption(name: "--via-app", summary: "In der laufenden App Open OBD GUI ausführen, die App zeigt mit"),
                CapabilityOption(name: "--route direct|app|auto", summary: "Weg zum Fahrzeug, Standard direct"),
                CapabilityOption(name: "--json", summary: "Ein JSON-Objekt auf stdout"),
            ],
            commands: [
                CapabilityCommand(name: "devices", usage: "openobd devices [--json]", summary: "Serielle Geräte und Adapterkandidaten", output: "[SerialDeviceCandidate]", needsVehicle: false),
                CapabilityCommand(name: "adapter", usage: "openobd adapter [--port P | --sim ID] [--json]", summary: "Adapteridentität, Firmware, Spannung, MS-CAN", output: "AdapterSummary", needsVehicle: false),
                CapabilityCommand(name: "scan", usage: "openobd scan [--depth quick|standard|deep] [--out datei.json] [--markdown datei.md] [--archive] [--digest] [--json]", summary: "Vollständiges Auslesen mit Bericht", output: "\(VehicleReport.schemaName) oder openobd.digest/1", needsVehicle: true),
                CapabilityCommand(name: "dtc", usage: "openobd dtc [--module 7E0 --bus hs|ms] [--obd] [--json]", summary: "Fehlerspeicher", output: "[ReportDTC]", needsVehicle: true),
                CapabilityCommand(name: "modules", usage: "openobd modules [--bus all|hs|ms] [--sweep] [--json]", summary: "Steuergeräte suchen", output: "[ModuleListing]", needsVehicle: true),
                CapabilityCommand(name: "ident", usage: "openobd ident --module 726 --bus ms [--full] [--json]", summary: "Kennungen eines Steuergeräts", output: "IdentOutput", needsVehicle: true),
                CapabilityCommand(name: "read-did", usage: "openobd read-did --module 726 --bus ms --did F190 [--json]", summary: "Eine Kennung lesen", output: "DIDReading", needsVehicle: true),
                CapabilityCommand(name: "pids", usage: "openobd pids [--catalog] [--json]", summary: "Unterstützte OBD-Messwerte oder Katalog", output: "[PIDListing]", needsVehicle: true),
                CapabilityCommand(name: "live", usage: "openobd live 0C 0D 05 [--interval 500] [--duration 10] [--count 0] [--format table|csv|ndjson] [--json]", summary: "Live-Messwerte", output: "NDJSON openobd.live/1", needsVehicle: true),
                CapabilityCommand(name: "raw", usage: "openobd raw --module 7E0 [--bus hs] \"22 F1 90\" [--json]", summary: "Expertenanfrage, nur lesende Dienste", output: "RawOutput", needsVehicle: true),
                CapabilityCommand(name: "explain dtc", usage: "openobd explain dtc P0401-00 [--json]", summary: "Fehlercode erklären", output: "DTCExplanationOutput", needsVehicle: false),
                CapabilityCommand(name: "explain pid", usage: "openobd explain pid 0C [--json]", summary: "PID mit Formel", output: "PIDListing", needsVehicle: false),
                CapabilityCommand(name: "explain nrc", usage: "openobd explain nrc 31 [--json]", summary: "Negativantwortcode", output: "NRCExplanation", needsVehicle: false),
                CapabilityCommand(name: "explain did", usage: "openobd explain did F190 [--json]", summary: "Kennung", output: "DIDExplanation", needsVehicle: false),
                CapabilityCommand(name: "explain module", usage: "openobd explain module 726 [--json]", summary: "Ford-Moduladresse", output: "ModuleExplanation", needsVehicle: false),
                CapabilityCommand(name: "report show", usage: "openobd report show datei.json [--markdown] [--digest] [--json]", summary: "Gespeicherten Bericht anzeigen", output: VehicleReport.schemaName, needsVehicle: false),
                CapabilityCommand(name: "report list", usage: "openobd report list [--limit N] [--json]", summary: "Berichte im Verlauf der App", output: "[ReportListing]", needsVehicle: false),
                CapabilityCommand(name: "report last", usage: "openobd report last [--source auto|app|archive] [--digest] [--json]", summary: "Neuester Bericht aus App oder Verlauf", output: "LastReportOutput", needsVehicle: false),
                CapabilityCommand(name: "app", usage: "openobd app [--json]", summary: "Läuft die App, nimmt sie Aufträge an, wohin geht --route auto", output: "AppStatus", needsVehicle: false),
                CapabilityCommand(name: "mcp", usage: "openobd mcp [--sim ID] [--route auto|app|direct]", summary: "MCP-Server über stdio mit allen Befehlen als Werkzeuge", output: "JSON-RPC 2.0", needsVehicle: false),
                CapabilityCommand(name: "capabilities", usage: "openobd capabilities [--json]", summary: "Diese Beschreibung", output: "Capabilities", needsVehicle: false),
            ],
            exitCodes: [
                CapabilityExit(code: 0, meaning: "ok"),
                CapabilityExit(code: 1, meaning: "interner Fehler oder unerwartete Antwort"),
                CapabilityExit(code: 2, meaning: "Bedienfehler oder Datei nicht lesbar"),
                CapabilityExit(code: 3, meaning: "kein Adapter gefunden"),
                CapabilityExit(code: 4, meaning: "Adapter- oder Verbindungsfehler"),
                CapabilityExit(code: 5, meaning: "Fahrzeug antwortet nicht oder lehnt ab"),
                CapabilityExit(code: 6, meaning: "von der Nur-Lese-Richtlinie abgelehnt"),
                CapabilityExit(code: 7, meaning: "Adapter von anderem Programm belegt oder App beschäftigt"),
                CapabilityExit(code: 8, meaning: "App nicht erreichbar (--via-app)"),
                CapabilityExit(code: 64, meaning: "ungültige Argumente"),
                CapabilityExit(code: 130, meaning: "abgebrochen"),
            ],
            errorCodes: errors.map(\.code) + ["USAGE_ERROR", "FILE_ERROR", "NO_REPORT", "APP_NOT_RUNNING", "APP_BUSY", "BRIDGE_DISCONNECTED",
                                               "BRIDGE_PROTOCOL", "INTERNAL_ERROR"],
            simulatorProfiles: VehicleProfile.all.map(\.id),
            confidenceLevels: Dictionary(uniqueKeysWithValues: Confidence.allCases.map { ($0.rawValue, $0.german) }),
            routes: [
                "direct": "eigene Verbindung: Adapter, Simulator oder Mitschnitt",
                "app": "Sitzung der laufenden App, die App zeigt Fortschritt und Verkehr",
                "auto": "App, wenn sie mit einem echten Adapter verbunden ist, sonst direkt",
            ],
            mcpTools: MCPTools.catalog.map { CapabilityTool(name: $0.name, command: $0.command, summary: $0.title) },
            notes: [
                "Nur lesend: schreibende Dienste werden vor dem Senden abgelehnt.",
                "Werte mit Vertrauensstufe community oder unknown sind keine Tatsachen.",
                "Ohne Fahrzeug: --sim mondeo-mk4 oder --sim focus-mk4.",
                "Mit --capture entsteht ein Mitschnitt, der sich mit --replay wieder abspielen lässt.",
                "Nur ein Programm kann den Adapter gleichzeitig nutzen. Läuft die App, über --via-app lesen.",
            ])
    }
}
