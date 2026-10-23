import AdapterKit
import FordKnowledge
import Foundation
import OBDCore

/// Collects scan results step by step and assembles the final report. Confined to one scan task.
final class ReportBuilder {
    let knowledge: KnowledgeBase
    let depth: ScanDepth
    let link: String
    let simulated: Bool
    let title: String?
    let vehicleHint: String?
    let createdAt: Date

    var identity: AdapterIdentity?
    var voltage: Double?
    var buses: [BusAvailability] = []
    var protocolName: String?
    var warnings: [String] = []
    private(set) var steps: [StepRecord] = []
    private(set) var ecus: [UInt32: ReportOBDECU] = [:]
    private(set) var modules: [ReportModule] = []

    init(knowledge: KnowledgeBase, depth: ScanDepth, link: String, simulated: Bool, title: String?, vehicleHint: String?, createdAt: Date = Date()) {
        self.knowledge = knowledge
        self.depth = depth
        self.link = link
        self.simulated = simulated
        self.title = title
        self.vehicleHint = vehicleHint
        self.createdAt = createdAt
    }

    func record(_ step: ScanStep, _ outcome: StepRecord.Outcome, _ duration: Duration, _ detail: String) {
        steps.append(StepRecord(step: step, title: step.title, outcome: outcome, durationMilliseconds: Int(duration.wholeMilliseconds), detail: detail))
    }

    func updateECU(_ id: UInt32, _ change: (inout ReportOBDECU) -> Void) {
        var ecu = ecus[id] ?? ReportOBDECU(address: Hex.canID(id, extended: false))
        change(&ecu)
        ecus[id] = ecu
    }

    func addModule(_ module: DiscoveredModule) {
        guard !modules.contains(where: { $0.id == module.id }) else { return }
        let name = Self.moduleName(requestID: module.requestID, identification: [], knowledge: knowledge)
        modules.append(ReportModule(
            id: module.id, bus: module.bus, requestID: module.requestHex, responseID: module.responseHex,
            responseMilliseconds: module.responseMilliseconds, acronym: name.acronym, name: name.name,
            nameConfidence: name.confidence, nameSource: name.source, zone: name.zone))
    }

