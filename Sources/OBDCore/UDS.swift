import Foundation

/// Classification of a single UDS response message.
public enum UDSResponse: Sendable, Equatable {
    /// Bytes after the positive response service ID.
    case positive(data: [UInt8])
    case negative(code: UInt8)
    /// Negative response 0x78: the ECU will answer later.
    case pending

    public static func classify(_ payload: [UInt8], service: UInt8) throws -> UDSResponse {
        guard let first = payload.first else {
            throw OBDError.malformedResponse("Leere Antwort auf Dienst \(Hex.byteString(service))")
        }
        if first == 0x7F {
            guard payload.count >= 3, payload[1] == service else {
                throw OBDError.malformedResponse("Negativantwort passt nicht zu Dienst \(Hex.byteString(service)): \(Hex.encode(payload, separator: " "))")
            }
            return payload[2] == 0x78 ? .pending : .negative(code: payload[2])
        }
        guard first == service &+ 0x40 else {
            throw OBDError.malformedResponse("Antwort \(Hex.byteString(first)) passt nicht zu Dienst \(Hex.byteString(service))")
        }
        return .positive(data: Array(payload.dropFirst()))
    }
}

/// Request builders and response decoders for the read-only UDS services.
public enum UDSCodec {
    public static let testerPresent: [UInt8] = [0x3E, 0x00]

    public static func readDataByIdentifier(_ did: UInt16) -> [UInt8] {
        [0x22, UInt8(did >> 8), UInt8(did & 0xFF)]
    }

    public static func reportNumberOfDTCByStatusMask(_ mask: UInt8 = 0xFF) -> [UInt8] {
        [0x19, 0x01, mask]
    }

    public static func reportDTCByStatusMask(_ mask: UInt8 = 0xFF) -> [UInt8] {
        [0x19, 0x02, mask]
    }

    public static func reportSnapshotRecord(_ dtc: UDSDTC, record: UInt8 = 0xFF) -> [UInt8] {
        [0x19, 0x04] + dtc.bytes + [record]
    }

    public static func reportExtendedDataRecord(_ dtc: UDSDTC, record: UInt8 = 0xFF) -> [UInt8] {
        [0x19, 0x06] + dtc.bytes + [record]
    }

    /// `data` are the bytes after 0x62. Returns the record value.
    public static func decodeReadDataByIdentifier(_ data: [UInt8], did: UInt16) throws -> [UInt8] {
        guard data.count >= 2, data[0] == UInt8(did >> 8), data[1] == UInt8(did & 0xFF) else {
            throw OBDError.malformedResponse("Antwort gehört nicht zu DID \(Hex.encode([UInt8(did >> 8), UInt8(did & 0xFF)])): \(Hex.encode(data, separator: " "))")
        }
        return Array(data.dropFirst(2))
    }

    public struct DTCList: Sendable, Equatable {
        public let availabilityMask: DTCStatus
        public let dtcs: [UDSDTC]
    }

    /// `data` are the bytes after 0x59, starting with sub-function 0x02.
    public static func decodeDTCByStatusMask(_ data: [UInt8]) throws -> DTCList {
        guard data.count >= 2, data[0] == 0x02 else {
            throw OBDError.malformedResponse("Keine Antwort auf 19 02: \(Hex.encode(data, separator: " "))")
        }
        let records = Array(data.dropFirst(2))
        guard records.count.isMultiple(of: 4) else {
            throw OBDError.malformedResponse("DTC-Liste mit \(records.count) Bytes ist kein Vielfaches von 4")
        }
        var dtcs: [UDSDTC] = []
        for index in stride(from: 0, to: records.count, by: 4) {
            let dtc = UDSDTC(high: records[index], middle: records[index + 1], low: records[index + 2], status: DTCStatus(rawValue: records[index + 3]))
            if dtc.code.raw != 0 || dtc.failureType != 0 {
                dtcs.append(dtc)
            }
        }
        return DTCList(availabilityMask: DTCStatus(rawValue: data[1]), dtcs: dtcs)
    }

    public struct DTCCount: Sendable, Equatable {
        public let availabilityMask: DTCStatus
        public let formatIdentifier: UInt8
        public let count: Int
    }

    /// `data` are the bytes after 0x59, starting with sub-function 0x01.
    public static func decodeDTCCount(_ data: [UInt8]) throws -> DTCCount {
        guard data.count == 5, data[0] == 0x01 else {
            throw OBDError.malformedResponse("Keine Antwort auf 19 01: \(Hex.encode(data, separator: " "))")
        }
        return DTCCount(availabilityMask: DTCStatus(rawValue: data[1]), formatIdentifier: data[2], count: Int(data[3]) << 8 | Int(data[4]))
    }
}
