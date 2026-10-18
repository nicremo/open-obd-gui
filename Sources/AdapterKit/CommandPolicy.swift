import Foundation
import OBDCore

/// Allowlist for everything sent to the adapter. Vehicle payloads additionally pass `ReadOnlyPolicy`.
public enum CommandPolicy {
    static let exact: Set<String> = [
        "ATZ", "ATWS", "ATE0", "ATL0", "ATS1", "ATH1", "ATCAF1", "ATAT0", "ATAT1", "ATAT2", "ATI", "AT@1", "ATRV",
        "ATDP", "ATDPN", "ATCRA", "ATD0",
        "STI", "STIX", "STDI", "STMFR", "STSN", "STPR", "STPRS", "STPBRR", "STFAC", "STFPC", "STCFCPC",
    ]

    /// STN protocol presets: HS-CAN 11/29 bit 500 kbit/s, 11/29 bit 250 kbit/s, MS-CAN 11/29 bit 125 kbit/s.
    static let protocolPresets: Set<String> = ["33", "34", "35", "36", "53", "54"]

    public static func validate(_ command: String) throws {
        let upper = command.uppercased().trimmingCharacters(in: .whitespaces)
        if upper.hasPrefix("STPX") {
            try validateSTPX(command, upper: upper)
            return
        }
        let compact = upper.filter { $0 != " " }
        guard !compact.isEmpty else {
            throw deny(command, "ein leerer Befehl würde den letzten Befehl wiederholen")
        }
        if exact.contains(compact) { return }
        if compact.hasPrefix("AT") || compact.hasPrefix("ST") {
            guard matchesParameterized(compact) else {
                throw deny(command, "Adapterbefehl ist nicht freigegeben")
            }
            return
        }
        guard Hex.isHexDigits(compact), compact.count.isMultiple(of: 2) else {
            throw deny(command, "weder freigegebener Adapterbefehl noch Hex-Nutzdaten")
        }
        try ReadOnlyPolicy.validate(Hex.decode(compact))
    }

    static func matchesParameterized(_ command: String) -> Bool {
        func suffix(_ prefix: String) -> Substring? {
            command.hasPrefix(prefix) ? command.dropFirst(prefix.count) : nil
        }
        func isCANID(_ text: Substring) -> Bool {
            (text.count == 3 || text.count == 8) && Hex.isHexDigits(text)
        }
        func isDecimal(_ text: Substring, in range: ClosedRange<Int>) -> Bool {
            !text.isEmpty && text.count <= 5 && text.utf8.allSatisfy { (0x30...0x39).contains($0) }
                && Int(text).map(range.contains) == true
        }
        func isPair(_ text: Substring, valid: (Substring) -> Bool) -> Bool {
            let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            return parts.count == 2 && parts.allSatisfy(valid)
        }

        if let value = suffix("ATSP") { return value.count == 1 && "0123456789ABC".contains(value) }
        if let value = suffix("ATSH") { return [3, 6, 8].contains(value.count) && Hex.isHexDigits(value) }
        if let value = suffix("ATCRA") { return isCANID(value) }
        if let value = suffix("ATCF") { return isCANID(value) }
        if let value = suffix("ATCM") { return isCANID(value) }
        if let value = suffix("ATST") { return value.count == 2 && Hex.isHexDigits(value) }
        if let value = suffix("STPTO") { return isDecimal(value, in: 1...65_535) }
        if let value = suffix("STFPA") { return isPair(value) { (1...10).contains($0.count) && Hex.isHexDigits($0) } }
        if let value = suffix("STCFCPA") { return isPair(value, valid: isCANID) }
        if let value = suffix("STP") { return protocolPresets.contains(String(value)) }
        return false
    }

    /// STPX is only allowed with h, d, t and r. The data passes the read-only vehicle policy.
    static func validateSTPX(_ command: String, upper: String) throws {
        var parameters: [Character: String] = [:]
        for part in upper.dropFirst(4).split(separator: ",") {
            let item = part.trimmingCharacters(in: .whitespaces)
            guard item.count >= 2, let key = item.first, item.dropFirst().first == ":" else {
                throw deny(command, "ungültiger STPX-Parameter \(item)")
            }
            guard parameters[key] == nil else {
                throw deny(command, "STPX-Parameter \(key) doppelt")
            }
            parameters[key] = String(item.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        guard Set(parameters.keys).isSubset(of: ["H", "D", "T", "R"]) else {
            throw deny(command, "STPX nur mit h, d, t und r erlaubt")
        }
        guard let data = parameters["D"], Hex.isHexDigits(data), data.count.isMultiple(of: 2) else {
            throw deny(command, "STPX braucht Hex-Nutzdaten in d")
        }
        if let header = parameters["H"], Hex.parseCANID(header) == nil {
            throw deny(command, "STPX-Header \(header) ist keine CAN-ID")
        }
        if let timeout = parameters["T"], !(Int(timeout).map { (1...65_535).contains($0) } ?? false) {
            throw deny(command, "STPX-Timeout \(timeout) ungültig")
        }
        if let responses = parameters["R"], !(Int(responses).map { (1...99).contains($0) } ?? false) {
            throw deny(command, "STPX-Antwortanzahl \(responses) ungültig")
        }
        try ReadOnlyPolicy.validate(Hex.decode(data))
    }

    static func deny(_ command: String, _ reason: String) -> OBDError {
        .policyDenied("\(command.isEmpty ? "(leer)" : command): \(reason)")
    }
}
