import Foundation

// Formulas: SAE J1979 service 01, cross-checked against https://en.wikipedia.org/wiki/OBD-II_PIDs (13.10.2026).
extension J1979 {
    static func buildCatalog() -> [PIDDefinition] {
        var list: [PIDDefinition] = []

        list.append(PIDDefinition(pid: 0x01, name: "Monitorstatus seit Fehlerlöschen", category: .diagnostics, byteCount: 4,
                                  formula: "A7: MIL, A0 bis A6: Anzahl DTCs, B3: Zündart, B, C, D: Monitore") { data in
            try ReadinessReport.decode(data, kind: .sinceClear).fields
        })
        list.append(PIDDefinition(pid: 0x02, name: "Auslösender Fehlercode (Freeze Frame)", category: .diagnostics, byteCount: 2,
                                  formula: "Fehlercode aus A und B") { data in
            let code = DTCCode(high: data[0], low: data[1])
            return [DecodedField(label: "Auslösender Fehlercode",
                                 value: code.raw == 0 ? .unavailable("kein Freeze Frame gespeichert") : .text(code.description))]
        })
        list.append(enumeration(0x03, "Kraftstoffsystemstatus", .fuel, labels: ["Kraftstoffsystem 1", "Kraftstoffsystem 2"],
                                table: fuelSystemStatus, formula: "A: System 1, B: System 2 (Bitwert)"))
        list.append(percent(0x04, "Berechnete Motorlast", .engine))
        list.append(temperature(0x05, "Kühlmitteltemperatur"))
        list.append(trim(0x06, "Kurzzeit-Kraftstoffkorrektur Bank 1", .fuel))
        list.append(trim(0x07, "Langzeit-Kraftstoffkorrektur Bank 1", .fuel))
        list.append(trim(0x08, "Kurzzeit-Kraftstoffkorrektur Bank 2", .fuel))
        list.append(trim(0x09, "Langzeit-Kraftstoffkorrektur Bank 2", .fuel))
        list.append(scalar(0x0A, "Kraftstoffdruck (Überdruck)", .fuel, bytes: 1, unit: "kPa", formula: "3 * A") { 3 * $0 })
        list.append(scalar(0x0B, "Saugrohrdruck (absolut)", .air, bytes: 1, unit: "kPa", formula: "A") { $0 })
        list.append(scalar(0x0C, "Motordrehzahl", .engine, bytes: 2, unit: "1/min", formula: "(256 * A + B) / 4") { $0 / 4 })
        list.append(scalar(0x0D, "Fahrzeuggeschwindigkeit", .vehicle, bytes: 1, unit: "km/h", formula: "A") { $0 })
        list.append(scalar(0x0E, "Zündzeitpunkt", .engine, bytes: 1, unit: "° v. OT", formula: "A / 2 - 64") { $0 / 2 - 64 })
        list.append(temperature(0x0F, "Ansauglufttemperatur"))
        list.append(scalar(0x10, "Luftmassenstrom", .air, bytes: 2, unit: "g/s", formula: "(256 * A + B) / 100") { $0 / 100 })
        list.append(percent(0x11, "Drosselklappenstellung", .air))
        list.append(enumeration(0x12, "Sekundärluft-Status", .exhaust, labels: ["Sekundärluft"],
                                table: secondaryAirStatus, formula: "A (Bitwert)"))
        list.append(flags(0x13, "Vorhandene Lambdasonden (2 Bänke)", .exhaust, labels: twoBankSensors,
                          formula: "Bit 0 bis 3: Bank 1 Sensor 1 bis 4, Bit 4 bis 7: Bank 2 Sensor 1 bis 4"))
        for (offset, pid) in (UInt8(0x14)...UInt8(0x1B)).enumerated() {
            list.append(narrowbandOxygen(pid, sensor: offset + 1))
        }
        list.append(enumeration(0x1C, "OBD-Norm des Fahrzeugs", .diagnostics, labels: ["OBD-Norm"],
                                table: obdStandards, formula: "A (Aufzählung)"))
        list.append(flags(0x1D, "Vorhandene Lambdasonden (4 Bänke)", .exhaust, labels: fourBankSensors,
                          formula: "je 2 Bit pro Bank: Bank 1 bis 4, Sensor 1 und 2"))
        list.append(flags(0x1E, "Status Hilfseingänge", .vehicle, labels: ["Nebenabtrieb (PTO) aktiv"], formula: "A0"))
        list.append(scalar(0x1F, "Laufzeit seit Motorstart", .engine, bytes: 2, unit: "s", formula: "256 * A + B") { $0 })
        list.append(scalar(0x21, "Strecke mit Warnleuchte (MIL) an", .diagnostics, bytes: 2, unit: "km", formula: "256 * A + B") { $0 })
        list.append(scalar(0x22, "Kraftstoffverteilerdruck (relativ zum Saugrohr)", .fuel, bytes: 2, unit: "kPa",
                           formula: "0,079 * (256 * A + B)") { $0 * 0.079 })
        list.append(scalar(0x23, "Kraftstoffverteilerdruck (Überdruck, Diesel oder Direkteinspritzung)", .fuel, bytes: 2, unit: "kPa",
                           formula: "10 * (256 * A + B)") { $0 * 10 })
        for (offset, pid) in (UInt8(0x24)...UInt8(0x2B)).enumerated() {
            list.append(widebandVoltage(pid, sensor: offset + 1))
        }
        list.append(percent(0x2C, "AGR-Sollwert", .exhaust))
        list.append(trim(0x2D, "AGR-Abweichung", .exhaust))
        list.append(percent(0x2E, "Tankentlüftung Sollwert", .fuel))
        list.append(percent(0x2F, "Tankfüllstand", .fuel))
        list.append(scalar(0x30, "Warmlaufzyklen seit Fehlerlöschen", .diagnostics, bytes: 1, unit: "", formula: "A") { $0 })
        list.append(scalar(0x31, "Strecke seit Fehlerlöschen", .diagnostics, bytes: 2, unit: "km", formula: "256 * A + B") { $0 })
        list.append(PIDDefinition(pid: 0x32, name: "Dampfdruck Tankentlüftung", category: .fuel, byteCount: 2,
                                  formula: "(256 * A + B) / 4, vorzeichenbehaftet") { data in
            let signed = Int16(bitPattern: UInt16(data[0]) << 8 | UInt16(data[1]))
            return [DecodedField(label: "Dampfdruck Tankentlüftung", value: .number(Double(signed) / 4, unit: "Pa"))]
        })
        list.append(scalar(0x33, "Luftdruck (Umgebung)", .air, bytes: 1, unit: "kPa", formula: "A") { $0 })
        for (offset, pid) in (UInt8(0x34)...UInt8(0x3B)).enumerated() {
            list.append(widebandCurrent(pid, sensor: offset + 1))
        }
        list.append(catalystTemperature(0x3C, "Katalysatortemperatur Bank 1 Sensor 1"))
        list.append(catalystTemperature(0x3D, "Katalysatortemperatur Bank 2 Sensor 1"))
        list.append(catalystTemperature(0x3E, "Katalysatortemperatur Bank 1 Sensor 2"))
        list.append(catalystTemperature(0x3F, "Katalysatortemperatur Bank 2 Sensor 2"))
        list.append(PIDDefinition(pid: 0x41, name: "Monitorstatus dieser Fahrzyklus", category: .diagnostics, byteCount: 4,
                                  formula: "B, C, D: Monitore aktiviert und abgeschlossen") { data in
            try ReadinessReport.decode(data, kind: .thisDriveCycle).fields
        })
        list.append(scalar(0x42, "Steuergerätespannung", .electrical, bytes: 2, unit: "V", formula: "(256 * A + B) / 1000") { $0 / 1000 })
        list.append(scalar(0x43, "Absolute Last", .engine, bytes: 2, unit: "%", formula: "(256 * A + B) * 100 / 255") { $0 * 100 / 255 })
        list.append(scalar(0x44, "Lambda-Sollwert", .exhaust, bytes: 2, unit: "λ", formula: "(256 * A + B) * 2 / 65536") { $0 * 2 / 65536 })
        list.append(percent(0x45, "Relative Drosselklappenstellung", .air))
        list.append(temperature(0x46, "Umgebungstemperatur"))
        list.append(percent(0x47, "Absolute Drosselklappenstellung B", .air))
        list.append(percent(0x48, "Absolute Drosselklappenstellung C", .air))
        list.append(percent(0x49, "Fahrpedalstellung D", .engine))
        list.append(percent(0x4A, "Fahrpedalstellung E", .engine))
        list.append(percent(0x4B, "Fahrpedalstellung F", .engine))
        list.append(percent(0x4C, "Drosselklappensteller Sollwert", .air))
        list.append(scalar(0x4D, "Laufzeit mit Warnleuchte (MIL) an", .diagnostics, bytes: 2, unit: "min", formula: "256 * A + B") { $0 })
        list.append(scalar(0x4E, "Zeit seit Fehlerlöschen", .diagnostics, bytes: 2, unit: "min", formula: "256 * A + B") { $0 })
        list.append(PIDDefinition(pid: 0x4F, name: "Maximalwerte Lambda, Sondenspannung, Sondenstrom, Saugrohrdruck", category: .exhaust,
                                  byteCount: 4, formula: "A, B V, C mA, D * 10 kPa") { data in
            [
                DecodedField(label: "Maximales Lambda", value: .number(Double(data[0]), unit: "λ")),
                DecodedField(label: "Maximale Sondenspannung", value: .number(Double(data[1]), unit: "V")),
                DecodedField(label: "Maximaler Sondenstrom", value: .number(Double(data[2]), unit: "mA")),
                DecodedField(label: "Maximaler Saugrohrdruck", value: .number(Double(data[3]) * 10, unit: "kPa")),
            ]
        })
        list.append(PIDDefinition(pid: 0x50, name: "Maximaler Luftmassenstrom", category: .air, byteCount: 4,
                                  formula: "A * 10 (B, C, D reserviert)") { data in
            [DecodedField(label: "Maximaler Luftmassenstrom", value: .number(Double(data[0]) * 10, unit: "g/s"))]
        })
        list.append(enumeration(0x51, "Kraftstoffart", .fuel, labels: ["Kraftstoffart"], table: fuelTypes, formula: "A (Aufzählung)"))
        list.append(percent(0x52, "Ethanolanteil", .fuel))
        list.append(scalar(0x53, "Dampfdruck Tankentlüftung (absolut)", .fuel, bytes: 2, unit: "kPa", formula: "(256 * A + B) / 200") { $0 / 200 })
        list.append(scalar(0x54, "Dampfdruck Tankentlüftung (erweitert)", .fuel, bytes: 2, unit: "Pa", formula: "256 * A + B - 32767") { $0 - 32767 })
        list.append(pairTrim(0x55, "Kurzzeitkorrektur zweite Lambdasonde", banks: (1, 3)))
        list.append(pairTrim(0x56, "Langzeitkorrektur zweite Lambdasonde", banks: (1, 3)))
        list.append(pairTrim(0x57, "Kurzzeitkorrektur zweite Lambdasonde", banks: (2, 4)))
        list.append(pairTrim(0x58, "Langzeitkorrektur zweite Lambdasonde", banks: (2, 4)))
        list.append(scalar(0x59, "Kraftstoffverteilerdruck (absolut)", .fuel, bytes: 2, unit: "kPa", formula: "10 * (256 * A + B)") { $0 * 10 })
        list.append(percent(0x5A, "Relative Fahrpedalstellung", .engine))
        list.append(percent(0x5B, "Restlebensdauer Hybridbatterie", .electrical))
        list.append(temperature(0x5C, "Motoröltemperatur"))
        list.append(scalar(0x5D, "Einspritzzeitpunkt", .fuel, bytes: 2, unit: "°", formula: "(256 * A + B) / 128 - 210") { $0 / 128 - 210 })
        list.append(scalar(0x5E, "Kraftstoffverbrauch (Motor)", .fuel, bytes: 2, unit: "l/h", formula: "(256 * A + B) / 20") { $0 / 20 })
        list.append(PIDDefinition(pid: 0x5F, name: "Emissionsanforderungen", category: .diagnostics, byteCount: 1,
                                  formula: "A (bitcodiert, als Rohwert)") { data in
            [DecodedField(label: "Emissionsanforderungen", value: .raw(data))]
        })
        list.append(scalar(0x61, "Fahrerwunsch-Motormoment", .engine, bytes: 1, unit: "%", formula: "A - 125") { $0 - 125 })
        list.append(scalar(0x62, "Ist-Motormoment", .engine, bytes: 1, unit: "%", formula: "A - 125") { $0 - 125 })
        list.append(scalar(0x63, "Referenzmoment des Motors", .engine, bytes: 2, unit: "Nm", formula: "256 * A + B") { $0 })
        list.append(PIDDefinition(pid: 0x64, name: "Motormoment-Stützstellen", category: .engine, byteCount: 5,
                                  formula: "A bis E jeweils minus 125") { data in
            ["Leerlauf", "Punkt 1", "Punkt 2", "Punkt 3", "Punkt 4"].enumerated().map { index, label in
                DecodedField(label: "Motormoment \(label)", value: .number(Double(data[index]) - 125, unit: "%"))
            }
        })
        list.append(PIDDefinition(pid: 0x65, name: "Hilfseingänge und -ausgänge", category: .vehicle, byteCount: 2,
                                  formula: "A: unterstützt, B: Zustand (als Rohwert)") { data in
            [DecodedField(label: "Hilfseingänge und -ausgänge", value: .raw(data))]
        })
        list.append(PIDDefinition(pid: 0xA6, name: "Kilometerstand", category: .vehicle, byteCount: 4,
                                  formula: "(A * 2^24 + B * 2^16 + C * 2^8 + D) / 10") { data in
            [DecodedField(label: "Kilometerstand", value: .number(unsigned(data[0..<4]) / 10, unit: "km"))]
        })
        return list
    }

