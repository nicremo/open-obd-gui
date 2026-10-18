import SwiftUI

/// States a value can be in besides a valid reading.
enum ValueState: Equatable {
    case notRead
    case noResponse
    case unsupported
    case rejected(String)
    case invalid
    case stale(Date)
    case paused
    case live

    var word: String {
        switch self {
        case .notRead: "nicht gelesen"
        case .noResponse: "keine Antwort"
        case .unsupported: "nicht unterstützt"
        case .rejected(let reason): "abgelehnt: \(reason)"
        case .invalid: "ungültig"
        case .stale(let date): "zuletzt \(Fmt.time(date))"
        case .paused: "Pausiert"
        case .live: "Live"
        }
    }

    var symbol: String {
        switch self {
        case .notRead: "circle.dashed"
        case .noResponse: "antenna.radiowaves.left.and.right.slash"
        case .unsupported: "nosign"
        case .rejected: "hand.raised"
        case .invalid: "exclamationmark.triangle"
        case .stale: "clock"
        case .paused: "pause.circle"
        case .live: "dot.radiowaves.left.and.right"
        }
    }

    var color: Color {
        switch self {
        case .notRead, .unsupported: Palette.textTertiary
        case .noResponse, .rejected: Palette.warningText
        case .invalid: Palette.fault
        case .stale, .paused: Palette.textSecondary
        case .live: Palette.live
        }
    }
}

struct StateLabel: View {
    let state: ValueState
    var font: Font = .obdLabel

    var body: some View {
        Label(state.word, systemImage: state.symbol)
            .font(font)
            .foregroundStyle(state.color)
            .lineLimit(1)
    }
}

/// Number with unit on one baseline. Digits keep their width.
struct ValueText: View {
    let number: String
    let unit: String
    var font: Font = .obdValue
    var color: Color = Palette.textPrimary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(number)
                .font(font)
                .foregroundStyle(color)
                .contentTransition(reduceMotion ? .identity : .numericText())
            if !unit.isEmpty {
                Text(unit).font(.obdLabel).foregroundStyle(Palette.textSecondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Pulsing dot for a running live stream, static when motion is reduced.
/// The animation is scoped to the halo with a phase animator, so it never moves the surrounding layout.
struct LiveDot: View {
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if active && !reduceMotion {
                Circle()
                    .fill(Palette.live.opacity(0.35))
                    .frame(width: 14, height: 14)
                    .phaseAnimator([false, true]) { halo, expanded in
                        halo.scaleEffect(expanded ? 1 : 0.5).opacity(expanded ? 0 : 1)
                    } animation: { expanded in
                        expanded ? .easeOut(duration: 1.2) : nil
                    }
            }
            Circle().fill(active ? Palette.live : Palette.textTertiary).frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
        .accessibilityLabel(active ? "Live" : "Pausiert")
    }
}
