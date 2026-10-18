import Foundation

/// UDS DTC status byte (ISO 14229-1, D.2).
public struct DTCStatus: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let testFailed = DTCStatus(rawValue: 1 << 0)
    public static let testFailedThisOperationCycle = DTCStatus(rawValue: 1 << 1)
    public static let pending = DTCStatus(rawValue: 1 << 2)
    public static let confirmed = DTCStatus(rawValue: 1 << 3)
    public static let testNotCompletedSinceLastClear = DTCStatus(rawValue: 1 << 4)
    public static let testFailedSinceLastClear = DTCStatus(rawValue: 1 << 5)
    public static let testNotCompletedThisOperationCycle = DTCStatus(rawValue: 1 << 6)
    public static let warningIndicatorRequested = DTCStatus(rawValue: 1 << 7)

    public struct Bit: Sendable, Equatable {
        public let index: Int
        public let name: String
        public let german: String
    }

    public static let bits: [Bit] = [
        Bit(index: 0, name: "testFailed", german: "Fehler liegt jetzt vor"),
        Bit(index: 1, name: "testFailedThisOperationCycle", german: "in diesem Fahrzyklus aufgetreten"),
        Bit(index: 2, name: "pendingDTC", german: "vorläufig, noch nicht bestätigt"),
        Bit(index: 3, name: "confirmedDTC", german: "bestätigt und gespeichert"),
        Bit(index: 4, name: "testNotCompletedSinceLastClear", german: "Test seit dem Löschen nicht abgeschlossen"),
        Bit(index: 5, name: "testFailedSinceLastClear", german: "seit dem Löschen mindestens einmal aufgetreten"),
        Bit(index: 6, name: "testNotCompletedThisOperationCycle", german: "Test in diesem Fahrzyklus nicht abgeschlossen"),
        Bit(index: 7, name: "warningIndicatorRequested", german: "Warnleuchte angefordert"),
    ]

    public var setBits: [Bit] {
        Self.bits.filter { rawValue & (1 << UInt8($0.index)) != 0 }
    }
}

/// Three-byte UDS DTC: J2012 code plus failure type byte, with its status.
public struct UDSDTC: Hashable, Sendable, Codable {
    public let code: DTCCode
    public let failureType: UInt8
    public let status: DTCStatus

    public init(code: DTCCode, failureType: UInt8, status: DTCStatus) {
        self.code = code
        self.failureType = failureType
        self.status = status
    }

    public init(high: UInt8, middle: UInt8, low: UInt8, status: DTCStatus) {
        self.init(code: DTCCode(high: high, low: middle), failureType: low, status: status)
    }

    public var bytes: [UInt8] { [UInt8(code.raw >> 8), UInt8(code.raw & 0xFF), failureType] }

    public var displayCode: String { "\(code)-\(Hex.byteString(failureType))" }
}
