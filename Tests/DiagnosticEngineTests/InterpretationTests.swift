import Foundation
import Testing
import FordKnowledge
import OBDCore
@testable import DiagnosticEngine

@Suite struct InterpretationTests {
    let knowledge = KnowledgeBase.bundled

    func dtc(_ text: String, ftb: UInt8 = 0, status: UInt8) -> UDSDTC {
        UDSDTC(code: DTCCode(text)!, failureType: ftb, status: DTCStatus(rawValue: status))
    }

    @Test(arguments: [
        ("C0035", UInt8(0x89), Severity.critical, "aktiv"),
        ("B0012", 0x89, .critical, "aktiv"),
        ("P0301", 0x89, .critical, "aktiv"),
        ("P0401", 0x89, .high, "aktiv"),
        ("P0401", 0x88, .high, "gespeichert"),
        ("P0401", 0x08, .medium, "gespeichert"),
        ("P0401", 0x01, .medium, "aktiv"),
        ("P0401", 0x04, .medium, "vorläufig"),
        ("U0100", 0x28, .medium, "gespeichert"),
        ("U0100", 0xA8, .high, "gespeichert"),
        ("U0100", 0x20, .info, "historisch"),
        ("U0100", 0x00, .info, "ohne Fehlerbits"),
        ("B1318", 0x08, .medium, "gespeichert"),
    ])
    func severityRules(_ code: String, _ status: UInt8, _ severity: Severity, _ state: String) {
        let assessment = DTCInterpreter.assess(code: DTCCode(code)!, status: DTCStatus(rawValue: status))
        #expect(assessment.severity == severity)
        #expect(assessment.state == state)
        #expect(!assessment.reasons.isEmpty)
    }

    @Test func udsEntryIsFullyExplained() {
        let entry = DTCInterpreter.interpret(dtc("P0401", ftb: 0x00, status: 0xAF), module: 0x7E0, knowledge: knowledge)
        #expect(entry.displayCode == "P0401-00")
        #expect(entry.id == "7E0-P0401-00-uds")
        #expect(entry.module == "7E0")
        #expect(entry.title == "Abgasrückführung \"A\": Durchfluss zu gering")
        #expect(entry.titleConfidence == .standard)
        #expect(entry.explanation?.causes.isEmpty == false)
        #expect(entry.failureTypeCategory == "Allgemeine Fehlerart")
        #expect(entry.failureTypeDetail == "keine Unterart angegeben")
        #expect(entry.statusByte == 0xAF)
        #expect(entry.statusLabels.contains("Warnleuchte angefordert"))
        #expect(entry.subsystem == "Zusätzliche Abgasreinigung")
        #expect(entry.origin == "genormter Code (SAE)")
    }

    @Test func unknownManufacturerCodeIsNeverGuessed() {
        let entry = DTCInterpreter.interpret(dtc("B1318", ftb: 0x16, status: 0x08), module: 0x720, knowledge: knowledge)
        #expect(entry.title == nil)
        #expect(entry.origin == "herstellerspezifischer Code")
        #expect(entry.failureTypeDetail == "Spannung unter Schwellenwert")
        #expect(entry.system == "Karosserie (Airbag, Komfort, Licht)")
    }

    @Test func obdEntriesUseServiceAndMIL() {
        let stored = DTCInterpreter.interpret(obd: DTCCode("P0401")!, source: .obdStored, ecu: 0x7E8, milOn: true, knowledge: knowledge)
        #expect(stored.severity == .high)
        #expect(stored.state == "gespeichert")
        #expect(stored.displayCode == "P0401")
        #expect(stored.failureType == nil)
        #expect(stored.module == "7E0")
        #expect(stored.id == "7E0-P0401-obd-stored")
        #expect(DTCInterpreter.interpret(obd: DTCCode("P0300")!, source: .obdStored, ecu: 0x7E8, milOn: true, knowledge: knowledge).severity == .critical)
        #expect(DTCInterpreter.interpret(obd: DTCCode("P0401")!, source: .obdStored, ecu: 0x7E8, milOn: false, knowledge: knowledge).severity == .medium)
        #expect(DTCInterpreter.interpret(obd: DTCCode("P0401")!, source: .obdPermanent, ecu: 0x7E8, milOn: true, knowledge: knowledge).state == "permanent")
        #expect(DTCInterpreter.interpret(obd: DTCCode("P0401")!, source: .obdPending, ecu: 0x7E8, milOn: false, knowledge: knowledge).state == "vorläufig")
    }

    @Test func severityOrder() {
        #expect(Severity.info < .medium && Severity.medium < .high && Severity.high < .critical)
        #expect([Severity.medium, .critical, .info].max() == .critical)
    }

    @Test func europeanFordVIN() {
        let info = VINDecoder.decode("WF0DXXGBBDSM12345", knowledge: knowledge)
        #expect(info.isValid)
        #expect(info.wmi == "WF0")
        #expect(info.manufacturer == "Ford-Werke GmbH, Deutschland")
        #expect(info.region == "Europa")
        #expect(info.vehicleDescriptor == "DXXGBB")
        #expect(info.serial == "M12345")
        #expect(info.modelYearCandidates.isEmpty)
        #expect(!info.checkDigitApplies)
    }

    @Test func northAmericanVINHasCheckDigitAndModelYear() {
        let info = VINDecoder.decode("1M8GDM9AXKP042788", knowledge: knowledge)
        #expect(info.region == "Nordamerika")
        #expect(info.checkDigitApplies)
        #expect(info.checkDigitValid == true)
        #expect(info.modelYearCandidates == [1989, 2019])
        #expect(VINDecoder.expectedCheckDigit("1M8GDM9AXKP042788") == "X")
        #expect(VINDecoder.decode("1M8GDM9A1KP042788", knowledge: knowledge).checkDigitValid == false)
    }

    @Test func invalidVINIsMarked() {
        #expect(!VINDecoder.decode("WF0", knowledge: knowledge).isValid)
        #expect(VINDecoder.expectedCheckDigit("SHORT") == nil)
    }
}
