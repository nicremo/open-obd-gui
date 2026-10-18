import ArgumentParser
import DiagnosticEngine
import Foundation

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Startet den MCP-Server über stdio (JSON-RPC 2.0) mit allen Befehlen als Werkzeuge.",
        discussion: """
        Einbindung: openobd mcp als stdio-Server im MCP-Client eintragen.
        stdout gehört dem Protokoll, Meldungen gehen nach stderr. Ohne Hardware: openobd mcp --sim mondeo-mk4.
        """)

    @Option(help: "Simulator als Standard für alle Werkzeuge: mondeo-mk4 oder focus-mk4.")
    var sim: String?

    @Option(help: "Serieller Port als Standard für alle Werkzeuge.")
    var port: String?

    @Option(help: "Fahrzeugprofil als Namenshinweis.")
    var vehicle: String?

    @Option(help: "Standardweg: auto (App, wenn sie mit echtem Adapter verbunden ist), app oder direct.")
    var route = "auto"

    @Option(help: ArgumentHelp("Socket der App-Brücke (für Tests).", visibility: .private))
    var bridgeSocket: String?

    func run() async throws {
        guard ConnectionSpec.Route(rawValue: route) != nil else {
            throw ValidationError("Unbekannter Weg \(route). Erlaubt: auto, app, direct")
        }
        let server = MCPServer(defaults: MCPDefaults(sim: sim, port: port, vehicle: vehicle, route: route, bridgeSocket: bridgeSocket),
                               write: { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) })
        let stderrOnly = OutputSink(out: OutputSink.standard.err, err: OutputSink.standard.err)
        await Output.$sink.withValue(stderrOnly) {
            await server.run(lines: FileHandle.standardInput.bytes.lines)
        }
    }
}
