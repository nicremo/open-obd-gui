import ArgumentParser
import DiagnosticEngine
import OBDCore

struct IdentOutput: Encodable, Sendable {
    let module: String
    let bus: BusKind
    let readings: [DIDReading]
    let unsupportedCount: Int
    let issues: [String]
}

struct IdentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ident",
        abstract: "Liest die Kennungen eines Steuergeräts (Teilenummern, Software, VIN).")

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(help: "Steuergerät, Anfrage-ID wie 726.")
    var module: String

    @Option(help: "Bus: hs oder ms.")
    var bus = "hs"

    @Flag(help: "Alle Kennungen F100 bis F1FF lesen statt des Standardsatzes.")
    var full = false

    func run() async throws {
        try await CLI.execute("ident", json: output.json) { context in
            try await Self.perform(connection.connector(context), module: module, bus: bus, full: full)
        }
    }

    static func perform(_ connect: Connector, module: String, bus: String, full: Bool) async throws -> CLIResult<IdentOutput> {
        let request = try ArgumentParsing.module(module)
        let busKind = try ArgumentParsing.bus(bus)
        let result = try await connect().identify(request: request, bus: busKind, full: full)
        let data = IdentOutput(module: module.uppercased(), bus: busKind, readings: result.readings,
                               unsupportedCount: result.unsupportedCount, issues: result.issues)
        return CLIResult(data: data, human: HumanFormat.readings(result.readings), warnings: result.issues)
    }
}