    func updateModule(_ id: String, _ change: (inout ReportModule) -> Void) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        change(&modules[index])
    }

    func build(duration: Duration) -> VehicleReport {
        var finalModules = modules.map { module -> ReportModule in
            var module = module
            let name = Self.moduleName(requestID: Hex.parseCANID(module.requestID) ?? 0, identification: module.identification, knowledge: knowledge)
            module.acronym = name.acronym
            module.name = name.name
            module.nameConfidence = name.confidence
            module.nameSource = name.source
            module.zone = name.zone ?? module.zone
            return module
        }
        finalModules.sort { ($0.bus == .hsCAN ? 0 : 1, $0.requestID) < ($1.bus == .hsCAN ? 0 : 1, $1.requestID) }
        let finalECUs = ecus.keys.sorted().compactMap { ecus[$0] }

        var vinSources: [VINSource] = finalECUs.compactMap { ecu in
            ecu.info?.vin.map { VINSource(source: "OBD Dienst 09 von \(ecu.address)", vin: $0) }
        }
        for module in finalModules {
            if let vin = module.identification.first(where: { $0.vin != nil })?.vin {
                vinSources.append(VINSource(source: "DID F190 von \(module.requestID) (\(module.acronym ?? module.name))", vin: vin))
            }
        }
        let counts = Dictionary(grouping: vinSources.map(\.vin), by: { $0 }).mapValues(\.count)
        let vin = vinSources.map(\.vin).max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
        let vinInfo = vin.map { VINDecoder.decode($0, knowledge: knowledge) }
        let vehicleTitle = title ?? vehicleHint.flatMap { knowledge.vehicle(id: $0)?.nameDE } ?? (vinInfo?.manufacturer != nil ? "Ford-Fahrzeug" : "Fahrzeug")

        let obd = ReportOBD(protocolName: protocolName, ecus: finalECUs)
        let codes = finalECUs.flatMap(\.troubleCodes) + finalModules.flatMap(\.troubleCodes)
        let milOn = finalECUs.compactMap { $0.readiness?.milOn }.contains(true) ? true : (finalECUs.contains { $0.readiness != nil } ? false : nil)
        let noResponse = finalECUs.isEmpty && finalModules.isEmpty
        let findings = Self.findings(noResponse: noResponse, vinSources: vinSources, voltage: voltage, ecus: finalECUs, buses: buses, simulated: simulated)

        return VehicleReport(
            schema: VehicleReport.schemaName,
            meta: ReportMeta(tool: OpenOBD.toolDescription, createdAt: createdAt, depth: depth, durationMilliseconds: Int(duration.wholeMilliseconds),
                             link: link, simulated: simulated, steps: steps),
            adapter: ReportAdapter(identity: identity, voltage: voltage, buses: buses),
            vehicle: ReportVehicle(title: vehicleTitle, vin: vin, vinSources: vinSources, vinInfo: vinInfo, profileHint: vehicleHint),
            summary: Self.summary(codes: codes, moduleCount: finalModules.count, milOn: milOn, vin: vin, findings: findings, noResponse: noResponse),
            obd: obd,
            modules: finalModules,
            findings: findings,
            warnings: warnings)
    }

    // MARK: - Rules

    struct ModuleName: Equatable {
        let acronym: String?
        let name: String
        let confidence: Confidence
        let source: String
        let zone: VehicleZone?
    }

    /// Catalog address and part number base are both community knowledge. They raise or lower plausibility, never certainty.
    static func moduleName(requestID: UInt32, identification: [DIDReading], knowledge: KnowledgeBase) -> ModuleName {
        let catalog = knowledge.module(request: requestID)
        let base = identification.compactMap { $0.partNumber?.base }.compactMap { knowledge.partNumberBase($0) }.first
        switch (catalog, base) {
        case let (catalog?, base?) where catalog.acronym == base.acronym:
            return ModuleName(acronym: catalog.acronym, name: catalog.nameDE, confidence: .community, source: "Adresse und Teilenummer passen zusammen", zone: catalog.zone)
        case let (catalog?, base?):
            return ModuleName(acronym: base.acronym, name: base.nameDE, confidence: .community, source: "Teilenummer \(base.base) widerspricht der Adresse (\(catalog.acronym))", zone: catalog.zone)
        case let (catalog?, nil):
            return ModuleName(acronym: catalog.acronym, name: catalog.nameDE, confidence: .community, source: "Typische Ford-Adresse, nicht durch Teilenummer bestätigt", zone: catalog.zone)
        case let (nil, base?):
            return ModuleName(acronym: base.acronym, name: base.nameDE, confidence: .community, source: "Aus der Teilenummer \(base.base)", zone: nil)
        case (nil, nil):
            return ModuleName(acronym: nil, name: "Unbekanntes Steuergerät \(Hex.canID(requestID, extended: false))", confidence: .unknown, source: "Weder Adresse noch Teilenummer bekannt", zone: nil)
        }
    }

    static func findings(noResponse: Bool, vinSources: [VINSource], voltage: Double?, ecus: [ReportOBDECU], buses: [BusAvailability], simulated: Bool) -> [Finding] {
        var findings: [Finding] = []
        if noResponse {
            findings.append(Finding(kind: .noVehicleResponse, severity: .high, text: "Das Fahrzeug antwortet nicht. Ist die Zündung an und sitzt der Adapter fest?",
                                    evidence: "Keine Antwort auf OBD 01 00 und kein Steuergerät bei der Modulsuche"))
        }
        let distinct = Set(vinSources.map(\.vin))
        if distinct.count > 1 {
            findings.append(Finding(kind: .vinMismatch, severity: .medium,
                                    text: "Nicht alle Steuergeräte melden dieselbe Fahrgestellnummer. Ein Steuergerät könnte getauscht oder anders codiert sein.",
                                    evidence: vinSources.map { "\($0.source): \($0.vin)" }.joined(separator: "; ")))
        }
        if let voltage, voltage < AdapterDriver.vehiclePowerThreshold {
            findings.append(Finding(kind: .noVehiclePower, severity: .high,
                                    text: "Der Adapter bekommt keinen Strom vom Auto (\(MeasuredValue.format(voltage)) V). Er steckt nicht in der OBD-Buchse, oder deren Sicherung ist defekt.",
                                    evidence: "Adaptermessung ATRV an Pin 16"))
        } else if let voltage, voltage < 12.0 {
            findings.append(Finding(kind: .lowVoltage, severity: voltage < 11.6 ? .high : .medium,
                                    text: "Batteriespannung niedrig (\(MeasuredValue.format(voltage)) V). Unter 12 V ist die Batterie meist deutlich entladen.",
                                    evidence: "Adaptermessung ATRV an Pin 16"))
        }
        if ecus.contains(where: { $0.readiness?.milOn == true }) {
            findings.append(Finding(kind: .milOn, severity: .high, text: "Die Motorkontrollleuchte ist an.", evidence: "OBD 01 01, Bit A7"))
        }
        let incomplete = ecus.flatMap { $0.readiness?.incompleteMonitors.map(\.name) ?? [] }
        if !incomplete.isEmpty {
            findings.append(Finding(kind: .readinessIncomplete, severity: .info,
                                    text: "Nicht abgeschlossene Bereitschaftstests: \(incomplete.joined(separator: ", ")). Für die Abgasuntersuchung müssen sie abgeschlossen sein.",
                                    evidence: "OBD 01 01, Bytes C und D"))
        }
        for bus in buses where !bus.available {
            findings.append(Finding(kind: .busUnavailable, severity: .info, text: "\(bus.bus.shortName) war nicht erreichbar. \(bus.note ?? "")".trimmingCharacters(in: .whitespaces),
                                    evidence: "Buswahl des Adapters"))
        }
        if simulated {
            findings.append(Finding(kind: .simulated, severity: .info, text: "Simulator: Diese Daten stammen nicht von einem echten Fahrzeug.", evidence: "Verbindung zum Simulator"))
        }
        return findings
    }

    static func summary(codes: [ReportDTC], moduleCount: Int, milOn: Bool?, vin: String?, findings: [Finding], noResponse: Bool) -> ReportSummary {
        // One fault per module and code, represented by its most severe entry.
        var strongest: [String: ReportDTC] = [:]
        for code in codes {
            let key = "\(code.module)-\(code.code)"
            if let existing = strongest[key], existing.severity >= code.severity { continue }
            strongest[key] = code
        }
        let faults = Array(strongest.values)
        let headline: String
        if noResponse {
            headline = "Keine Antwort vom Fahrzeug."
        } else if codes.isEmpty {
            headline = "Keine Fehler gespeichert."
        } else {
            let modules = Set(faults.map(\.module)).count
            let urgent = faults.filter { $0.severity >= .high }.count
            headline = "\(faults.count) Fehler in \(modules) \(modules == 1 ? "Steuergerät" : "Steuergeräten")."
                + (urgent > 0 ? " \(urgent) davon dringend." : "")
        }
        let ranked = faults.sorted { ($0.severity, $1.displayCode) > ($1.severity, $0.displayCode) }
        var highlights = ranked.prefix(3).map { code in
            "\(code.displayCode) \(code.title ?? "herstellerspezifisch, Bedeutung unbekannt"): \(code.state), \(code.severity.german)"
        }
        highlights += findings.filter { $0.severity >= .medium && $0.kind != .noVehicleResponse }.map(\.text)
        var bySeverity: [String: Int] = [:]
        for severity in Severity.allCases {
            bySeverity[severity.rawValue] = codes.filter { $0.severity == severity }.count
        }
        return ReportSummary(headline: headline, highlights: Array(highlights.prefix(5)), moduleCount: moduleCount,
                             troubleCodeCount: codes.count, faultCount: faults.count, bySeverity: bySeverity, milOn: milOn, vin: vin)
    }
}
