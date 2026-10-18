import ArgumentParser
import OBDCore

struct PIDListing: Encodable, Sendable {
    let ecu: String?
    let pid: String
    let name: String
    let category: String
    let formula: String
}

struct PIDsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pids",
        abstract: "Zeigt die OBD-Messwerte, die das Fahrzeug unterstützt, oder den eingebauten Katalog.")

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Flag(help: "Nur den eingebauten Katalog zeigen, ohne Fahrzeug.")
    var catalog = false

    func run() async throws {
        try await CLI.execute("pids", json: output.json) { context in
            try await Self.perform(connection.connector(context), catalog: catalog)
        }
    }

    /// With `catalog` the vehicle is never contacted.
    static func perform(_ connect: Connector, catalog: Bool) async throws -> CLIResult<[PIDListing]> {
        var listing: [PIDListing] = []
        if catalog {
            listing = J1979.allDefinitions.map {
                PIDListing(ecu: nil, pid: Hex.byteString($0.pid), name: $0.name, category: $0.category.german, formula: $0.formula)
            }
        } else {
            let supported = try await connect().supportedPIDs()
            for ecu in supported.keys.sorted() {
                for pid in (supported[ecu] ?? []).sorted() {
                    let definition = J1979.definition(pid)
                    listing.append(PIDListing(ecu: Hex.canID(ecu, extended: false), pid: Hex.byteString(pid),
                                              name: definition?.name ?? "unbekannt (Rohwert)",
                                              category: definition?.category.german ?? "unbekannt",
                                              formula: definition?.formula ?? "keine Definition"))
                }
            }
        }
        var table = TextTable(headers: ["Steuergerät", "PID", "Kategorie", "Name"])
        listing.forEach { table.add([$0.ecu ?? "Katalog", $0.pid, $0.category, $0.name]) }
        return CLIResult(data: listing, human: table.render())
    }
}
