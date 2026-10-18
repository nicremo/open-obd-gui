import AdapterKit
import ArgumentParser
import OBDCore

struct RawMessage: Encodable, Sendable {
    let source: String
    let payload: String
    let interpretation: String
}

struct RawOutput: Encodable, Sendable {
    let request: String
    let target: String
    let bus: BusKind
    let elapsedMs: Int
    let messages: [RawMessage]
    let adapterText: String
}

struct RawCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "raw",
        abstract: "Expertenanfrage an ein Steuergerät. Nur lesende Dienste sind erlaubt.",
        discussion: "Erlaubt: 01 02 03 06 07 09 0A 22 19 (01,02,03,04,06,0A) 3E (00,80) 10 01. Alles andere wird vor dem Senden abgelehnt (Exitcode 6).")

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(help: "Steuergerät, Anfrage-ID wie 7E0.")
    var module: String?

    @Flag(help: "Funktionale OBD-Anfrage an 7DF statt an ein Modul.")
    var functional = false

    @Option(help: "Bus: hs oder ms.")
    var bus = "hs"

    @Option(help: "Wartezeit auf Antworten in Millisekunden.")
    var timeout = 500

    @Argument(help: "Nutzdaten als Hex, zum Beispiel \"22 F1 90\".")
    var payload: [String]

    func run() async throws {
        try await CLI.execute("raw", json: output.json) { context in
            try await Self.perform(connection.connector(context), payload: payload.joined(separator: " "), module: module, functional: functional,
                                   bus: bus, timeout: timeout)
        }
    }

    /// The read-only policy is checked before any connection is opened.
    static func perform(_ connect: Connector, payload: String, module: String?, functional: Bool, bus: String,
                        timeout: Int) async throws -> CLIResult<RawOutput> {
        let bytes = try ArgumentParsing.payload([payload])
        try ReadOnlyPolicy.validate(bytes)
        let target: RequestTarget
        if functional {
            target = .functional
        } else if let module {
            target = .module(try ArgumentParsing.module(module))
        } else {
            throw CLIError.usage("Bitte --module oder --functional angeben.")
        }
        let busKind = try ArgumentParsing.bus(bus)
        guard timeout > 0 else { throw CLIError.usage("Die Wartezeit muss größer als 0 sein.") }
        let result = try await connect().rawRequest(bytes, target: target, bus: busKind, timeout: .milliseconds(timeout))
        let messages = result.messages.map {
            RawMessage(source: $0.source.description, payload: Hex.encode($0.payload), interpretation: Self.interpret($0.payload, service: bytes[0]))
        }
        let data = RawOutput(request: Hex.encode(bytes), target: functional ? "7DF (funktional)" : Hex.canID(target.requestID, extended: false),
                             bus: busKind, elapsedMs: Int(result.elapsed.wholeMilliseconds), messages: messages, adapterText: result.rawText)
        var table = TextTable(headers: ["Quelle", "Antwort", "Deutung"])
        messages.forEach { table.add([$0.source, $0.payload, $0.interpretation]) }
        return CLIResult(data: data, human: messages.isEmpty ? "Keine Antwort." : table.render())
    }

    static func interpret(_ payload: [UInt8], service: UInt8) -> String {
        guard let first = payload.first else { return "leer" }
        if first == 0x7F, payload.count >= 3 {
            return payload[2] == 0x78
                ? "Antwort folgt (NRC 78)"
                : "abgelehnt: NRC \(Hex.byteString(payload[2])) \(NegativeResponseCode.german(payload[2]))"
        }
        if first == service &+ 0x40 {
            return "positive Antwort auf Dienst \(Hex.byteString(service))"
        }
        return "unerwartete Antwort"
    }
}