    // MARK: - Builders

    static func unsigned(_ bytes: ArraySlice<UInt8>) -> Double {
        bytes.reduce(0.0) { $0 * 256 + Double($1) }
    }

    static func scalar(_ pid: UInt8, _ name: String, _ category: PIDCategory, bytes: Int, unit: String, formula: String,
                       _ transform: @escaping @Sendable (Double) -> Double) -> PIDDefinition {
        PIDDefinition(pid: pid, name: name, category: category, byteCount: bytes, formula: formula) { data in
            [DecodedField(label: name, value: .number(transform(unsigned(data[0..<bytes])), unit: unit))]
        }
    }

    static func percent(_ pid: UInt8, _ name: String, _ category: PIDCategory) -> PIDDefinition {
        scalar(pid, name, category, bytes: 1, unit: "%", formula: "A * 100 / 255") { $0 * 100 / 255 }
    }

    static func temperature(_ pid: UInt8, _ name: String) -> PIDDefinition {
        scalar(pid, name, .temperature, bytes: 1, unit: "°C", formula: "A - 40") { $0 - 40 }
    }

    static func trim(_ pid: UInt8, _ name: String, _ category: PIDCategory) -> PIDDefinition {
        scalar(pid, name, category, bytes: 1, unit: "%", formula: "A * 100 / 128 - 100") { $0 * 100 / 128 - 100 }
    }

