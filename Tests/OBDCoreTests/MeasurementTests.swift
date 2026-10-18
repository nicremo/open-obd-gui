import Foundation
import Testing
@testable import OBDCore

@Suite struct MeasurementTests {
    @Test func displayTextUsesGermanNumberFormat() {
        #expect(MeasuredValue.number(12.588, unit: "V").displayText == "12,588 V")
        #expect(MeasuredValue.number(1726, unit: "1/min").displayText == "1726 1/min")
        #expect(MeasuredValue.number(-1, unit: "Pa").displayText == "-1 Pa")
        #expect(MeasuredValue.number(3, unit: "").displayText == "3")
        #expect(MeasuredValue.enumeration(code: 4, label: "Diesel").displayText == "Diesel")
        #expect(MeasuredValue.flags([.init(label: "A", isSet: true), .init(label: "B", isSet: false)]).displayText == "A")
        #expect(MeasuredValue.flags([.init(label: "A", isSet: false)]).displayText == "keine")
        #expect(MeasuredValue.raw([0x01, 0xAB]).displayText == "01 AB")
        #expect(MeasuredValue.number(5, unit: "km").numericValue == 5)
        #expect(MeasuredValue.text("x").numericValue == nil)
    }

    @Test(arguments: [
        MeasuredValue.number(1.5, unit: "V"), .text("WF0"), .enumeration(code: 6, label: "EOBD"),
        .flags([.init(label: "Bank 1 Sensor 1", isSet: true)]), .unavailable("nicht genutzt"), .raw([0xDE, 0xAD]),
    ])
    func valuesRoundTripThroughJSON(_ value: MeasuredValue) throws {
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(MeasuredValue.self, from: data) == value)
    }

    @Test func numberEncodesWithKindValueAndUnit() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(MeasuredValue.number(50, unit: "°C")), as: UTF8.self)
        #expect(json == "{\"kind\":\"number\",\"unit\":\"°C\",\"value\":50}")
    }

    @Test func unknownKindFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MeasuredValue.self, from: Data("{\"kind\":\"magic\"}".utf8))
        }
    }

    @Test func confidenceSeparatesFactsFromHints() {
        #expect(Confidence.standard.isFact)
        #expect(Confidence.verifiedOnVehicle.isFact)
        #expect(!Confidence.community.isFact)
        #expect(!Confidence.unknown.isFact)
        #expect(Confidence.verifiedOnVehicle.rawValue == "verified-on-vehicle")
    }

    @Test func measurementRoundTrips() throws {
        let measurement = MeasurementRecord(
            id: "7E8:01:0C",
            name: "Motordrehzahl",
            fields: [DecodedField(label: "Motordrehzahl", value: .number(1726, unit: "1/min"))],
            rawHex: "1AF8",
            provenance: Provenance(ecu: "7E8", bus: .hsCAN, requestHex: "010C", responseHex: "410C1AF8", timestamp: Date(timeIntervalSince1970: 0)),
            definition: DefinitionReference(reference: "SAE J1979 Dienst 01, PID 0C", formula: "(256 * A + B) / 4", confidence: .standard)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(MeasurementRecord.self, from: encoder.encode(measurement)) == measurement)
        #expect(measurement.primaryValue == .number(1726, unit: "1/min"))
        #expect(BusKind.msCAN.shortName == "MS-CAN")
    }
}
