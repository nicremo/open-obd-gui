import Foundation
import OBDCore

public struct LivePoint: Sendable, Equatable, Identifiable {
    public let id: Int
    public let time: Date
    public let value: Double
}

/// Fixed display range for a live gauge. Unknown PIDs fall back to the observed span.
public struct GaugeRange: Sendable, Equatable {
    public let lower: Double
    public let upper: Double

    public static func forPID(_ pid: UInt8) -> GaugeRange? {
        switch pid {
        case 0x0C: GaugeRange(lower: 0, upper: 6000)
        case 0x0D: GaugeRange(lower: 0, upper: 220)
        case 0x05, 0x5C: GaugeRange(lower: -40, upper: 140)
        case 0x0F, 0x46: GaugeRange(lower: -40, upper: 80)
        case 0x04, 0x11, 0x2C, 0x2E, 0x2F, 0x43, 0x45, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x52, 0x5A, 0x5B: GaugeRange(lower: 0, upper: 100)
        case 0x06, 0x07, 0x08, 0x09, 0x2D: GaugeRange(lower: -25, upper: 25)
        case 0x42: GaugeRange(lower: 10, upper: 16)
        case 0x0B, 0x33: GaugeRange(lower: 0, upper: 255)
        case 0x10: GaugeRange(lower: 0, upper: 250)
        case 0x0E: GaugeRange(lower: -64, upper: 64)
        case 0x23, 0x59: GaugeRange(lower: 0, upper: 200_000)
        case 0x3C, 0x3D, 0x3E, 0x3F: GaugeRange(lower: 0, upper: 1000)
        case 0x5E: GaugeRange(lower: 0, upper: 40)
        default: nil
        }
    }

    public func fraction(_ value: Double) -> Double {
        guard upper > lower else { return 0 }
        return min(1, max(0, (value - lower) / (upper - lower)))
    }
}

/// Ring buffer of one live value for gauges and charts.
public struct LiveSeries: Identifiable, Sendable, Equatable {
    /// Five minutes at four samples per second.
    public static let capacity = 1200

    public let id: String
    public let pid: UInt8
    public let ecu: String
    public private(set) var name: String
    public private(set) var unit = ""
    public private(set) var latest: MeasurementRecord?
    public private(set) var points: [LivePoint] = []
    public private(set) var minimum: Double?
    public private(set) var maximum: Double?
    /// Sum and count of all samples, also those already dropped from `points`.
    public private(set) var sum = 0.0
    public private(set) var sampleCount = 0
    private var counter = 0

    public init(pid: UInt8, ecu: String, name: String) {
        id = "\(ecu):\(Hex.byteString(pid))"
        self.pid = pid
        self.ecu = ecu
        self.name = name
    }

    public var latestValue: Double? { latest?.primaryValue?.numericValue }

    public var mean: Double? { sampleCount > 0 ? sum / Double(sampleCount) : nil }

    public var range: GaugeRange? {
        if let fixed = GaugeRange.forPID(pid) { return fixed }
        guard let minimum, let maximum, maximum > minimum else { return nil }
        return GaugeRange(lower: minimum, upper: maximum)
    }

    public mutating func append(_ record: MeasurementRecord) {
        latest = record
        name = record.name
        guard case .number(let value, let unit) = record.primaryValue else { return }
        self.unit = unit
        counter += 1
        points.append(LivePoint(id: counter, time: record.provenance.timestamp, value: value))
        if points.count > Self.capacity {
            points.removeFirst(points.count - Self.capacity)
        }
        minimum = min(minimum ?? value, value)
        maximum = max(maximum ?? value, value)
        sum += value
        sampleCount += 1
    }
}
