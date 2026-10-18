import Charts
import OpenOBDAppCore
import SwiftUI

/// Time series of one live value: fixed scale from the quantity,
/// Y axis with grid, gaps instead of bridged lines, hover read-out.
struct LiveChart: View {
    let series: LiveSeries
    let window: TimeInterval
    var showAxes = true
    var color: Color = Palette.live
    var maximumGap: TimeInterval = 2.5
    /// Scale to the minimum and maximum of the visible points instead of the quantity's fixed range.
    var autoScale = false
    @State private var hover: LivePoint?

    var body: some View {
        let end = series.points.last?.time ?? Date()
        let start = end.addingTimeInterval(-window)
        let segments = series.segments(maximumGap: maximumGap)
            .map { $0.filter { $0.time >= start } }
            .filter { !$0.isEmpty }
        let domain = yDomain
        Chart {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                ForEach(segment) { point in
                    LineMark(x: .value("Zeit", point.time), y: .value(series.unit, point.value), series: .value("Abschnitt", index))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.linear)
                }
            }
            if let hover {
                RuleMark(x: .value("Zeit", hover.time))
                    .foregroundStyle(Palette.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Zeit", hover.time), y: .value(series.unit, hover.value))
                    .foregroundStyle(color)
                    .symbolSize(40)
                    .annotation(position: .top, alignment: .center, spacing: 6) {
                        VStack(spacing: 1) {
                            Text("\(series.format(hover.value)) \(series.unit)").font(.obdLabel).monospacedDigit()
                            Text(Fmt.time(hover.time)).font(.obdCaption).foregroundStyle(Palette.textSecondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.hairline))
                    }
            }
        }
        .chartXScale(domain: start...max(end, start.addingTimeInterval(1)))
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel()
            }
        }
        .chartXAxis(showAxes ? .visible : .hidden)
        .chartYAxis(showAxes ? .visible : .hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard showAxes else { return }
                        switch phase {
                        case .active(let location):
                            let origin = proxy.plotFrame.map { geometry[$0].origin } ?? .zero
                            if let date: Date = proxy.value(atX: location.x - origin.x) {
                                hover = series.points.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
                            }
                        case .ended:
                            hover = nil
                        }
                    }
            }
        }
        .accessibilityLabel("Verlauf \(series.name)")
        .accessibilityValue(accessibilityText)
    }

    private var yDomain: ClosedRange<Double> {
        if autoScale, let low = series.points.map(\.value).min(), let high = series.points.map(\.value).max() {
            let pad = max((high - low) * 0.1, max(abs(high) * 0.01, 0.01))
            return (low - pad)...(high + pad)
        }
        if let range = series.range, range.upper > range.lower {
            return range.lower...range.upper
        }
        let value = series.latestValue ?? 0
        return (value - 1)...(value + 1)
    }

    private var accessibilityText: String {
        guard let latest = series.latestValue else { return "kein Wert" }
        let trend: String
        if let previous = series.points.dropLast().last?.value {
            trend = latest > previous ? ", steigend" : latest < previous ? ", fallend" : ", gleichbleibend"
        } else {
            trend = ""
        }
        return "\(series.format(latest)) \(series.unit)\(trend)"
    }
}

/// Compact chart without axes for rows and tiles.
struct Sparkline: View {
    let series: LiveSeries
    var window: TimeInterval = 60
    var color: Color = Palette.live

    var body: some View {
        LiveChart(series: series, window: window, showAxes: false, color: color, autoScale: true)
            .accessibilityHidden(true)
    }
}