    static func catalystTemperature(_ pid: UInt8, _ name: String) -> PIDDefinition {
        scalar(pid, name, .temperature, bytes: 2, unit: "°C", formula: "(256 * A + B) / 10 - 40") { $0 / 10 - 40 }
    }

    static func enumeration(_ pid: UInt8, _ name: String, _ category: PIDCategory, labels: [String], table: [Int: String],
                            formula: String) -> PIDDefinition {
        PIDDefinition(pid: pid, name: name, category: category, byteCount: labels.count, formula: formula) { data in
            labels.enumerated().map { index, label in
                let code = Int(data[index])
                return DecodedField(label: label, value: .enumeration(code: code, label: table[code] ?? "unbekannter Wert \(code)"))
            }
        }
    }

    static func flags(_ pid: UInt8, _ name: String, _ category: PIDCategory, labels: [String], formula: String) -> PIDDefinition {
        PIDDefinition(pid: pid, name: name, category: category, byteCount: 1, formula: formula) { data in
            let flags = labels.enumerated().map { index, label in
                MeasuredValue.Flag(label: label, isSet: data[0] & (1 << UInt8(index)) != 0)
            }
            return [DecodedField(label: name, value: .flags(flags))]
        }
    }

    // Sensor numbering follows PID order. The bank mapping depends on PID 13 or 1D.
    static func narrowbandOxygen(_ pid: UInt8, sensor: Int) -> PIDDefinition {
        PIDDefinition(pid: pid, name: "Lambdasonde \(sensor): Spannung und Kurzzeitkorrektur", category: .exhaust, byteCount: 2,
                      formula: "A / 200 V, B * 100 / 128 - 100 % (B = FF: nicht genutzt)") { data in
            [
                DecodedField(label: "Lambdasonde \(sensor) Spannung", value: .number(Double(data[0]) / 200, unit: "V")),
                DecodedField(label: "Lambdasonde \(sensor) Kurzzeitkorrektur",
                             value: data[1] == 0xFF
                                 ? .unavailable("nicht für die Gemischkorrektur genutzt")
                                 : .number(Double(data[1]) * 100 / 128 - 100, unit: "%")),
            ]
        }
    }

