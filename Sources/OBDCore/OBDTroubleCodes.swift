import Foundation

/// SAE J1979 services 03 (stored), 07 (pending) and 0A (permanent) over CAN.
public enum OBDTroubleCodes {
    /// `payload` is the complete response, starting with 43, 47 or 4A, followed by the count byte.
    public static func decode(_ payload: [UInt8], service: UInt8) throws -> [DTCCode] {
        guard payload.count >= 2, payload[0] == service &+ 0x40 else {
            throw OBDError.malformedResponse("Keine Antwort auf Dienst \(Hex.byteString(service)): \(Hex.encode(payload, separator: " "))")
        }
        let count = Int(payload[1])
        let body = Array(payload.dropFirst(2))
        guard body.count == count * 2 else {
            throw OBDError.malformedResponse("Dienst \(Hex.byteString(service)): \(count) Fehlercodes angekündigt, \(body.count) Datenbytes erhalten")
        }
        return stride(from: 0, to: body.count, by: 2)
            .map { DTCCode(high: body[$0], low: body[$0 + 1]) }
            .filter { $0.raw != 0 }
    }
}
