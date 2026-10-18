import ArgumentParser
import DiagnosticEngine
import OBDCore

struct DTCCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dtc",
        abstract: "Liest Fehlerspeicher: OBD und alle Steuergeräte, oder ein einzelnes Modul.")

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(help: "Nur dieses Steuergerät, Anfrage-ID wie 7E0.")
    var module: String?

    @Option(help: "Bus des Steuergeräts für --module: hs oder ms.")
    var bus = "hs"

    @Flag(help: "Nur die OBD-Fehlerspeicher (Dienste 03, 07, 0A).")
    var obd = false

    func run() async throws {
        try await CLI.execute("dtc", json: output.json) { context in
            try await Self.perform(connection.connector(context), module: module, bus: bus, obdOnly: obd)
        }
    }

    static func perform(_ connect: Connector, module: String?, bus: String, obdOnly: Bool) async throws -> CLIResult<[ReportDTC]> {
        let request = try module.map(ArgumentParsing.module)
        let busKind = try ArgumentParsing.bus(bus)
        let backend = try await connect()
        if let request {
            let codes = try await backend.readModuleTroubleCodes(request: request, bus: busKind)
            return CLIResult(data: codes, human: HumanFormat.codes(codes))
        }
        var codes = try await backend.readOBDTroubleCodes()
        var warnings: [String] = []
        if !obdOnly {
            for found in try await backend.discoverModules(buses: [.hsCAN, .msCAN], sweep: false) {
                do {
                    codes += try await backend.readModuleTroubleCodes(request: found.requestID, bus: found.bus)
                } catch let error as OBDError where !CLI.isFatal(error) {
                    warnings.append("\(found.requestHex): \(error.message)")
                }
            }
        }
        return CLIResult(data: codes, human: HumanFormat.codes(codes), warnings: warnings)
    }
}
