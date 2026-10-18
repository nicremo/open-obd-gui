import Testing
@testable import OBDCore

struct PIDVector: Sendable, CustomTestStringConvertible {
    let pid: UInt8
    let bytes: [UInt8]
    let value: Double
    let unit: String
    var testDescription: String { "PID \(Hex.byteString(pid)) [\(Hex.encode(bytes, separator: " "))]" }
}

@Suite struct J1979Tests {
    @Test(arguments: [
        PIDVector(pid: 0x04, bytes: [0xFF], value: 100, unit: "%"),
        PIDVector(pid: 0x05, bytes: [0x5A], value: 50, unit: "°C"),
        PIDVector(pid: 0x05, bytes: [0x00], value: -40, unit: "°C"),
        PIDVector(pid: 0x06, bytes: [0x80], value: 0, unit: "%"),
        PIDVector(pid: 0x07, bytes: [0x00], value: -100, unit: "%"),
        PIDVector(pid: 0x0A, bytes: [0x64], value: 300, unit: "kPa"),
        PIDVector(pid: 0x0B, bytes: [0x65], value: 101, unit: "kPa"),
        PIDVector(pid: 0x0C, bytes: [0x1A, 0xF8], value: 1726, unit: "1/min"),
        PIDVector(pid: 0x0D, bytes: [0x32], value: 50, unit: "km/h"),
        PIDVector(pid: 0x0E, bytes: [0x80], value: 0, unit: "° v. OT"),
        PIDVector(pid: 0x0F, bytes: [0x28], value: 0, unit: "°C"),
        PIDVector(pid: 0x10, bytes: [0x01, 0xF4], value: 5, unit: "g/s"),
        PIDVector(pid: 0x11, bytes: [0x33], value: 20, unit: "%"),
        PIDVector(pid: 0x1F, bytes: [0x01, 0x2C], value: 300, unit: "s"),
        PIDVector(pid: 0x21, bytes: [0x00, 0x0A], value: 10, unit: "km"),
        PIDVector(pid: 0x22, bytes: [0x03, 0xE8], value: 79, unit: "kPa"),
        PIDVector(pid: 0x23, bytes: [0x0B, 0xB8], value: 30000, unit: "kPa"),
        PIDVector(pid: 0x2C, bytes: [0xFF], value: 100, unit: "%"),
        PIDVector(pid: 0x2D, bytes: [0x80], value: 0, unit: "%"),
        PIDVector(pid: 0x2F, bytes: [0x80], value: 50.196, unit: "%"),
        PIDVector(pid: 0x30, bytes: [0x05], value: 5, unit: ""),
        PIDVector(pid: 0x31, bytes: [0x01, 0x00], value: 256, unit: "km"),
        PIDVector(pid: 0x32, bytes: [0xFF, 0xFC], value: -1, unit: "Pa"),
        PIDVector(pid: 0x33, bytes: [0x63], value: 99, unit: "kPa"),
        PIDVector(pid: 0x3C, bytes: [0x10, 0x9A], value: 385, unit: "°C"),
        PIDVector(pid: 0x42, bytes: [0x31, 0x2C], value: 12.588, unit: "V"),
        PIDVector(pid: 0x43, bytes: [0x00, 0xFF], value: 100, unit: "%"),
        PIDVector(pid: 0x44, bytes: [0x80, 0x00], value: 1, unit: "λ"),
        PIDVector(pid: 0x46, bytes: [0x32], value: 10, unit: "°C"),
        PIDVector(pid: 0x49, bytes: [0x33], value: 20, unit: "%"),
        PIDVector(pid: 0x4D, bytes: [0x00, 0x3C], value: 60, unit: "min"),
        PIDVector(pid: 0x4E, bytes: [0x01, 0x00], value: 256, unit: "min"),
        PIDVector(pid: 0x50, bytes: [0x19, 0x00, 0x00, 0x00], value: 250, unit: "g/s"),
        PIDVector(pid: 0x53, bytes: [0x4E, 0x20], value: 100, unit: "kPa"),
        PIDVector(pid: 0x54, bytes: [0x80, 0x00], value: 1, unit: "Pa"),
        PIDVector(pid: 0x59, bytes: [0x00, 0x64], value: 1000, unit: "kPa"),
        PIDVector(pid: 0x5C, bytes: [0x82], value: 90, unit: "°C"),
        PIDVector(pid: 0x5D, bytes: [0x69, 0x00], value: 0, unit: "°"),
        PIDVector(pid: 0x5E, bytes: [0x00, 0x64], value: 5, unit: "l/h"),
        PIDVector(pid: 0x61, bytes: [0x7D], value: 0, unit: "%"),
        PIDVector(pid: 0x62, bytes: [0xAF], value: 50, unit: "%"),
        PIDVector(pid: 0x63, bytes: [0x01, 0x90], value: 400, unit: "Nm"),
        PIDVector(pid: 0xA6, bytes: [0x00, 0x01, 0xE2, 0x40], value: 12345.6, unit: "km"),
    ])
    func scalarFormulas(_ vector: PIDVector) throws {
        let fields = try J1979.decode(pid: vector.pid, data: vector.bytes)
        let field = try #require(fields.first)
        guard case .number(let value, let unit) = field.value else {
            Issue.record("PID \(Hex.byteString(vector.pid)) liefert keine Zahl: \(field.value)")
            return
        }
        #expect(abs(value - vector.value) < 0.0005)
        #expect(unit == vector.unit)
    }

