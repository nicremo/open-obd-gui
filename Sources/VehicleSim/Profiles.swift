import Foundation
import OBDCore

/// A synthetic vehicle: which ECUs exist on which bus and what they answer.
public struct VehicleProfile: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let note: String
    public let batteryVoltage: Double
    public let ecus: [VirtualECU]

    public init(id: String, title: String, note: String, batteryVoltage: Double, ecus: [VirtualECU]) {
        self.id = id
        self.title = title
        self.note = note
        self.batteryVoltage = batteryVoltage
        self.ecus = ecus
    }

    public static let all: [VehicleProfile] = [.mondeoMk4, .focusMk4]

    public static func named(_ id: String) -> VehicleProfile? {
        all.first { $0.id == id }
    }

    static func ascii(_ text: String) -> [UInt8] { Array(text.utf8) }
}

/// Live value generator. `bytes(at:)` returns the PID data bytes for a point in simulated time.
public struct SimSignal: Sendable {
    let generate: @Sendable (Double) -> [UInt8]

    public init(_ generate: @escaping @Sendable (Double) -> [UInt8]) {
        self.generate = generate
    }

    public func bytes(at time: Double) -> [UInt8] { generate(time) }

    public static func constant(_ bytes: [UInt8]) -> SimSignal {
        SimSignal { _ in bytes }
    }

    /// Smooth oscillation between `minimum` and `maximum` in physical units.
    public static func wave(_ minimum: Double, _ maximum: Double, period: Double, phase: Double = 0,
                            encode: @escaping @Sendable (Double) -> [UInt8]) -> SimSignal {
        SimSignal { time in
            let fraction = (sin((time / period + phase) * 2 * Double.pi) + 1) / 2
            return encode(minimum + (maximum - minimum) * fraction)
        }
    }
}

/// Inverse J1979 formulas used by the simulator.
public enum SimEncode {
    public static func byte(_ value: Double) -> [UInt8] {
        [UInt8(clamping: Int(value.rounded()))]
    }

    public static func word(_ value: Double) -> [UInt8] {
        let raw = UInt16(clamping: Int(value.rounded()))
        return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
    }

    public static let rpm: @Sendable (Double) -> [UInt8] = { word($0 * 4) }
    public static let temperature: @Sendable (Double) -> [UInt8] = { byte($0 + 40) }
    public static let percent: @Sendable (Double) -> [UInt8] = { byte($0 * 255 / 100) }
    public static let trim: @Sendable (Double) -> [UInt8] = { byte($0 * 128 / 100 + 128) }
    public static let plain: @Sendable (Double) -> [UInt8] = { byte($0) }
    public static let timing: @Sendable (Double) -> [UInt8] = { byte(($0 + 64) * 2) }
    public static let airflow: @Sendable (Double) -> [UInt8] = { word($0 * 100) }
    public static let voltage: @Sendable (Double) -> [UInt8] = { word($0 * 1000) }
    public static let railPressure: @Sendable (Double) -> [UInt8] = { word($0 / 10) }
    public static let catalyst: @Sendable (Double) -> [UInt8] = { word(($0 + 40) * 10) }
}
