import ArgumentParser
import FordKnowledge
import OBDCore

struct ExplainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explain",
        abstract: "Erklärt Fehlercodes, PIDs, Antwortcodes, Kennungen und Moduladressen. Ohne Fahrzeug.",
        subcommands: [ExplainDTCCommand.self, ExplainPIDCommand.self, ExplainNRCCommand.self, ExplainDIDCommand.self, ExplainModuleCommand.self])
}

struct DTCExplanationOutput: Encodable, Sendable {
    let code: String
    let failureType: String?
    let system: String
    let origin: String
    let subsystem: String?
    let title: String?
    let titleSource: String?
    let titleConfidence: Confidence?
    let failureTypeCategory: String?
    let failureTypeDetail: String?
    let explanation: DTCExplanation?
    let note: String?

    static func make(_ text: String, knowledge: KnowledgeBase) throws -> DTCExplanationOutput {
        let parts = text.uppercased().split(separator: "-", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let dtc = DTCCode(String(parts[0])) else {
            throw CLIError.usage("\(text) ist kein Fehlercode. Beispiel: P0401 oder U0100-87")
        }
        var failureType: UInt8?
        if parts.count == 2 {
            guard parts[1].count == 2, let value = UInt8(parts[1], radix: 16) else {
                throw CLIError.usage("Fehlerart \(parts[1]) ist kein Hex-Byte")
            }
            failureType = value
        }
        let title = knowledge.title(for: dtc)
        let failure = failureType.map(FailureType.describe)
        return DTCExplanationOutput(
            code: dtc.description, failureType: failureType.map(Hex.byteString), system: dtc.system.german,
            origin: dtc.origin.german, subsystem: dtc.subsystemGerman, title: title?.titleDE, titleSource: title?.source,
            titleConfidence: title?.confidence, failureTypeCategory: failure?.category, failureTypeDetail: failure?.detail,
            explanation: knowledge.explanation(for: dtc),
            note: title == nil ? "Für diesen Code liegt kein Text vor. Herstellerspezifische Codes werden nicht geraten." : nil)
    }

    var human: String {
        var lines = ["\(code)\(failureType.map { "-\($0)" } ?? ""): \(title ?? "kein Text bekannt")"]
        lines.append("System: \(system), \(origin)\(subsystem.map { ", \($0)" } ?? "")")
        if let failureTypeCategory {
            lines.append("Fehlerart: \(failureTypeCategory)\(failureTypeDetail.map { ", \($0)" } ?? "")")
        }
        if let explanation {
            lines += ["", explanation.what, "Dringlichkeit: \(explanation.urgency)"]
            lines += explanation.causes.map { "  - \($0)" }
        }
        if let note { lines += ["", note] }
        return lines.joined(separator: "\n")
    }
}

struct ExplainDTCCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "dtc", abstract: "Erklärt einen Fehlercode wie P0401 oder U0100-87.")

    @OptionGroup var output: OutputOptions

    @Argument(help: "Fehlercode, optional mit Fehlerart, zum Beispiel P0401 oder U0100-87.")
    var code: String

    func run() async throws {
        try await CLI.execute("explain dtc", json: output.json) { _ in try Self.perform(code) }
    }

    static func perform(_ code: String) throws -> CLIResult<DTCExplanationOutput> {
        let explanation = try DTCExplanationOutput.make(code, knowledge: .bundled)
        return CLIResult(data: explanation, human: explanation.human)
    }
}

struct ExplainPIDCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "pid", abstract: "Erklärt eine OBD-PID mit Formel.")

    @OptionGroup var output: OutputOptions

    @Argument(help: "PID als Hex, zum Beispiel 0C.")
    var pid: String

    func run() async throws {
        try await CLI.execute("explain pid", json: output.json) { _ in try Self.perform(pid) }
    }

    static func perform(_ pid: String) throws -> CLIResult<PIDListing> {
        let value = try ArgumentParsing.pid(pid)
        guard let definition = J1979.definition(value) else {
            throw CLIError.usage("PID \(Hex.byteString(value)) ist nicht im Katalog. Unbekannte PIDs werden als Rohwert gezeigt.")
        }
        let data = PIDListing(ecu: nil, pid: Hex.byteString(value), name: definition.name, category: definition.category.german, formula: definition.formula)
        return CLIResult(data: data, human: "\(data.pid): \(data.name)\nKategorie: \(data.category)\nFormel: \(data.formula)\nQuelle: \(definition.reference)")
    }
}

