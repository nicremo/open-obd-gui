import Foundation
import Testing
@testable import OBDCore

@Suite struct DTCTests {
    @Test(arguments: [
        ("P0401", UInt16(0x0401)), ("U0100", 0xC100), ("C0035", 0x4035), ("B1318", 0x9318),
        ("P2463", 0x2463), ("P242F", 0x242F), ("U3000", 0xF000), ("P0000", 0x0000),
    ])
    func parsesAndFormats(_ text: String, _ raw: UInt16) throws {
        let code = try #require(DTCCode(text))
        #expect(code.raw == raw)
        #expect(code.description == text)
        #expect(DTCCode(raw: raw).description == text)
    }

    @Test(arguments: ["", "P040", "P04011", "X0401", "P4401", "P04G1", "p0401x"])
    func rejectsInvalidText(_ text: String) {
        #expect(DTCCode(text) == nil)
    }

    @Test func acceptsLowercase() {
        #expect(DTCCode("p0401")?.raw == 0x0401)
    }

    @Test func buildsFromTwoBytes() {
        #expect(DTCCode(high: 0x01, low: 0x33).description == "P0133")
        #expect(DTCCode(high: 0xC1, low: 0x55).description == "U0155")
    }

    @Test(arguments: [
        ("P0401", DTCCode.Origin.sae), ("P1000", .manufacturer), ("P2002", .sae), ("P3000", .manufacturer),
        ("P3400", .sae), ("B0001", .sae), ("B1318", .manufacturer), ("C2100", .manufacturer),
        ("U0100", .sae), ("U3000", .sae),
    ])
    func classifiesOrigin(_ text: String, _ origin: DTCCode.Origin) throws {
        #expect(try #require(DTCCode(text)).origin == origin)
    }

    @Test func namesPowertrainSubsystems() {
        #expect(DTCCode("P0300")?.subsystemGerman == "Zündsystem oder Fehlzündungen")
        #expect(DTCCode("P0401")?.subsystemGerman == "Zusätzliche Abgasreinigung")
        #expect(DTCCode("P0700")?.subsystemGerman == "Getriebe")
        #expect(DTCCode("P2463")?.subsystemGerman == "Zusätzliche Abgasreinigung")
        #expect(DTCCode("P1000")?.subsystemGerman == nil)
        #expect(DTCCode("U0100")?.subsystemGerman == nil)
    }

    @Test func codableAsString() throws {
        let data = try JSONEncoder().encode([DTCCode("P0401")!])
        #expect(String(decoding: data, as: UTF8.self) == "[\"P0401\"]")
        #expect(try JSONDecoder().decode([DTCCode].self, from: data) == [DTCCode("P0401")!])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([DTCCode].self, from: Data("[\"Q1\"]".utf8)) }
    }

    @Test func statusBitsAreNamed() {
        let status = DTCStatus(rawValue: 0x89)
        #expect(status.contains(.testFailed))
        #expect(status.contains(.confirmed))
        #expect(status.contains(.warningIndicatorRequested))
        #expect(!status.contains(.pending))
        #expect(status.setBits.map(\.german) == ["Fehler liegt jetzt vor", "bestätigt und gespeichert", "Warnleuchte angefordert"])
        #expect(DTCStatus.bits.count == 8)
    }

    @Test func udsDTCDisplayAndBytes() {
        let dtc = UDSDTC(high: 0xC1, middle: 0x00, low: 0x87, status: DTCStatus(rawValue: 0x28))
        #expect(dtc.displayCode == "U0100-87")
        #expect(dtc.bytes == [0xC1, 0x00, 0x87])
        #expect(dtc.code.description == "U0100")
    }

    @Test func failureTypesAreDescribed() {
        #expect(FailureType.describe(0x87) == .init(category: "Busnachricht oder Kommunikation", detail: "Nachricht fehlt"))
        #expect(FailureType.describe(0x13).detail == "Stromkreis unterbrochen")
        #expect(FailureType.describe(0x00).detail == "keine Unterart angegeben")
        #expect(FailureType.describe(0xF5) == .init(category: "herstellerspezifisch", detail: nil))
        #expect(FailureType.describe(0xA1).category == "reserviert")
    }
}
