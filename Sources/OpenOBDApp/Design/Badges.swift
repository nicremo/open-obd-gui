import DiagnosticEngine
import OBDCore
import SwiftUI

/// Signal flag of the timing world. The shape encodes the level, so it reads without color too:
/// green and blue plain, yellow plain, black with an orange disc for a technical defect, red plain.
enum Flag: Equatable {
    case clear
    case info
    case caution
    case defect
    case stop

    init(_ severity: Severity?) {
        switch severity {
        case .critical: self = .stop
        case .high: self = .defect
        case .medium: self = .caution
        case .info: self = .info
        case nil: self = .clear
        }
    }

    var meaning: String {
        switch self {
        case .clear: "Grüne Flagge: kein Fehler gespeichert."
        case .info: "Blaue Flagge: Hinweis, kein Handlungsbedarf."
        case .caution: "Gelbe Flagge: beobachten und beim nächsten Werkstattbesuch ansprechen."
        case .defect: "Schwarze Flagge mit orangem Punkt: technischer Defekt, bald in die Werkstatt."
        case .stop: "Rote Flagge: sofort prüfen lassen."
        }
    }
}

struct FlagGlyph: View {
    let flag: Flag
    var width: CGFloat = 14

    var body: some View {
        let height = width * 0.7
        ZStack {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(cloth)
            if flag == .defect {
                Circle().fill(FlagCloth.orange).frame(width: height * 0.62, height: height * 0.62)
            }
        }
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .strokeBorder(flag == .defect ? Palette.textSecondary : Palette.hairlineStrong, lineWidth: flag == .defect ? 0.75 : 0.5))
        .accessibilityHidden(true)
    }

    private var cloth: Color {
        switch flag {
        case .clear: FlagCloth.green
        case .info: FlagCloth.blue
        case .caution: FlagCloth.yellow
        case .defect: FlagCloth.black
        case .stop: FlagCloth.red
        }
    }
}

/// Urgency as a flag plus the word. No capsule, no fill behind the text.
struct SeverityFlag: View {
    let severity: Severity?
    var font: Font = .system(size: 13, weight: .medium)

    var body: some View {
        HStack(spacing: 6) {
            FlagGlyph(flag: Flag(severity))
            Text(severity?.german ?? "frei")
                .font(font)
                .foregroundStyle(Palette.textPrimary)
        }
        .help(Flag(severity).meaning)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dringlichkeit \(severity?.german ?? "keine")")
    }
}

/// Kept as the shared name used by every screen.
struct SeverityBadge: View {
    let severity: Severity

    var body: some View { SeverityFlag(severity: severity) }
}

/// Small inline label: symbol in state color, text. No container.
struct Chip: View {
    let text: String
    var color: Color = Palette.textSecondary
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).imageScale(.small).foregroundStyle(color)
            }
            Text(text).foregroundStyle(color == Palette.textSecondary ? Palette.textSecondary : color).lineLimit(1)
        }
        .font(.obdCaption)
    }
}

/// Shows whether a meaning is a fact (standard, verified) or not.
/// The compact form shows only the symbol and explains itself in the tooltip.
struct ConfidenceBadge: View {
    let confidence: Confidence
    var compact = false

    var body: some View {
        if compact {
            Image(systemName: Self.symbol(confidence))
                .font(.obdLabel)
                .foregroundStyle(Palette.confidence(confidence))
                .help("\(Self.word(confidence)): \(Self.explanation(confidence))")
                .accessibilityLabel(Self.word(confidence))
        } else {
            Chip(text: Self.word(confidence), color: confidence == .community ? Palette.unverifiedText : Palette.confidence(confidence), symbol: Self.symbol(confidence))
                .help(Self.explanation(confidence))
        }
    }

    static func word(_ confidence: Confidence) -> String {
        switch confidence {
        case .standard: "genormt"
        case .verifiedOnVehicle: "am Fahrzeug bestätigt"
        case .community: "unbestätigt"
        case .unknown: "Bedeutung unbekannt"
        }
    }

    static func symbol(_ confidence: Confidence) -> String {
        switch confidence {
        case .standard: "checkmark.seal"
        case .verifiedOnVehicle: "checkmark.seal.fill"
        case .community: "questionmark.circle"
        case .unknown: "questionmark.square.dashed"
        }
    }

    static func explanation(_ confidence: Confidence) -> String {
        switch confidence {
        case .standard: "Bedeutung aus einer Norm (SAE J1979, J2012, ISO 14229)."
        case .verifiedOnVehicle: "Bedeutung an einem echten Fahrzeug geprüft."
        case .community: "Bedeutung aus einer Community-Quelle, nicht geprüft. Nicht als Tatsache behandeln."
        case .unknown: "Für diesen Wert ist keine Bedeutung hinterlegt. Nur die Rohdaten sind sicher."
        }
    }
}

/// State of a trouble code: aktiv, gespeichert, vorläufig, historisch, permanent. Symbol plus word, no pill.
struct StateChip: View {
    let state: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).imageScale(.small)
            Text(state)
        }
        .font(.system(size: 12))
        .foregroundStyle(color)
        .help(help)
    }

    private var symbol: String {
        switch state {
        case "aktiv": "bolt.fill"
        case "gespeichert": "tray.full"
        case "vorläufig": "hourglass"
        case "permanent": "lock"
        default: "clock.arrow.circlepath"
        }
    }

    private var color: Color {
        switch state {
        case "aktiv": Palette.faultText
        default: Palette.textSecondary
        }
    }

    private var help: String {
        switch state {
        case "aktiv": "Der Fehler liegt gerade an."
        case "gespeichert": "Der Fehler ist bestätigt und im Speicher abgelegt."
        case "vorläufig": "Der Fehler trat einmal auf und ist noch nicht bestätigt."
        case "permanent": "Der Fehler lässt sich nicht löschen, bis die Prüfung bestanden ist."
        default: "Der Fehler trat früher auf."
        }
    }
}

/// A DTC typeset like a timing code: the system letter in a box, the number, the failure type dimmed.
struct DTCCodeText: View {
    let displayCode: String
    var size: CGFloat = 15

    var body: some View {
        let parts = displayCode.split(separator: "-", maxSplits: 1).map(String.init)
        let code = parts.first ?? displayCode
        HStack(alignment: .firstTextBaseline, spacing: size * 0.18) {
            Text(String(code.prefix(1)))
                .font(.timing(size * 0.8, .heavy))
                .foregroundStyle(Palette.background)
                .padding(.horizontal, size * 0.18)
                .background(Palette.textPrimary, in: RoundedRectangle(cornerRadius: Radius.tag, style: .continuous))
            Text(String(code.dropFirst()))
                .font(.timing(size, .heavy))
                .foregroundStyle(Palette.textPrimary)
            if parts.count > 1 {
                Text("-\(parts[1])")
                    .font(.timing(size, .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fehlercode \(displayCode)")
    }
}