    @Test func narrowbandOxygenSensor() throws {
        let fields = try J1979.decode(pid: 0x14, data: [0x5A, 0x80])
        #expect(fields.count == 2)
        #expect(fields[0].value == .number(0.45, unit: "V"))
        #expect(fields[1].value == .number(0, unit: "%"))
        let unused = try J1979.decode(pid: 0x15, data: [0x5A, 0xFF])
        #expect(unused[1].value == .unavailable("nicht für die Gemischkorrektur genutzt"))
    }

    @Test func widebandSensors() throws {
        let voltage = try J1979.decode(pid: 0x24, data: [0x80, 0x00, 0x80, 0x00])
        #expect(voltage[0].value == .number(1, unit: "λ"))
        #expect(voltage[1].value == .number(4, unit: "V"))
        let current = try J1979.decode(pid: 0x34, data: [0x80, 0x00, 0x80, 0x00])
        #expect(current[0].value == .number(1, unit: "λ"))
        #expect(current[1].value == .number(0, unit: "mA"))
    }

    @Test func enumerations() throws {
        #expect(try J1979.decode(pid: 0x1C, data: [0x06])[0].value == .enumeration(code: 6, label: "EOBD (Europa)"))
        #expect(try J1979.decode(pid: 0x51, data: [0x04])[0].value == .enumeration(code: 4, label: "Diesel"))
        #expect(try J1979.decode(pid: 0x51, data: [0x63])[0].value == .enumeration(code: 99, label: "unbekannter Wert 99"))
        let fuelSystem = try J1979.decode(pid: 0x03, data: [0x02, 0x00])
        #expect(fuelSystem[0].value == .enumeration(code: 2, label: "Regelung geschlossen: Lambdasonde regelt das Gemisch"))
        #expect(fuelSystem[1].value == .enumeration(code: 0, label: "nicht aktiv oder nicht vorhanden"))
    }

    @Test func oxygenSensorPresenceFlags() throws {
        guard case .flags(let flags) = try J1979.decode(pid: 0x13, data: [0x03])[0].value else {
            Issue.record("PID 13 muss Flags liefern")
            return
        }
        #expect(flags.filter(\.isSet).map(\.label) == ["Bank 1 Sensor 1", "Bank 1 Sensor 2"])
        #expect(flags.count == 8)
    }

    @Test func freezeFrameTriggerCode() throws {
        #expect(try J1979.decode(pid: 0x02, data: [0x04, 0x01])[0].value == .text("P0401"))
        #expect(try J1979.decode(pid: 0x02, data: [0x00, 0x00])[0].value == .unavailable("kein Freeze Frame gespeichert"))
    }

    @Test func torqueAndMaximumValues() throws {
        let torque = try J1979.decode(pid: 0x64, data: [0x7D, 0x7E, 0x7F, 0x80, 0x81])
        #expect(torque.map(\.value) == [0, 1, 2, 3, 4].map { MeasuredValue.number(Double($0), unit: "%") })
        let maxima = try J1979.decode(pid: 0x4F, data: [0x02, 0x08, 0x10, 0x19])
        #expect(maxima[3].value == .number(250, unit: "kPa"))
    }

