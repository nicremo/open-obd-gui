import AdapterKit
import Foundation
import Testing
import FordKnowledge
import OBDCore
@testable import DiagnosticEngine

@Suite struct ReportTests {
    let knowledge = KnowledgeBase.bundled

    func reading(_ did: String, _ text: String) -> DIDReading {
        Identification.reading(did: UInt16(did, radix: 16)!, reply: UDSReply(outcome: .positive(Array(text.utf8)), request: [], response: nil, elapsed: .zero), knowledge: knowledge)
    }

    func builder() -> ReportBuilder {
        ReportBuilder(knowledge: knowledge, depth: .standard, link: "test", simulated: false, title: nil, vehicleHint: "mondeo-mk4",
                      createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test(arguments: [
        (UInt32(0x7E0), ["SIM1-12A650-AA"], "Motorsteuergerät", "PCM", Confidence.community, "Adresse und Teilenummer passen zusammen"),
        (0x7E0, ["SIM1-14B321-AA"], "Airbag-Steuergerät", "RCM", .community, "Teilenummer 14B321 widerspricht der Adresse (PCM)"),
        (0x726, [], "Karosseriesteuergerät", "BCM", .community, "Typische Ford-Adresse, nicht durch Teilenummer bestätigt"),
        (0x7A2, ["SIM1-10849-AA"], "Kombiinstrument", "IPC", .community, "Aus der Teilenummer 10849"),
        (0x7A2, [], "Unbekanntes Steuergerät 7A2", nil, .unknown, "Weder Adresse noch Teilenummer bekannt"),
    ] as [(UInt32, [String], String, String?, Confidence, String)])
    func moduleNamesAreResolvedCarefully(_ request: UInt32, _ parts: [String], _ name: String, _ acronym: String?, _ confidence: Confidence, _ source: String) {
        let resolved = ReportBuilder.moduleName(requestID: request, identification: parts.map { reading("F111", $0) }, knowledge: knowledge)
        #expect(resolved.name == name)
        #expect(resolved.acronym == acronym)
        #expect(resolved.confidence == confidence)
        #expect(resolved.source == source)
    }

    @Test func emptyScanReportsNoResponse() {
        let report = builder().build(duration: .seconds(2))
        #expect(report.summary.headline == "Keine Antwort vom Fahrzeug.")
        #expect(report.findings.map(\.kind) == [.noVehicleResponse])
        #expect(report.vehicle.title == "Ford Mondeo IV (BA7)")
        #expect(report.schema == "openobd.report/1")
    }

    @Test func findingsAndSummaryFromData() throws {
        let builder = builder()
        builder.voltage = 11.5
        builder.updateECU(0x7E8) { ecu in
            ecu.readiness = try? ReadinessReport.decode([0x81, 0x0F, 0xE9, 0x08], kind: .sinceClear)
            ecu.info = OBDECUInfo(ecu: "7E8", vin: "WF0DXXGBBDSM12345")
            ecu.troubleCodes = [DTCInterpreter.interpret(obd: DTCCode("P0401")!, source: .obdStored, ecu: 0x7E8, milOn: true, knowledge: knowledge)]
        }
        builder.addModule(DiscoveredModule(bus: .msCAN, requestID: 0x726, responseID: 0x72E, responseMilliseconds: 12, probe: "3E 00", catalogAcronym: "BCM"))
        builder.updateModule("ms-can-726") { module in
            module.identification = [reading("F190", "WF0DXXGBBDSM99999")]
            module.troubleCodes = [DTCInterpreter.interpret(UDSDTC(code: DTCCode("U0100")!, failureType: 0x87, status: DTCStatus(rawValue: 0x28)), module: 0x726, knowledge: knowledge)]
        }
        let report = builder.build(duration: .seconds(5))
        #expect(Set(report.findings.map(\.kind)) == [.lowVoltage, .milOn, .vinMismatch, .readinessIncomplete])
        #expect(report.findings.first { $0.kind == .lowVoltage }?.severity == .high)
        #expect(report.vehicle.vin == "WF0DXXGBBDSM12345")
        #expect(report.vehicle.vinSources.count == 2)
        #expect(report.summary.headline == "2 Fehler in 2 Steuergeräten. 1 davon dringend.")
        #expect(report.summary.troubleCodeCount == 2)
        #expect(report.summary.bySeverity == ["info": 0, "medium": 1, "high": 1, "critical": 0])
        #expect(report.summary.highlights.first?.hasPrefix("P0401") == true)
        #expect(report.modules.first?.name == "Karosseriesteuergerät")
        #expect(report.allTroubleCodes.count == 2)
    }

    @Test func singleCodeUsesSingular() {
        let builder = builder()
        builder.updateECU(0x7E8) { ecu in
            ecu.troubleCodes = [DTCInterpreter.interpret(obd: DTCCode("P0401")!, source: .obdPending, ecu: 0x7E8, milOn: false, knowledge: knowledge)]
        }
        #expect(builder.build(duration: .zero).summary.headline == "1 Fehler in 1 Steuergerät.")
    }

    @Test func reportRoundTripsThroughJSON() throws {
        let builder = builder()
        builder.updateECU(0x7E8) { $0.supportedPIDs = ["0C", "0D"] }
        builder.record(.adapter, .ok, .milliseconds(120), "OBDLink EX")
        let report = builder.build(duration: .seconds(1))
        let data = try ReportCoding.encode(report)
        #expect(try ReportCoding.decode(data) == report)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"schema\" : \"openobd.report/1\""))
        #expect(json.contains("\"createdAt\" : \"2027-01-15T08:00:00Z\""))
    }

    @Test func markdownIsReadableAndClean() {
        let builder = builder()
        builder.updateECU(0x7E8) { ecu in
            ecu.troubleCodes = [DTCInterpreter.interpret(obd: DTCCode("P0401")!, source: .obdStored, ecu: 0x7E8, milOn: true, knowledge: knowledge)]
        }
        builder.addModule(DiscoveredModule(bus: .hsCAN, requestID: 0x7E0, responseID: 0x7E8, responseMilliseconds: 9, probe: "3E 00", catalogAcronym: "PCM"))
        let markdown = MarkdownExporter.render(builder.build(duration: .seconds(3)))
        #expect(markdown.hasPrefix("# Fahrzeugbericht: Ford Mondeo IV (BA7)"))
        for section in ["## Zusammenfassung", "## Fahrzeug", "## Fehlerspeicher", "## Steuergeräte", "## Adapter", "## Ablauf"] {
            #expect(markdown.contains(section))
        }
        #expect(markdown.contains("P0401"))
        #expect(markdown.contains("Abgasrückführung"))
        #expect(!markdown.contains("\u{2013}") && !markdown.contains("\u{2014}"))
    }

    @Test func stepsFollowTheDepthTable() {
        #expect(ScanStep.allCases.filter { $0.isIncluded(in: .quick) } == [.adapter, .obdSupport, .obdReadiness, .obdTroubleCodes, .obdVehicleInfo, .discoveryHS, .moduleTroubleCodes])
        #expect(ScanStep.allCases.filter { !$0.isIncluded(in: .standard) } == [.troubleCodeDetails, .asBuilt])
        #expect(ScanStep.allCases.allSatisfy { $0.isIncluded(in: .deep) })
    }
}
