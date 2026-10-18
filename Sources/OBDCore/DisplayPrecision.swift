import Foundation

/// Fixed number of decimals per measured quantity, so values do not change width while they update.
/// Derived from the resolution of one bit of the SAE J1979 formula, with a few readability overrides.
public enum DisplayPrecision {
    /// Overrides where the resolution would show noise rather than information.
    static let overrides: [UInt8: Int] = [
        0x0C: 0, // engine speed: 0.25 1/min steps carry no meaning for a reader
        0x42: 2, // control module voltage: 1 mV steps, two decimals are enough
    ]

    static let derived: [UInt8: Int] = {
        var table: [UInt8: Int] = [:]
        for definition in J1979.allDefinitions {
            table[definition.pid] = decimals(for: definition)
        }
        return table
    }()

    /// Decimals for the display of a service 01 PID, nil for unknown PIDs.
    public static func decimals(forPID pid: UInt8) -> Int? {
        overrides[pid] ?? derived[pid]
    }

    /// Resolution of the least significant bit, measured by decoding a zero and a one.
    static func decimals(for definition: PIDDefinition) -> Int {
        let zero = [UInt8](repeating: 0, count: definition.byteCount)
        var one = zero
        one[one.count - 1] = 1
        guard let low = try? definition.decoder(zero).first?.value.numericValue,
              let high = try? definition.decoder(one).first?.value.numericValue else { return 2 }
        let step = abs(high - low)
        guard step > 0 else { return 2 }
        if step >= 1 - 1e-9 { return 0 }
        return min(3, Int(ceil(-log10(step) - 1e-9)))
    }
}

extension MeasuredValue {
    /// German number with a fixed number of decimals.
    public static func format(_ value: Double, decimals: Int) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).grouping(.never).locale(Locale(identifier: "de_DE")))
    }
}
