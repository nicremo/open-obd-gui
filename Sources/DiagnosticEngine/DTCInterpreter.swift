import FordKnowledge
import Foundation
import OBDCore

public enum Severity: String, Sendable, Codable, CaseIterable, Comparable {
    case info
    case medium
    case high
    case critical

    public var german: String {
        switch self {
        case .info: "Info"
        case .medium: "Mittel"
        case .high: "Hoch"
        case .critical: "Kritisch"
        }
    }

    var rank: Int {
        switch self {
        case .info: 0
        case .medium: 1
        case .high: 2
        case .critical: 3
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
}

/// One trouble code as shown to people and agents: structure, texts, state, urgency and raw facts.
public struct ReportDTC: Sendable, Codable, Equatable, Identifiable {
    public enum Source: String, Sendable, Codable {
        case obdStored = "obd-stored"
        case obdPending = "obd-pending"
        case obdPermanent = "obd-permanent"
        case uds

        public var german: String {
            switch self {
            case .obdStored: "OBD gespeichert (Dienst 03)"
            case .obdPending: "OBD vorläufig (Dienst 07)"
            case .obdPermanent: "OBD permanent (Dienst 0A)"
            case .uds: "Fehlerspeicher des Steuergeräts (UDS 19 02)"
            }
        }
    }

    public var id: String
    public var module: String
    public var code: String
    public var failureType: String?
    public var displayCode: String
    public var source: Source
    public var statusByte: UInt8?
    public var statusLabels: [String]
    public var state: String
    public var system: String
    public var origin: String
    public var subsystem: String?
    public var failureTypeCategory: String?
    public var failureTypeDetail: String?
    public var title: String?
    public var titleSource: String?
    public var titleConfidence: Confidence?
    public var explanation: DTCExplanation?
    public var severity: Severity
    public var severityReasons: [String]
    public var snapshotHex: String?
    public var extendedDataHex: String?
}

public struct DTCAssessment: Sendable, Equatable {
    public let severity: Severity
    public let reasons: [String]
    public let state: String
}

public enum DTCInterpreter {
    public static func interpret(_ dtc: UDSDTC, module: UInt32, knowledge: KnowledgeBase) -> ReportDTC {
        entry(code: dtc.code, module: module, source: .uds, failureType: dtc.failureType,
              statusByte: dtc.status.rawValue, statusLabels: dtc.status.setBits.map(\.german),
              assessment: assess(code: dtc.code, status: dtc.status), knowledge: knowledge)
    }

    /// `ecu` is the OBD responder (0x7E8 to 0x7EF). The entry is filed under its physical request address (ISO 15765-4: response minus 8),
    /// so OBD and UDS entries of the same control module share one module identifier.
    public static func interpret(obd code: DTCCode, source: ReportDTC.Source, ecu: UInt32, milOn: Bool, knowledge: KnowledgeBase) -> ReportDTC {
        entry(code: code, module: (0x7E8...0x7EF).contains(ecu) ? ecu - 8 : ecu, source: source, failureType: nil, statusByte: nil, statusLabels: [source.german],
              assessment: assessOBD(code: code, source: source, milOn: milOn), knowledge: knowledge)
    }

    public static func assess(code: DTCCode, status: DTCStatus) -> DTCAssessment {
        let active = status.contains(.testFailed)
        let confirmed = status.contains(.confirmed)
        let pending = status.contains(.pending)
        let warning = status.contains(.warningIndicatorRequested)
        let history = status.contains(.testFailedSinceLastClear)
        let state = active ? "aktiv" : confirmed ? "gespeichert" : pending ? "vorläufig" : history ? "historisch" : "ohne Fehlerbits"

        var reasons: [String] = []
        if active { reasons.append("Der Fehler liegt jetzt vor.") }
        if confirmed { reasons.append("Der Fehler ist bestätigt und gespeichert.") }
        if pending { reasons.append("Der Fehler ist vorläufig erkannt.") }
        if warning { reasons.append("Das Steuergerät fordert eine Warnleuchte an.") }

        let severity: Severity
        if active && warning && isSafetyCritical(code) {
            severity = .critical
            reasons.append("Betroffen ist ein sicherheitsrelevantes System (Bremse, Airbag oder Fehlzündungen).")
        } else if confirmed && warning {
            severity = .high
        } else if confirmed || active || pending {
            severity = .medium
        } else {
            severity = .info
            reasons.append(history
                ? "Der Fehler trat seit dem letzten Löschen auf, liegt aber nicht mehr vor."
                : "Es sind keine Fehlerbits gesetzt.")
        }
        return DTCAssessment(severity: severity, reasons: reasons, state: state)
    }

    public static func assessOBD(code: DTCCode, source: ReportDTC.Source, milOn: Bool) -> DTCAssessment {
        switch source {
        case .obdStored:
            if milOn && isSafetyCritical(code) {
                return DTCAssessment(severity: .critical, reasons: ["Gespeicherter Abgasfehler bei leuchtender Motorkontrollleuchte.",
                                                                    "Fehlzündungen können den Katalysator schädigen."], state: "gespeichert")
            }
            if milOn {
                return DTCAssessment(severity: .high, reasons: ["Gespeicherter Abgasfehler, die Motorkontrollleuchte ist an."], state: "gespeichert")
            }
            return DTCAssessment(severity: .medium, reasons: ["Gespeicherter Abgasfehler."], state: "gespeichert")
        case .obdPending:
            return DTCAssessment(severity: .medium, reasons: ["Vorläufig erkannt, noch nicht bestätigt."], state: "vorläufig")
        case .obdPermanent:
            return DTCAssessment(severity: .medium, reasons: ["Permanenter Eintrag. Er verschwindet erst, wenn das Steuergerät die Reparatur selbst bestätigt hat."], state: "permanent")
        case .uds:
            return assess(code: code, status: [])
        }
    }

    /// Brakes (C0xxx), airbag (B00xx) and misfire (P0300 to P030C).
    static func isSafetyCritical(_ code: DTCCode) -> Bool {
        switch code.system {
        case .chassis: code.firstDigit == 0
        case .body: code.firstDigit == 0 && code.secondDigit == 0
        case .powertrain: (0x0300...0x030C).contains(code.raw)
        case .network: false
        }
    }

    static func entry(code: DTCCode, module: UInt32, source: ReportDTC.Source, failureType: UInt8?, statusByte: UInt8?,
                      statusLabels: [String], assessment: DTCAssessment, knowledge: KnowledgeBase) -> ReportDTC {
        let title = knowledge.title(for: code)
        let failure = failureType.map(FailureType.describe)
        let moduleHex = Hex.canID(module, extended: false)
        let display = failureType.map { "\(code)-\(Hex.byteString($0))" } ?? code.description
        return ReportDTC(
            id: "\(moduleHex)-\(display)-\(source.rawValue)",
            module: moduleHex,
            code: code.description,
            failureType: failureType.map(Hex.byteString),
            displayCode: display,
            source: source,
            statusByte: statusByte,
            statusLabels: statusLabels,
            state: assessment.state,
            system: code.system.german,
            origin: code.origin.german,
            subsystem: code.subsystemGerman,
            failureTypeCategory: failure?.category,
            failureTypeDetail: failure?.detail,
            title: title?.titleDE,
            titleSource: title?.source,
            titleConfidence: title?.confidence,
            explanation: knowledge.explanation(for: code),
            severity: assessment.severity,
            severityReasons: assessment.reasons,
            snapshotHex: nil,
            extendedDataHex: nil)
    }
}
