import Foundation

/// OBD readiness monitors from PID 01 (since clear) or PID 41 (this drive cycle).
public struct ReadinessReport: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case sinceClear
        case thisDriveCycle
    }

    public enum Ignition: String, Sendable, Codable {
        case spark
        case compression

        public var german: String {
            switch self {
            case .spark: "Fremdzündung (Benziner)"
            case .compression: "Selbstzündung (Diesel)"
            }
        }
    }

    public struct Monitor: Sendable, Equatable, Codable {
        public let name: String
        public let continuous: Bool
        /// PID 01: supported by the vehicle. PID 41: enabled in this drive cycle.
        public let supported: Bool
        public let complete: Bool

        public var stateGerman: String {
            guard supported else { return "nicht unterstützt" }
            return complete ? "abgeschlossen" : "nicht abgeschlossen"
        }
    }

    public let kind: Kind
    public let milOn: Bool?
    public let storedDTCCount: Int?
    public let ignition: Ignition
    public let monitors: [Monitor]

    public var supportedMonitors: [Monitor] { monitors.filter(\.supported) }
    public var incompleteMonitors: [Monitor] { monitors.filter { $0.supported && !$0.complete } }
    public var isReady: Bool { incompleteMonitors.isEmpty }

    static let continuousNames = ["Fehlzündungen", "Kraftstoffsystem", "Bauteile"]
    static let sparkNames: [String?] = [
        "Katalysator", "Beheizter Katalysator", "Tankentlüftung", "Sekundärluftsystem",
        "Klimaanlage bzw. Benzinpartikelfilter (je nach Normstand)", "Lambdasonde", "Lambdasondenheizung",
        "AGR und/oder variable Ventilsteuerung",
    ]
    static let compressionNames: [String?] = [
        "NMHC-Katalysator", "NOx-Nachbehandlung", nil, "Ladedruck", nil, "Abgassensor", "Partikelfilter",
        "AGR und/oder variable Ventilsteuerung",
    ]

    public static func decode(_ data: [UInt8], kind: Kind) throws -> ReadinessReport {
        guard data.count >= 4 else {
            throw OBDError.malformedResponse("Readiness erwartet 4 Bytes, erhalten \(data.count)")
        }
        let a = data[0], b = data[1], c = data[2], d = data[3]
        let ignition: Ignition = b & 0x08 != 0 ? .compression : .spark
        var monitors: [Monitor] = []
        for (bit, name) in continuousNames.enumerated() {
            monitors.append(Monitor(name: name, continuous: true,
                                    supported: b & (1 << UInt8(bit)) != 0,
                                    complete: b & (1 << UInt8(bit + 4)) == 0))
        }
        for (bit, name) in (ignition == .spark ? sparkNames : compressionNames).enumerated() {
            let supported = c & (1 << UInt8(bit)) != 0
            let complete = d & (1 << UInt8(bit)) == 0
            if let name {
                monitors.append(Monitor(name: name, continuous: false, supported: supported, complete: complete))
            } else if supported {
                monitors.append(Monitor(name: "Reserviertes Bit \(bit)", continuous: false, supported: true, complete: complete))
            }
        }
        return ReadinessReport(
            kind: kind,
            milOn: kind == .sinceClear ? a & 0x80 != 0 : nil,
            storedDTCCount: kind == .sinceClear ? Int(a & 0x7F) : nil,
            ignition: ignition,
            monitors: monitors
        )
    }

    public var fields: [DecodedField] {
        var result: [DecodedField] = []
        if let milOn {
            result.append(DecodedField(label: "Motorkontrollleuchte (MIL)", value: .enumeration(code: milOn ? 1 : 0, label: milOn ? "an" : "aus")))
        }
        if let storedDTCCount {
            result.append(DecodedField(label: "Anzahl emissionsrelevanter Fehlercodes", value: .number(Double(storedDTCCount), unit: "")))
        }
        result.append(DecodedField(label: "Zündart", value: .enumeration(code: ignition == .spark ? 0 : 1, label: ignition.german)))
        for monitor in supportedMonitors {
            result.append(DecodedField(label: "Monitor \(monitor.name)", value: .text(monitor.stateGerman)))
        }
        return result
    }
}
