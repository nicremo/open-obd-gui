import ArgumentParser
import DiagnosticEngine
import Foundation

extension ScanDepth: ExpressibleByArgument {}

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Liest das Fahrzeug vollständig aus und erstellt einen Bericht.",
        discussion: "Tiefen: quick (OBD und HS-CAN), standard (zusätzlich MS-CAN, Kennungen, Freeze Frame, Messwerte), deep (zusätzlich alle Adressen, alle Kennungen, Fehlerdetails, Konfigurationsblöcke).")

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(help: "Tiefe: quick, standard oder deep.")
    var depth: ScanDepth = .standard

    @Option(help: "Bericht zusätzlich als JSON-Datei speichern.")
    var out: String?

    @Option(help: "Bericht zusätzlich als Markdown-Datei speichern.")
    var markdown: String?

    @Flag(help: "Bericht im Verlauf der App speichern. Über --via-app speichert die App selbst.")
    var archive = false

    @Flag(help: "Kurzfassung (openobd.digest/1) statt des vollständigen Berichts ausgeben.")
    var digest = false

    func run() async throws {
        try await CLI.execute("scan", json: output.json) { context in
            try await Self.perform(connection.connector(context, progress: !output.json), depth: depth, out: out, markdown: markdown,
                                   archive: archive, digest: digest, store: ReportStore())
        }
    }

    /// `onReport` sees the full report even when `digest` shortens the output.
    static func perform(_ connect: Connector, depth: ScanDepth, out: String?, markdown: String?, archive: Bool, digest: Bool,
                        store: ReportStore, onReport: (VehicleReport) -> Void = { _ in }) async throws -> CLIResult<ReportPayload> {
        let backend = try await connect()
        let report = try await backend.scan(depth: depth)
        onReport(report)
        if let out {
            try CLI.write(ReportCoding.encode(report), to: out)
        }
        if let markdown {
            try CLI.write(Data(MarkdownExporter.render(report).utf8), to: markdown)
        }
        var human = HumanFormat.report(report)
        if archive, !(backend is BridgeClient) {
            let url: URL
            do {
                url = try store.save(report)
            } catch {
                throw CLIError.file("Bericht konnte nicht im Verlauf gespeichert werden: \(error.localizedDescription)")
            }
            human += "\n\nIm Verlauf gespeichert: \(url.path)"
        }
        return CLIResult(data: ReportPayload(report, digest: digest), human: human)
    }
}
