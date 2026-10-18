import FordKnowledge
import Foundation
import OBDCore

public struct VINInfo: Sendable, Codable, Equatable {
    public var vin: String
    public var isValid: Bool
    public var wmi: String
    public var manufacturer: String?
    public var manufacturerConfidence: Confidence?
    public var region: String
    /// Positions 4 to 9.
    public var vehicleDescriptor: String
    /// Positions 12 to 17.
    public var serial: String
    public var modelYearCandidates: [Int]
    public var modelYearNote: String
    /// The check digit at position 9 is mandatory only for North America.
    public var checkDigitApplies: Bool
    public var checkDigitValid: Bool?
}

public enum VINDecoder {
    public static func decode(_ vin: String, knowledge: KnowledgeBase) -> VINInfo {
        let characters = Array(vin)
        let valid = OBDVehicleInfo.isValidVIN(vin)
        let northAmerica = characters.first.map { "12345".contains($0) } ?? false
        let wmi = knowledge.wmi(for: vin)
        var years: [Int] = []
        if valid, northAmerica, let base = yearCodes[characters[9]] {
            years = [base, base + 30]
        }
        return VINInfo(
            vin: vin,
            isValid: valid,
            wmi: String(vin.prefix(3)),
            manufacturer: wmi?.manufacturerDE,
            manufacturerConfidence: wmi?.confidence,
            region: characters.first.map(region) ?? "unbekannt",
            vehicleDescriptor: valid ? String(characters[3..<9]) : "",
            serial: valid ? String(characters[11..<17]) : "",
            modelYearCandidates: years,
            modelYearNote: northAmerica
                ? "Modelljahr aus Stelle 10 nach nordamerikanischem Schema, Zyklus von 30 Jahren."
                : "Europäische VINs codieren das Modelljahr nicht verbindlich. Baujahr aus Fahrzeugschein oder Motorsteuergerät ablesen.",
            checkDigitApplies: northAmerica,
            checkDigitValid: valid ? expectedCheckDigit(vin).map { $0 == characters[8] } : nil)
    }

    /// ISO 3779 / 49 CFR 565 check digit for position 9.
    public static func expectedCheckDigit(_ vin: String) -> Character? {
        let characters = Array(vin)
        guard characters.count == 17 else { return nil }
        var sum = 0
        for (index, character) in characters.enumerated() {
            guard let value = transliteration[character] else { return nil }
            sum += value * weights[index]
        }
        let remainder = sum % 11
        return remainder == 10 ? "X" : Character(String(remainder))
    }

    static func region(_ first: Character) -> String {
        switch first {
        case "A"..."H": "Afrika"
        case "J"..."R": "Asien"
        case "S"..."Z": "Europa"
        case "1"..."5": "Nordamerika"
        case "6", "7": "Ozeanien"
        case "8", "9", "0": "Südamerika"
        default: "unbekannt"
        }
    }

    static let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]

    static let transliteration: [Character: Int] = {
        var table: [Character: Int] = [:]
        for digit in 0...9 {
            table[Character(String(digit))] = digit
        }
        let letters: [(Character, Int)] = [
            ("A", 1), ("B", 2), ("C", 3), ("D", 4), ("E", 5), ("F", 6), ("G", 7), ("H", 8),
            ("J", 1), ("K", 2), ("L", 3), ("M", 4), ("N", 5), ("P", 7), ("R", 9),
            ("S", 2), ("T", 3), ("U", 4), ("V", 5), ("W", 6), ("X", 7), ("Y", 8), ("Z", 9),
        ]
        for (letter, value) in letters {
            table[letter] = value
        }
        return table
    }()

    static let yearCodes: [Character: Int] = {
        let codes = Array("ABCDEFGHJKLMNPRSTVWXY123456789")
        var table: [Character: Int] = [:]
        for (offset, code) in codes.enumerated() {
            table[code] = 1980 + offset
        }
        return table
    }()
}
