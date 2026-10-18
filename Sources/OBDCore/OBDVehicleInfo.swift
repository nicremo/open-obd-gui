import Foundation

/// SAE J1979 service 09 decoders. Inputs are the bytes after `49 <info type>`.
public enum OBDVehicleInfo {
    static let vinAlphabet = Set("ABCDEFGHJKLMNPRSTUVWXYZ0123456789")

    public static func isValidVIN(_ vin: String) -> Bool {
        vin.count == 17 && vin.allSatisfy { vinAlphabet.contains($0) }
    }

    /// Info type 02: number of data items, then the VIN. Leading zero padding is removed.
    public static func decodeVIN(_ data: [UInt8]) throws -> String {
        let bytes = data.dropFirst().drop { $0 == 0x00 }
        let vin = String(decoding: bytes, as: UTF8.self)
        guard isValidVIN(vin) else {
            throw OBDError.malformedResponse("Ungültige VIN: \(Hex.encode(data, separator: " "))")
        }
        return vin
    }

    /// Info type 04: number of calibration IDs, then 16 bytes each.
    public static func decodeCalibrationIDs(_ data: [UInt8]) throws -> [String] {
        try chunks(data, size: 16, what: "CALID").map(printableOrHex)
    }

    /// Info type 06: number of CVNs, then 4 bytes each, shown as hex.
    public static func decodeCVNs(_ data: [UInt8]) throws -> [String] {
        try chunks(data, size: 4, what: "CVN").map { Hex.encode($0) }
    }

    /// Info type 0A: number of data items (1), then 20 bytes ECU name.
    public static func decodeECUName(_ data: [UInt8]) throws -> String {
        guard data.count >= 21 else {
            throw OBDError.malformedResponse("ECU-Name erwartet 21 Bytes, erhalten \(data.count)")
        }
        return printableOrHex(Array(data[1...20]))
    }

    /// Info type 00: support bitmask for info types 01 to 20.
    public static func supportedInfoTypes(_ mask: [UInt8]) throws -> Set<UInt8> {
        try J1979.supportedPIDs(base: 0x00, mask: mask)
    }

    static func chunks(_ data: [UInt8], size: Int, what: String) throws -> [[UInt8]] {
        guard let count = data.first.map(Int.init), count > 0, data.count - 1 == count * size else {
            throw OBDError.malformedResponse("\(what): Anzahl passt nicht zur Länge (\(Hex.encode(data, separator: " ")))")
        }
        return stride(from: 1, to: data.count, by: size).map { Array(data[$0..<($0 + size)]) }
    }

    /// Trims zero and space padding. Returns hex if anything non-printable remains.
    static func printableOrHex(_ bytes: [UInt8]) -> String {
        var end = bytes.count
        while end > 0, bytes[end - 1] == 0x00 || bytes[end - 1] == 0x20 {
            end -= 1
        }
        let trimmed = bytes[..<end]
        guard !trimmed.isEmpty, trimmed.allSatisfy({ (0x20...0x7E).contains($0) }) else {
            return Hex.encode(bytes)
        }
        return String(decoding: trimmed, as: UTF8.self)
    }
}
