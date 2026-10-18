import SwiftUI

/// Colored part of the outer threshold band, as fractions of the scale.
struct GaugeBand: Identifiable {
    let from: Double
    let to: Double
    let color: Color

    var id: String { "\(from)-\(to)" }
}

/// Round instrument with a 270 degree arc. The value sits in the center,
/// scale limits below, optional evidenced thresholds as a thin outer band.
struct ArcGauge: View {
    let fraction: Double?
    let valueText: String
    let unit: String
    let lowerText: String
    let upperText: String
    var color: Color = Palette.live
    var bands: [GaugeBand] = []
    var dimmed = false

    private static let sweep = 0.75

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = max(6, side * 0.075)
            ZStack {
                Circle()
                    .trim(from: 0, to: Self.sweep)
                    .stroke(Palette.hairline, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(135))
                if let fraction {
                    Circle()
                        .trim(from: 0, to: Self.sweep * min(1, max(0, fraction)))
                        .stroke(dimmed ? Palette.textTertiary : color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(135))
                }
                ForEach(bands) { band in
                    Circle()
                        .trim(from: Self.sweep * band.from, to: Self.sweep * band.to)
                        .stroke(band.color, style: StrokeStyle(lineWidth: max(2, line * 0.3)))
                        .rotationEffect(.degrees(135))
                        .padding(-line * 0.9)
                }
                VStack(spacing: 0) {
                    Text(valueText)
                        .font(.timing(side * 0.22, .bold))
                        .foregroundStyle(dimmed ? Palette.textSecondary : Palette.textPrimary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(unit).font(.obdCaption).foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, line * 1.5)
                HStack {
                    Text(lowerText)
                    Spacer()
                    Text(upperText)
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Palette.textTertiary)
                .frame(width: side * 0.62)
                .offset(y: side * 0.47)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(valueText) \(unit)")
    }
}
