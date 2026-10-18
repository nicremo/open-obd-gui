import Foundation

/// The only vehicle requests Open OBD GUI may ever send. Everything else is rejected before it reaches the wire.
public enum ReadOnlyPolicy {
    public enum Kind: String, Sendable, Equatable {
        case obdCurrentData
        case obdFreezeFrame
        case obdStoredDTC
        case obdTestResults
        case obdPendingDTC
        case obdVehicleInformation
        case obdPermanentDTC
        case udsReadDataByIdentifier
        case udsReadDTCInformation
        case udsTesterPresent
        case udsDefaultSession
    }

    public static let allowedServices: Set<UInt8> = [0x01, 0x02, 0x03, 0x06, 0x07, 0x09, 0x0A, 0x10, 0x19, 0x22, 0x3E]

    /// ReadDTCInformation sub-functions and the exact number of argument bytes after the sub-function.
    private static let readDTCArguments: [UInt8: Int] = [
        0x01: 1, // reportNumberOfDTCByStatusMask: status mask
        0x02: 1, // reportDTCByStatusMask: status mask
        0x03: 0, // reportDTCSnapshotIdentification
        0x04: 4, // reportDTCSnapshotRecordByDTCNumber: DTC (3) + record number
        0x06: 4, // reportDTCExtDataRecordByDTCNumber: DTC (3) + record number
        0x0A: 0, // reportSupportedDTC
    ]

    @discardableResult
    public static func validate(_ payload: [UInt8]) throws -> Kind {
        guard let service = payload.first else {
            throw OBDError.policyDenied("leere Anfrage")
        }
        let arguments = payload.count - 1
        func require(_ condition: Bool, _ rule: String) throws {
            guard condition else {
                throw OBDError.policyDenied("\(Hex.encode(payload, separator: " ")): \(rule)")
            }
        }

        switch service {
        case 0x01:
            try require((1...6).contains(arguments), "Dienst 01 erwartet 1 bis 6 PIDs")
            return .obdCurrentData
        case 0x02:
            try require(arguments > 0 && arguments <= 6 && arguments.isMultiple(of: 2), "Dienst 02 erwartet Paare aus PID und Frame-Nummer")
            return .obdFreezeFrame
        case 0x03:
            try require(arguments == 0, "Dienst 03 hat keine Argumente")
            return .obdStoredDTC
        case 0x06:
            try require(arguments == 1, "Dienst 06 erwartet eine Monitor-ID")
            return .obdTestResults
        case 0x07:
            try require(arguments == 0, "Dienst 07 hat keine Argumente")
            return .obdPendingDTC
        case 0x09:
            try require(arguments == 1, "Dienst 09 erwartet einen Infotyp")
            return .obdVehicleInformation
        case 0x0A:
            try require(arguments == 0, "Dienst 0A hat keine Argumente")
            return .obdPermanentDTC
        case 0x22:
            try require(arguments == 2, "Dienst 22 erwartet genau eine DID")
            return .udsReadDataByIdentifier
        case 0x19:
            try require(arguments >= 1, "Dienst 19 erwartet eine Unterfunktion")
            let subFunction = payload[1]
            guard let expected = readDTCArguments[subFunction] else {
                throw OBDError.policyDenied("Dienst 19 Unterfunktion \(Hex.byteString(subFunction)) ist nicht freigegeben")
            }
            try require(arguments - 1 == expected, "Dienst 19 Unterfunktion \(Hex.byteString(subFunction)) erwartet \(expected) Argumentbytes")
            return .udsReadDTCInformation
        case 0x3E:
            try require(arguments == 1 && (payload[1] == 0x00 || payload[1] == 0x80), "TesterPresent nur mit 00 oder 80")
            return .udsTesterPresent
        case 0x10:
            try require(arguments == 1 && payload[1] == 0x01, "Nur die Default Session (10 01) ist erlaubt")
            return .udsDefaultSession
        default:
            throw OBDError.policyDenied("Dienst \(Hex.byteString(service)) ist nicht freigegeben, Open OBD GUI liest nur")
        }
    }
}
