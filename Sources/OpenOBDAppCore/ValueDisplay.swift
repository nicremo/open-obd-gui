import Foundation
import OBDCore

extension MeasurementRecord {
    /// Service 01 PID for ids of the form `7E8:01:0C`, also used for freeze frames (`:02:`).
    public var pid: UInt8? {
        let parts = id.split(separator: ":")
        guard parts.count >= 3, parts[parts.count - 2] == "01" || parts[parts.count - 2] == "02" else { return nil }
        return UInt8(parts[parts.count - 1], radix: 16)
    }

    public var displayDecimals: Int {
        pid.flatMap(DisplayPrecision.decimals(forPID:)) ?? 2
    }

    /// Primary value with fixed decimals, without unit. Non-numeric values use their own text.
    public var displayNumber: String {
        switch primaryValue {
        case .number(let value, _)?: MeasuredValue.format(value, decimals: displayDecimals)
        case let other?: other.displayText
        case nil: "kein Wert"
        }
    }

    public var displayUnit: String {
        if case .number(_, let unit)? = primaryValue { return unit }
        return ""
    }
}

extension LiveSeries {
    public var decimals: Int { DisplayPrecision.decimals(forPID: pid) ?? 2 }

    public func format(_ value: Double?) -> String {
        value.map { MeasuredValue.format($0, decimals: decimals) } ?? "kein Wert"
    }

    /// Points split where the time between two samples exceeds `maximumGap`, so charts draw gaps instead of bridges.
    public func segments(maximumGap: TimeInterval) -> [[LivePoint]] {
        var result: [[LivePoint]] = []
        var current: [LivePoint] = []
        for point in points {
            if let last = current.last, point.time.timeIntervalSince(last.time) > maximumGap {
                result.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