    static func widebandVoltage(_ pid: UInt8, sensor: Int) -> PIDDefinition {
        PIDDefinition(pid: pid, name: "Lambdasonde \(sensor): Lambda und Spannung", category: .exhaust, byteCount: 4,
                      formula: "(256 * A + B) * 2 / 65536, (256 * C + D) * 8 / 65536 V") { data in
            [
                DecodedField(label: "Lambdasonde \(sensor) Lambda", value: .number(unsigned(data[0..<2]) * 2 / 65536, unit: "λ")),
                DecodedField(label: "Lambdasonde \(sensor) Spannung", value: .number(unsigned(data[2..<4]) * 8 / 65536, unit: "V")),
            ]
        }
    }

    static func widebandCurrent(_ pid: UInt8, sensor: Int) -> PIDDefinition {
        PIDDefinition(pid: pid, name: "Lambdasonde \(sensor): Lambda und Strom", category: .exhaust, byteCount: 4,
                      formula: "(256 * A + B) * 2 / 65536, (256 * C + D) / 256 - 128 mA") { data in
            [
                DecodedField(label: "Lambdasonde \(sensor) Lambda", value: .number(unsigned(data[0..<2]) * 2 / 65536, unit: "λ")),
                DecodedField(label: "Lambdasonde \(sensor) Strom", value: .number(unsigned(data[2..<4]) / 256 - 128, unit: "mA")),
            ]
        }
    }

