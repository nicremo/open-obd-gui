import Foundation
import OBDCore

public struct VirtualAdapterIdentity: Sendable {
    public var elmVersion: String
    public var stnFirmware: String?
    public var device: String
    public var manufacturer: String
    public var serialNumber: String
    public var supportsMSCAN: Bool

    public static let obdLinkEX = VirtualAdapterIdentity(
        elmVersion: "ELM327 v1.4b", stnFirmware: "STN2232 v5.10.3", device: "OBDLink EX (Simulator)",
        manufacturer: "OBD Solutions LLC", serialNumber: "SIM000000001", supportsMSCAN: true)

    public static let genericELM = VirtualAdapterIdentity(
        elmVersion: "ELM327 v1.5", stnFirmware: nil, device: "ELM327 (Simulator)",
        manufacturer: "unbekannt", serialNumber: "", supportsMSCAN: false)
}

/// Text level imitation of an ELM327/STN adapter connected to a `VehicleProfile`.
public actor VirtualAdapter {
    enum Filter: Equatable {
        case standard
        case single(UInt32)
        case masked(pattern: UInt32, mask: UInt32)
    }

    public nonisolated let profile: VehicleProfile
    public nonisolated let identity: VirtualAdapterIdentity
    private let start = ContinuousClock.now
    private var echo = true
    private var linefeeds = true
    private var spaces = true
    private var headers = false
    private var bus: BusKind?
    private var protocolNumber: String?
    private var header: UInt32 = 0x7DF
    private var filter: Filter = .standard
    private var filterPattern: UInt32 = 0
    private var filterMask: UInt32 = 0x7FF
    public private(set) var ignitionOn = true
    public private(set) var received: [String] = []

    public init(profile: VehicleProfile, identity: VirtualAdapterIdentity) {
        self.profile = profile
        self.identity = identity
    }

    public func setIgnition(_ on: Bool) {
        ignitionOn = on
    }

    /// Returns the complete adapter output for one command, ending with the `>` prompt.
    public func handle(_ rawCommand: String) -> String {
        received.append(rawCommand)
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = command.uppercased()
        let compact = upper.filter { $0 != " " }
        let echoed = echo ? command + "\r" : ""
        let lines = respond(upper: upper, compact: compact)
        let newline = linefeeds ? "\r\n" : "\r"
        return echoed + lines.map { $0 + newline }.joined() + newline + ">"
    }

    func respond(upper: String, compact: String) -> [String] {
        if upper.hasPrefix("STPX") {
            return identity.stnFirmware == nil ? ["?"] : transmitSTPX(upper)
        }
        switch compact {
        case "ATZ", "ATWS": reset(); return [identity.elmVersion]
        case "ATE0": echo = false; return ["OK"]
        case "ATE1": echo = true; return ["OK"]
        case "ATL0": linefeeds = false; return ["OK"]
        case "ATL1": linefeeds = true; return ["OK"]
        case "ATS0": spaces = false; return ["OK"]
        case "ATS1": spaces = true; return ["OK"]
        case "ATH0": headers = false; return ["OK"]
        case "ATH1": headers = true; return ["OK"]
        case "ATCAF0", "ATCAF1", "ATAT0", "ATAT1", "ATAT2", "ATD0", "ATCFC1": return ["OK"]
        case "ATI": return [identity.elmVersion]
        case "AT@1": return [identity.device]
        case "ATRV": return [String(format: "%.1fV", ignitionOn ? profile.batteryVoltage : 12.2)]
        case "ATDPN": return [bus == nil ? "0" : "6"]
        case "ATDP": return [bus == .msCAN ? "ISO 15765-4 (CAN 11/125)" : bus == .hsCAN ? "ISO 15765-4 (CAN 11/500)" : "AUTO"]
        case "ATCRA": filter = .standard; return ["OK"]
        default: break
        }
        if let firmware = identity.stnFirmware, compact.hasPrefix("ST") {
            return stCommand(compact, firmware: firmware)
        }
        if compact.hasPrefix("ATSP") {
            let requested = compact.dropFirst(4)
            if requested == "0" || requested == "6" { bus = .hsCAN }
            return ["OK"]
        }
        if compact.hasPrefix("ATSH"), let id = UInt32(compact.dropFirst(4), radix: 16) {
            header = id
            return ["OK"]
        }
        if compact.hasPrefix("ATCRA"), let id = UInt32(compact.dropFirst(5), radix: 16) {
            filter = .single(id)
            return ["OK"]
        }
        if compact.hasPrefix("ATCF"), let id = UInt32(compact.dropFirst(4), radix: 16) {
            filterPattern = id
            filter = .masked(pattern: filterPattern, mask: filterMask)
            return ["OK"]
        }
        if compact.hasPrefix("ATCM"), let id = UInt32(compact.dropFirst(4), radix: 16) {
            filterMask = id
            filter = .masked(pattern: filterPattern, mask: filterMask)
            return ["OK"]
        }
        if compact.hasPrefix("ATST") { return ["OK"] }
        if Hex.isHexDigits(compact), compact.count.isMultiple(of: 2), let payload = try? Hex.decode(compact) {
            return transmit(payload, to: header, limit: nil)
        }
        return ["?"]
    }

    func stCommand(_ compact: String, firmware: String) -> [String] {
        switch compact {
        case "STI": return [firmware]
        case "STIX": return [firmware + " [2024.02.01]"]
        case "STDI": return [identity.device]
        case "STMFR": return [identity.manufacturer]
        case "STSN": return [identity.serialNumber]
        case "STPR": return [protocolNumber ?? "0"]
        case "STPRS": return [bus?.shortName ?? "AUTO"]
        case "STPBRR": return [bus == .msCAN ? "125000" : bus == .hsCAN ? "500000" : "?"]
        case "STP33":
            bus = .hsCAN
            protocolNumber = "33"
            return ["OK"]
        case "STP53":
            guard identity.supportsMSCAN else { return ["?"] }
            bus = .msCAN
            protocolNumber = "53"
            return ["OK"]
        case "STFAC", "STFPC", "STCFCPC":
            return ["OK"]
        default:
            if compact.hasPrefix("STPTO") || compact.hasPrefix("STFPA") || compact.hasPrefix("STCFCPA") { return ["OK"] }
            return ["?"]
        }
    }

    func transmitSTPX(_ upper: String) -> [String] {
        var parameters: [Character: String] = [:]
        for part in upper.dropFirst(4).split(separator: ",") {
            let item = part.trimmingCharacters(in: .whitespaces)
            guard let key = item.first, item.dropFirst().first == ":" else { return ["?"] }
            parameters[key] = String(item.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        guard let data = parameters["D"], let payload = try? Hex.decode(data), !payload.isEmpty else { return ["?"] }
        let target = parameters["H"].flatMap { UInt32($0, radix: 16) } ?? header
        return transmit(payload, to: target, limit: parameters["R"].flatMap { Int($0) })
    }

    func transmit(_ payload: [UInt8], to target: UInt32, limit: Int?) -> [String] {
        guard let bus else { return ["UNABLE TO CONNECT"] }
        guard ignitionOn else { return ["NO DATA"] }
        let time = elapsedSeconds()
        let functional = target == 0x7DF
        var lines: [String] = []
        var answered = 0
        for ecu in profile.ecus where ecu.bus == bus && (functional || ecu.request == target) {
            let messages = ecu.respond(to: payload, functional: functional, time: time)
            guard !messages.isEmpty, accepts(ecu.response) else { continue }
            for message in messages {
                lines += Self.segment(message).map { format(id: ecu.response, data: $0) }
            }
            answered += 1
            if let limit, answered >= limit { break }
        }
        return lines.isEmpty ? ["NO DATA"] : lines
    }

    func accepts(_ id: UInt32) -> Bool {
        switch filter {
        case .standard: (0x7E8...0x7EF).contains(id)
        case .single(let wanted): id == wanted
        case .masked(let pattern, let mask): id & mask == pattern & mask
        }
    }

    func format(id: UInt32, data: [UInt8]) -> String {
        let bytes = data.map(Hex.byteString)
        let body = spaces ? bytes.joined(separator: " ") : bytes.joined()
        guard headers else { return body }
        return Hex.canID(id, extended: false) + (spaces ? " " : "") + body
    }

    /// ISO 15765-2 segmentation with zero padding to eight bytes.
    public static func segment(_ message: [UInt8]) -> [[UInt8]] {
        if message.count <= 7 {
            return [pad([UInt8(message.count)] + message)]
        }
        var frames = [pad([0x10 | UInt8((message.count >> 8) & 0x0F), UInt8(message.count & 0xFF)] + message.prefix(6))]
        var offset = 6
        var sequence: UInt8 = 1
        while offset < message.count {
            let end = min(offset + 7, message.count)
            frames.append(pad([0x20 | sequence] + message[offset..<end]))
            offset = end
            sequence = (sequence + 1) & 0x0F
        }
        return frames
    }

    static func pad(_ frame: [UInt8]) -> [UInt8] {
        frame + [UInt8](repeating: 0x00, count: max(0, 8 - frame.count))
    }

    func reset() {
        echo = true
        linefeeds = true
        spaces = true
        headers = false
        bus = nil
        protocolNumber = nil
        header = 0x7DF
        filter = .standard
        filterPattern = 0
        filterMask = 0x7FF
    }

    func elapsedSeconds() -> Double {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
