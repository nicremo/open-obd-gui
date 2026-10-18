import ArgumentParser
import DiagnosticEngine

struct ReadDIDCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read-did",
        abstract: "Liest eine einzelne Kennung (DID) eines Steuergeräts, roh und dekodiert.")

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(help: "Steuergerät, Anfrage-ID wie 726.")
    var module: String

    @Option(help: "Bus: hs oder ms.")
    var bus = "hs"

    @Option(help: "DID, vier Hex-Ziffern wie F190.")
    var did: String

    func run() async throws {
        try await CLI.execute("read-did", json: output.json) { context in
            try await Self.perform(connection.connector(context), module: module, bus: bus, did: did)
        }
    }

    static func perform(_ connect: Connector, module: String, bus: String, did: String) async throws -> CLIResult<DIDReading> {
        let request = try ArgumentParsing.module(module)
        let busKind = try ArgumentParsing.bus(bus)
        let identifier = try ArgumentParsing.did(did)
        let reading = try await connect().readDID(identifier, request: request, bus: busKind)
        return CLIResult(data: reading, human: HumanFormat.readings([reading]))
    }
}
