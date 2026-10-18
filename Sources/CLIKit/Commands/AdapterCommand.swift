import ArgumentParser
import DiagnosticEngine

struct AdapterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "adapter",
        abstract: "Initialisiert den Adapter und zeigt Identität, Firmware, Spannung und MS-CAN-Fähigkeit.")

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    func run() async throws {
        try await CLI.execute("adapter", json: output.json) { context in
            try await Self.perform(connection.connector(context))
        }
    }

    static func perform(_ connect: Connector) async throws -> CLIResult<AdapterSummary> {
        let summary = try await connect().connect()
        return CLIResult(data: summary, human: HumanFormat.adapter(summary))
    }
}