    static func pairTrim(_ pid: UInt8, _ name: String, banks: (Int, Int)) -> PIDDefinition {
        PIDDefinition(pid: pid, name: "\(name) Bank \(banks.0) und \(banks.1)", category: .fuel, byteCount: 2,
                      formula: "A und B jeweils * 100 / 128 - 100") { data in
            [
                DecodedField(label: "\(name) Bank \(banks.0)", value: .number(Double(data[0]) * 100 / 128 - 100, unit: "%")),
                DecodedField(label: "\(name) Bank \(banks.1)", value: .number(Double(data[1]) * 100 / 128 - 100, unit: "%")),
            ]
        }
    }

    // MARK: - Tables

    static let twoBankSensors = (1...2).flatMap { bank in (1...4).map { "Bank \(bank) Sensor \($0)" } }
    static let fourBankSensors = (1...4).flatMap { bank in (1...2).map { "Bank \(bank) Sensor \($0)" } }

    static let fuelSystemStatus: [Int: String] = [
        0: "nicht aktiv oder nicht vorhanden",
        1: "Steuerung offen: Motor noch nicht warm",
        2: "Regelung geschlossen: Lambdasonde regelt das Gemisch",
        4: "Steuerung offen: Last oder Schubabschaltung",
        8: "Steuerung offen: Systemfehler",
        16: "Regelung geschlossen, aber Fehler in der Rückführung",
    ]

    static let secondaryAirStatus: [Int: String] = [
        0: "nicht aktiv",
        1: "vor dem Katalysator",
        2: "nach dem Katalysator",
        4: "von außen oder aus",
        8: "Pumpe zu Diagnosezwecken an",
    ]

    static let obdStandards: [Int: String] = [
        1: "OBD-II (CARB)", 2: "OBD (EPA)", 3: "OBD und OBD-II", 4: "OBD-I", 5: "nicht OBD-konform",
        6: "EOBD (Europa)", 7: "EOBD und OBD-II", 8: "EOBD und OBD", 9: "EOBD, OBD und OBD-II",
        10: "JOBD (Japan)", 11: "JOBD und OBD-II", 12: "JOBD und EOBD", 13: "JOBD, EOBD und OBD-II",
        17: "Engine Manufacturer Diagnostics (EMD)", 18: "EMD+", 19: "Heavy Duty OBD (Teilumfang)",
        20: "Heavy Duty OBD", 21: "World Wide Harmonized OBD (WWH-OBD)",
        23: "Heavy Duty Euro OBD Stufe I ohne NOx-Kontrolle", 24: "Heavy Duty Euro OBD Stufe I mit NOx-Kontrolle",
        25: "Heavy Duty Euro OBD Stufe II ohne NOx-Kontrolle", 26: "Heavy Duty Euro OBD Stufe II mit NOx-Kontrolle",
        28: "Brasilien OBD Phase 1", 29: "Brasilien OBD Phase 2", 30: "Korea OBD", 31: "Indien OBD I",
        32: "Indien OBD II", 33: "Heavy Duty Euro OBD Stufe VI",
    ]

    static let fuelTypes: [Int: String] = [
        0: "nicht verfügbar", 1: "Benzin", 2: "Methanol", 3: "Ethanol", 4: "Diesel", 5: "Autogas (LPG)",
        6: "Erdgas (CNG)", 7: "Propan", 8: "Elektrisch", 9: "Bivalent: Benzin", 10: "Bivalent: Methanol",
        11: "Bivalent: Ethanol", 12: "Bivalent: LPG", 13: "Bivalent: CNG", 14: "Bivalent: Propan",
        15: "Bivalent: Elektrisch", 16: "Bivalent: Elektro und Verbrenner", 17: "Hybrid Benzin",
        18: "Hybrid Ethanol", 19: "Hybrid Diesel", 20: "Hybrid elektrisch", 21: "Hybrid Elektro und Verbrenner",
        22: "Hybrid regenerativ", 23: "Bivalent: Diesel",
    ]
}
