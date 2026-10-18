import ArgumentParser
import DiagnosticEngine
import Foundation

struct ReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Arbeitet mit gespeicherten Berichten.",
        subcommands: [ReportShowCommand.self, ReportListCommand.self, ReportLastCommand.self])
}

struct ReportShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Zeigt einen gespeicherten Bericht an.")

    @OptionGroup var output: OutputOptions

    @Argument(help: "Pfad zur Berichtsdatei (JSON).")
    var path: String

    @Flag(help: "Als Markdown ausgeben.")
    var markdown = false

    @Flag(help: "Kurzfassung (openobd.digest/1) statt des vollständigen Berichts.")
    var digest = false

    func run() async throws {
        try await CLI.execute("report show", json: output.json) { _ in try Self.perform(path: path, markdown: markdown, digest: digest) }
    }

    static func perform(path: String, markdown: Bool, digest: Bool) throws -> CLIResult<ReportPayload> {
        let report = try load(path)
        return CLIResult(data: ReportPayload(report, digest: digest), human: markdown ? MarkdownExporter.render(report) : HumanFormat.report(report))
    }

    static func load(_ path: String) throws -> VehicleReport {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw CLIError.file("\(path) konnte nicht gelesen werden.")
        }
        do {
            return try ReportCoding.decode(data)
        } catch {
            throw CLIError.file("\(path) ist kein gültiger Bericht (openobd.report/1).")
        }
    }
}

struct ReportListing: Encodable, Sendable {
    let path: String
    let title: String
    let vin: String?
    let date: Date
    let headline: String
    let simulated: Bool
    let faultCount: Int
}

struct ReportListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "Listet die Berichte im Verlauf der App, neueste zuerst.")

    @OptionGroup var output: OutputOptions

    @Option(help: "Höchstens so viele Berichte, neueste zuerst. 0 bedeutet alle.")
    var limit = 0

    func run() async throws {
        try await CLI.execute("report list", json: output.json) { _ in try Self.perform(store: ReportStore(), limit: limit) }
    }

    static func perform(store: ReportStore, limit: Int = 0) throws -> CLIResult<[ReportListing]> {
        guard limit >= 0 else { throw CLIError.usage("limit darf nicht negativ sein.") }
        let entries = store.list()
        let listing = (limit > 0 ? Array(entries.prefix(limit)) : entries).map {
            ReportListing(path: $0.url.path, title: $0.title, vin: $0.vin, date: $0.date, headline: $0.headline, simulated: $0.simulated, faultCount: $0.faultCount)
        }
        var table = TextTable(headers: ["Datum", "Fahrzeug", "Fehler", "Datei"])
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        listing.forEach { table.add([formatter.string(from: $0.date), $0.title, String($0.faultCount), $0.path]) }
        return CLIResult(data: listing, human: listing.isEmpty ? "Noch keine Berichte im Verlauf (\(store.directory.path))." : table.render())
    }
}

struct LastReportOutput: Encodable, Sendable {
    /// `session` (this MCP server), `app` (shown in Open OBD GUI) or `archive` (newest saved file).
    let source: String
    let path: String?
    let report: ReportPayload
}

struct ReportLastCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "last",
        abstract: "Zeigt den neuesten Bericht: aus der laufenden App, sonst aus dem Verlauf.")

    @OptionGroup var output: OutputOptions

    @Option(help: "Quelle: auto, app oder archive.")
    var source = "auto"

    @Flag(help: "Kurzfassung (openobd.digest/1) statt des vollständigen Berichts.")
    var digest = false

    @Option(help: ArgumentHelp("Socket der App-Brücke (für Tests).", visibility: .private))
    var bridgeSocket: String?

    func run() async throws {
        try await CLI.execute("report last", json: output.json) { _ in
            try await Self.perform(source: source, digest: digest, socket: bridgeSocket ?? BridgeEndpoint.defaultPath, store: ReportStore(), session: nil)
        }
    }

    /// `session` is the report of the calling process, if it scanned already (MCP server).
    static func perform(source: String, digest: Bool, socket: String, store: ReportStore, session: VehicleReport?) async throws -> CLIResult<LastReportOutput> {
        let allowed = ["auto", "session", "app", "archive"]
        guard allowed.contains(source) else { throw CLIError.usage("Unbekannte Quelle \(source). Erlaubt: \(allowed.joined(separator: ", "))") }
        func result(_ name: String, _ report: VehicleReport, path: String?) -> CLIResult<LastReportOutput> {
            var human = HumanFormat.report(report)
            if let path { human += "\n\nDatei: \(path)" }
            return CLIResult(data: LastReportOutput(source: name, path: path, report: ReportPayload(report, digest: digest)), human: human)
        }
        if source == "auto" || source == "session", let session {
            return result("session", session, path: nil)
        }
        if source == "auto" || source == "app", BridgeClient.isReachable(at: socket) {
            let client = try await BridgeClient.connect(at: socket)
            let report = try? await client.lastReport()
            await client.close()
            if let report { return result("app", report, path: nil) }
        } else if source == "app" {
            throw BridgeError.appNotRunning(path: socket)
        }
        if source == "auto" || source == "archive", let latest = store.latest() {
            return result("archive", latest.report, path: latest.entry.url.path)
        }
        throw CLIError.noReport
    }
}
