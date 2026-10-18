import ArgumentParser
import DiagnosticEngine

public struct OpenOBDCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "openobd",
        abstract: "Liest Ford-Fahrzeuge über einen OBDLink-Adapter aus. Nur lesend.",
        discussion: """
        Jeder Befehl gibt mit --json genau ein JSON-Objekt aus (Schema openobd.cli/1), live mit --json eine Zeile pro Messwert.
        Ohne Adapter: --sim mondeo-mk4 oder --sim focus-mk4. Läuft die App: --via-app. Übersicht für Agenten: openobd capabilities --json
        MCP-Server für Agenten: openobd mcp
        """,
        version: OpenOBD.version,
        subcommands: [
            DevicesCommand.self, AdapterCommand.self, ScanCommand.self, DTCCommand.self, ModulesCommand.self, IdentCommand.self,
            ReadDIDCommand.self, PIDsCommand.self, LiveCommand.self, RawCommand.self, ExplainCommand.self, ReportCommand.self,
            AppCommand.self, MCPCommand.self, CapabilitiesCommand.self,
        ])

    public init() {}

    /// Entry point of the executable. In top level code `main()` resolves to the synchronous variant,
    /// so this mirrors the documented async path explicitly: parse, then await `run()`.
    public static func runAsRoot(_ arguments: [String]? = nil) async {
        do {
            var command = try parseAsRoot(normalized(arguments ?? Array(CommandLine.arguments.dropFirst())))
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }

    /// `openobd --via-app scan` reads naturally, but the flag belongs to the subcommand: move it behind the command words.
    static func normalized(_ arguments: [String]) -> [String] {
        guard let index = arguments.firstIndex(of: "--via-app"), index < (arguments.firstIndex { !$0.hasPrefix("-") } ?? 0) else {
            return arguments
        }
        var rest = arguments
        rest.remove(at: index)
        return rest + ["--via-app"]
    }
}