struct NRCExplanation: Encodable, Sendable {
    let code: String
    let name: String
    let german: String
}

struct ExplainNRCCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "nrc", abstract: "Erklärt einen UDS-Negativantwortcode wie 31.")

    @OptionGroup var output: OutputOptions

    @Argument(help: "Antwortcode als Hex, zum Beispiel 31.")
    var code: String

    func run() async throws {
        try await CLI.execute("explain nrc", json: output.json) { _ in try Self.perform(code) }
    }

    static func perform(_ code: String) throws -> CLIResult<NRCExplanation> {
        guard code.count == 2, Hex.isHexDigits(code), let value = UInt8(code, radix: 16) else {
            throw CLIError.usage("\(code) ist kein Antwortcode. Beispiel: 31")
        }
        let data = NRCExplanation(code: Hex.byteString(value), name: NegativeResponseCode.name(value), german: NegativeResponseCode.german(value))
        return CLIResult(data: data, human: "NRC \(data.code) (\(data.name)): \(data.german)")
    }
}

struct DIDExplanation: Encodable, Sendable {
    let did: String
    let known: Bool
    let name: String?
    let nameEN: String?
    let format: DIDFormat?
    let confidence: Confidence
    let source: String?
}

struct ExplainDIDCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "did", abstract: "Erklärt eine Kennung (DID) wie F190.")

    @OptionGroup var output: OutputOptions

    @Argument(help: "DID als Hex, zum Beispiel F190.")
    var did: String

    func run() async throws {
        try await CLI.execute("explain did", json: output.json) { _ in try Self.perform(did) }
    }

    static func perform(_ did: String) throws -> CLIResult<DIDExplanation> {
        let value = try ArgumentParsing.did(did)
        let definition = KnowledgeBase.bundled.did(value)
        let data = DIDExplanation(did: did.uppercased(), known: definition != nil, name: definition?.nameDE, nameEN: definition?.nameEN,
                                  format: definition?.format, confidence: definition?.confidence ?? .unknown, source: definition?.source)
        let human = definition.map { "\(data.did): \($0.nameDE) (\($0.confidence.german))\nQuelle: \($0.source)" }
            ?? "\(data.did) ist in der Wissensbasis nicht beschrieben. Der Wert wird roh angezeigt."
        return CLIResult(data: data, human: human)
    }
}

struct ModuleExplanation: Encodable, Sendable {
    let request: String
    let response: String
    let known: Bool
    let acronym: String?
    let name: String?
    let nameEN: String?
    let buses: [BusKind]
    let confidence: Confidence
    let source: String?
}

struct ExplainModuleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "module", abstract: "Erklärt eine Ford-Moduladresse wie 726.")

    @OptionGroup var output: OutputOptions

    @Argument(help: "Anfrage-ID, zum Beispiel 726.")
    var module: String

    func run() async throws {
        try await CLI.execute("explain module", json: output.json) { _ in try Self.perform(module) }
    }

    static func perform(_ module: String) throws -> CLIResult<ModuleExplanation> {
        let request = try ArgumentParsing.module(module)
        let definition = KnowledgeBase.bundled.module(request: request)
        let data = ModuleExplanation(request: Hex.canID(request, extended: false), response: Hex.canID(request + 8, extended: false),
                                     known: definition != nil, acronym: definition?.acronym, name: definition?.nameDE, nameEN: definition?.nameEN,
                                     buses: definition?.buses ?? [], confidence: definition?.confidence ?? .unknown, source: definition?.source)
        let human = definition.map { "\(data.request) / \(data.response): \($0.acronym) \($0.nameDE) (\($0.confidence.german))\nBusse: \($0.buses.map(\.shortName).joined(separator: ", "))" }
            ?? "\(data.request) ist keine bekannte Ford-Adresse."
        return CLIResult(data: data, human: human)
    }
}
