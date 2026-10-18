import ArgumentParser
import DiagnosticEngine
import OBDCore

struct ModuleListing: Codable, Sendable, Equatable {
    let bus: BusKind
    let request: String
    let response: String
    let acronym: String?
    let name: String
    let nameConfidence: Confidence
    let responseMs: Int
    let probe: String
}

struct ModulesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "modules",
        abstract: "Sucht Steuergeräte auf HS-CAN und MS-CAN.")

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(help: "Bus: all, hs oder ms.")
    var bus = "all"

    @Flag(help: "Alle Adressen 700 bis 7F7 prüfen statt nur bekannter Ford-Adressen (dauert länger).")
    var sweep = false

    func run() async throws {
        try await CLI.execute("modules", json: output.json) { context in
            try await Self.perform(connection.connector(context), bus: bus, sweep: sweep)
        }
    }

    static func perform(_ connect: Connector, bus: String, sweep: Bool) async throws -> CLIResult<[ModuleListing]> {
        let buses: [BusKind] = bus.lowercased() == "all" ? [.hsCAN, .msCAN] : [try ArgumentParsing.bus(bus)]
        let backend = try await connect()
        let modules = try await backend.discoverModules(buses: buses, sweep: sweep)
        let listing = modules.map { module in
            let catalog = backend.knowledge.module(request: module.requestID)
            return ModuleListing(bus: module.bus, request: module.requestHex, response: module.responseHex,
                                 acronym: catalog?.acronym, name: catalog?.nameDE ?? "Unbekanntes Steuergerät \(module.requestHex)",
                                 nameConfidence: catalog?.confidence ?? .unknown, responseMs: module.responseMilliseconds, probe: module.probe)
        }
        var table = TextTable(headers: ["Bus", "Adresse", "Antwort", "Name", "Zeit"])
        for item in listing {
            table.add([item.bus.shortName, item.request, item.response, "\(item.acronym.map { "\($0) " } ?? "")\(item.name)", "\(item.responseMs) ms"])
        }
        return CLIResult(data: listing, human: listing.isEmpty ? "Keine Steuergeräte gefunden." : table.render())
    }
}
