import ArgumentParser
import DiagnosticEngine
import Foundation
import OBDCore

struct LiveSample: Encodable, Sendable {
    let schema: String
    let time: Date
    let ecu: String
    let pid: String
    let name: String
    let value: String
    let number: Double?
    let unit: String?
    let fields: [DecodedField]
    let rawHex: String

    init(_ record: MeasurementRecord) {
        schema = "openobd.live/1"
        time = record.provenance.timestamp
        ecu = record.provenance.ecu
        pid = record.id.split(separator: ":").last.map(String.init) ?? ""
        name = record.name
        value = record.fields.map(\.value.displayText).joined(separator: "; ")
        if case .number(let number, let unit) = record.primaryValue {
            self.number = number
            self.unit = unit
        } else {
            number = nil
            unit = nil
        }
        fields = record.fields
        rawHex = record.rawHex
    }
}

struct LiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "live",
        abstract: "Liest OBD-Messwerte fortlaufend. Mit --json eine JSON-Zeile pro Messwert (openobd.live/1).")

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Argument(help: "PIDs als Hex, zum Beispiel 0C 0D 05.")
    var pids: [String]

    @Option(help: "Abfrageintervall in Millisekunden.")
    var interval = 500

    @Option(help: "Dauer in Sekunden. 0 bedeutet bis Strg+C.")
    var duration = 10.0

    @Option(help: "Höchstzahl an Messwerten. 0 bedeutet unbegrenzt.")
    var count = 0

    @Option(help: "Format: table, csv oder ndjson. Mit --json immer ndjson.")
    var format = "table"

    func run() async throws {
        let context = CLIContext()
        do {
            let codes = try Self.validate(pids: pids, interval: interval)
            let style = output.json ? "ndjson" : format
            guard ["table", "csv", "ndjson"].contains(style) else { throw CLIError.usage("Unbekanntes Format \(format). Erlaubt: table, csv, ndjson") }
            let backend = try await connection.spec().open(context)
            let deadline = duration > 0 ? ContinuousClock.now + .milliseconds(Int(duration * 1000)) : nil
            if style == "csv" { Output.line("zeit,steuergeraet,pid,name,wert,einheit,roh") }
            var emitted = 0
            for try await record in backend.live(pids: codes, interval: .milliseconds(interval)) {
                Output.line(try Self.render(LiveSample(record), style: style))
                emitted += 1
                if count > 0, emitted >= count { break }
                if let deadline, ContinuousClock.now >= deadline { break }
            }
            await context.cleanup()
        } catch {
            await context.cleanup()
            let payload = CLI.errorPayload(error)
            if output.json {
                let failure = Envelope<NoPayload>(schema: CLI.schema, command: "live", ok: false, data: nil, warnings: [], error: payload,
                                                  meta: CLIMeta(tool: OpenOBD.toolDescription, durationMs: 0, link: context.link, capture: context.capturePath))
                Output.line(try CLI.encode(failure, pretty: false))
            } else {
                Output.errorLine("Fehler: \(payload.message)")
            }
            throw ExitCode(CLI.exitCode(for: error))
        }
    }

    static func validate(pids: [String], interval: Int) throws -> [UInt8] {
        let codes = try pids.map(ArgumentParsing.pid)
        guard interval > 0, !codes.isEmpty else { throw CLIError.usage("Mindestens eine PID und ein Intervall über 0 angeben.") }
        return codes
    }

    /// Bounded collection for agents: stops after `count` samples or `duration` seconds, whichever comes first.
    static func collect(_ connect: Connector, pids: [String], interval: Int, count: Int, duration: Double) async throws -> CLIResult<[LiveSample]> {
        let codes = try validate(pids: pids, interval: interval)
        guard count > 0 || duration > 0 else { throw CLIError.usage("Für gesammelte Live-Daten count oder duration angeben.") }
        let backend = try await connect()
        let deadline = duration > 0 ? ContinuousClock.now + .milliseconds(Int(duration * 1000)) : nil
        var samples: [LiveSample] = []
        for try await record in backend.live(pids: codes, interval: .milliseconds(interval)) {
            samples.append(LiveSample(record))
            if count > 0, samples.count >= count { break }
            if let deadline, ContinuousClock.now >= deadline { break }
        }
        var table = TextTable(headers: ["Zeit", "Steuergerät", "PID", "Name", "Wert"])
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        samples.forEach { table.add([formatter.string(from: $0.time), $0.ecu, $0.pid, $0.name, $0.value]) }
        return CLIResult(data: samples, human: samples.isEmpty ? "Keine Messwerte." : table.render())
    }

    static func render(_ sample: LiveSample, style: String) throws -> String {
        switch style {
        case "ndjson":
            return try CLI.encode(sample, pretty: false)
        case "csv":
            let cells = [ISO8601DateFormatter().string(from: sample.time), sample.ecu, sample.pid, sample.name,
                         sample.number.map { String($0) } ?? sample.value, sample.unit ?? "", sample.rawHex]
            return cells.map { $0.contains(",") || $0.contains("\"") ? "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" : $0 }.joined(separator: ",")
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return "\(formatter.string(from: sample.time))  \(sample.ecu)  \(sample.pid)  \(sample.name): \(sample.value)"
        }
    }
}