    @Test func supportBitmaskFollowsJ1979Example() throws {
        let supported = try J1979.supportedPIDs(base: 0x00, mask: [0xBE, 0x1F, 0xA8, 0x13])
        #expect(supported == [0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x13, 0x15, 0x1C, 0x1F, 0x20])
        #expect(try J1979.supportedPIDs(base: 0xA0, mask: [0x04, 0x00, 0x00, 0x00]) == [0xA6])
        #expect(throws: OBDError.self) { try J1979.supportedPIDs(base: 0x00, mask: [0xBE]) }
        #expect(throws: OBDError.self) { try J1979.supportedPIDs(base: 0x0C, mask: [0, 0, 0, 0]) }
    }

    @Test func supportQueries() {
        #expect(J1979.supportQueryPIDs == [0x00, 0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0])
        #expect(J1979.isSupportQuery(0x40))
        #expect(!J1979.isSupportQuery(0x41))
        #expect(!J1979.isSupportQuery(0xE0))
    }

    @Test func shortDataThrowsAndUnknownPIDIsRaw() throws {
        #expect(throws: OBDError.self) { try J1979.decode(pid: 0x0C, data: [0x1A]) }
        #expect(try J1979.decode(pid: 0x7A, data: [0x01, 0x02]) == [DecodedField(label: "PID 7A", value: .raw([0x01, 0x02]))])
    }

    @Test func everyDefinitionDecodesZeroBytesAndIsDescribed() throws {
        #expect(J1979.allDefinitions.count >= 85)
        for definition in J1979.allDefinitions {
            #expect(!definition.name.isEmpty)
            #expect(!definition.formula.isEmpty)
            #expect(!definition.formula.contains("\u{2013}") && !definition.formula.contains("\u{2014}"))
            let fields = try J1979.decode(pid: definition.pid, data: Array(repeating: 0, count: definition.byteCount))
            #expect(!fields.isEmpty)
        }
    }

    @Test func readinessSparkIgnition() throws {
        let report = try ReadinessReport.decode([0x81, 0x07, 0x65, 0x04], kind: .sinceClear)
        #expect(report.milOn == true)
        #expect(report.storedDTCCount == 1)
        #expect(report.ignition == .spark)
        #expect(report.supportedMonitors.map(\.name) == ["Fehlzündungen", "Kraftstoffsystem", "Bauteile", "Katalysator", "Tankentlüftung", "Lambdasonde", "Lambdasondenheizung"])
        #expect(report.incompleteMonitors.map(\.name) == ["Tankentlüftung"])
        #expect(!report.isReady)
    }

    @Test func readinessCompressionIgnition() throws {
        let report = try ReadinessReport.decode([0x00, 0x0F, 0xE9, 0x48], kind: .sinceClear)
        #expect(report.milOn == false)
        #expect(report.ignition == .compression)
        #expect(report.supportedMonitors.map(\.name) == ["Fehlzündungen", "Kraftstoffsystem", "Bauteile", "NMHC-Katalysator", "Ladedruck", "Abgassensor", "Partikelfilter", "AGR und/oder variable Ventilsteuerung"])
        #expect(report.incompleteMonitors.map(\.name) == ["Ladedruck", "Partikelfilter"])
    }

    @Test func readinessThisDriveCycleHasNoMIL() throws {
        let report = try ReadinessReport.decode([0x00, 0x07, 0x01, 0x00], kind: .thisDriveCycle)
        #expect(report.milOn == nil)
        #expect(report.storedDTCCount == nil)
        #expect(report.isReady)
        #expect(throws: OBDError.self) { try ReadinessReport.decode([0x00, 0x07], kind: .sinceClear) }
    }

    @Test func readinessAsFields() throws {
        let fields = try J1979.decode(pid: 0x01, data: [0x81, 0x07, 0x65, 0x04])
        #expect(fields[0] == DecodedField(label: "Motorkontrollleuchte (MIL)", value: .enumeration(code: 1, label: "an")))
        #expect(fields[1] == DecodedField(label: "Anzahl emissionsrelevanter Fehlercodes", value: .number(1, unit: "")))
        #expect(fields.contains(DecodedField(label: "Monitor Tankentlüftung", value: .text("nicht abgeschlossen"))))
    }
}
