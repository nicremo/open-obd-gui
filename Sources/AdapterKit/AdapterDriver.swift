import Foundation
import OBDCore

public struct AdapterIdentity: Sendable, Codable, Equatable {
    public var elmVersion: String
    public var stnFirmware: String?
    public var device: String?
    public var manufacturer: String?
    public var serialNumber: String?

    public init(elmVersion: String, stnFirmware: String? = nil, device: String? = nil, manufacturer: String? = nil, serialNumber: String? = nil) {
        self.elmVersion = elmVersion
        self.stnFirmware = stnFirmware
        self.device = device
        self.manufacturer = manufacturer
        self.serialNumber = serialNumber
    }

    public var isSTN: Bool { stnFirmware != nil }
    public var displayName: String { device ?? stnFirmware ?? elmVersion }

    /// FRPM 8.4: `STN<4 digits> v<major>.<minor>.<patch>`, optionally followed by more text.
    static func isSTNFirmware(_ text: String) -> Bool {
        let tokens = text.split(separator: " ")
        guard tokens.count >= 2 else { return false }
        let chip = tokens[0]
        let version = tokens[1]
        let isDigit: (Character) -> Bool = { $0.isASCII && $0.isNumber }
        guard chip.count == 7, chip.hasPrefix("STN"), chip.dropFirst(3).allSatisfy(isDigit), version.first == "v" else { return false }
        let parts = version.dropFirst().split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(isDigit) }
    }
}

public enum RequestTarget: Sendable, Hashable, Codable {
    /// OBD broadcast to 0x7DF, answers from 0x7E8 to 0x7EF.
    case functional
    /// One module with a known response identifier.
    case physical(request: UInt32, response: UInt32)
    /// Presence probe: any 0x7xx responder is accepted.
    case probe(request: UInt32)

    /// Ford convention: response identifier = request identifier + 8.
    public static func module(_ request: UInt32) -> RequestTarget {
        .physical(request: request, response: request + 8)
    }

    public var requestID: UInt32 {
        switch self {
        case .functional: 0x7DF
        case .physical(let request, _): request
        case .probe(let request): request
        }
    }
}

public struct RequestResult: Sendable, Codable {
    public let request: [UInt8]
    public let target: RequestTarget
    public let messages: [ISOTPMessage]
    public let rawText: String
    public let elapsed: Duration

    public init(request: [UInt8], target: RequestTarget, messages: [ISOTPMessage], rawText: String, elapsed: Duration) {
        self.request = request
        self.target = target
        self.messages = messages
        self.rawText = rawText
        self.elapsed = elapsed
    }

    public var isEmpty: Bool { messages.isEmpty }

    public func payloads(from id: UInt32) -> [[UInt8]] {
        messages.filter { $0.source.value == id }.map(\.payload)
    }
}

/// Speaks ELM327 and the STN extensions of the OBDLink. One request at a time (actor).
public actor AdapterDriver {
    public typealias TrafficHandler = @Sendable (TrafficEvent) -> Void

    enum ReceiveFilter: Equatable {
        case unknown
        case standard
        case single(UInt32)
        case diagnosticRange
    }

    private let link: SafeLink
    private let traffic: TrafficHandler?
    public private(set) var identity: AdapterIdentity?
    public private(set) var activeBus: BusKind?
    public private(set) var voltage: Double?
    private var header: UInt32?
    private var filter: ReceiveFilter = .unknown
    private var msCANSupported: Bool?

    public init(link: any AdapterLink, traffic: TrafficHandler? = nil) {
        self.link = SafeLink(link)
        self.traffic = traffic
    }

    public nonisolated var label: String { link.label }

    // MARK: - Setup

    public func initialize() async throws -> AdapterIdentity {
        identity = nil
        activeBus = nil
        header = nil
        filter = .unknown
        msCANSupported = nil

        let reset = try await send("ATZ", timeout: .seconds(3))
        guard let banner = reset.texts.first(where: { $0.uppercased().contains("ELM327") }) else {
            throw OBDError.adapterNotResponding
        }
        for command in ["ATE0", "ATL0", "ATS1", "ATH1", "ATCAF1", "ATAT1"] {
            try await expectOK(command)
        }
        var identity = AdapterIdentity(elmVersion: try await send("ATI").texts.first ?? banner)
        if let firmware = try await send("STI").texts.first, AdapterIdentity.isSTNFirmware(firmware) {
            identity.stnFirmware = firmware
            identity.device = try await send("STDI").texts.first
            identity.manufacturer = try await send("STMFR").texts.first
            identity.serialNumber = try await send("STSN").texts.first
        } else {
            msCANSupported = false
        }
        self.identity = identity
        voltage = try await readVoltage()
        return identity
    }

    /// Battery voltage at pin 16 as measured by the adapter.
    public func readVoltage() async throws -> Double? {
        guard let text = try await send("ATRV").texts.first?.uppercased(), text.hasSuffix("V"),
              let value = Double(text.dropLast()) else { return nil }
        voltage = value
        return value
    }

    public func isBusAvailable(_ bus: BusKind) -> Bool {
        switch bus {
        case .hsCAN: true
        case .msCAN: identity?.isSTN == true && msCANSupported != false
        }
    }

    public func selectBus(_ bus: BusKind) async throws {
        guard let identity else { throw OBDError.adapterNotResponding }
        if activeBus == bus { return }
        guard isBusAvailable(bus) else {
            throw OBDError.busUnavailable("\(bus.shortName) wird von \(identity.displayName) nicht unterstützt")
        }
        activeBus = nil
        header = nil
        filter = .unknown
        if identity.isSTN {
            let preset = bus == .hsCAN ? "33" : "53"
            let response = try await send("STP\(preset)")
            if response.isUnknownCommand {
                if bus == .msCAN { msCANSupported = false }
                throw OBDError.busUnavailable("\(bus.shortName) wird von \(identity.displayName) nicht unterstützt")
            }
            guard response.isOK else {
                throw OBDError.adapterRejected(command: "STP\(preset)", reply: response.summary)
            }
            let active = try await send("STPR").texts.first
            guard active == preset else {
                throw OBDError.adapterRejected(command: "STPR", reply: active ?? "(leer)")
            }
            if bus == .msCAN { msCANSupported = true }
        } else {
            try await expectOK("ATSP6")
        }
        try await expectOK("ATCRA")
        filter = .standard
        activeBus = bus
    }

    // MARK: - Requests

    public func request(_ payload: [UInt8], to target: RequestTarget, timeout: Duration = .milliseconds(300),
                        expectedResponses: Int? = nil) async throws -> RequestResult {
        guard let identity, activeBus != nil else { throw OBDError.adapterNotResponding }
        try ReadOnlyPolicy.validate(payload)
        try await prepareFilter(for: target)

        let hex = Hex.encode(payload)
        let command: String
        if identity.isSTN {
            var parameters = ["h:\(Hex.canID(target.requestID, extended: false))", "d:\(hex)", "t:\(max(1, timeout.wholeMilliseconds))"]
            if let expectedResponses {
                parameters.append("r:\(expectedResponses)")
            }
            command = "STPX " + parameters.joined(separator: ", ")
        } else {
            try await setHeader(target.requestID)
            command = hex
        }

        let exchanged: (response: ELMResponse, reply: LinkReply)
        do {
            exchanged = try await exchange(command, timeout: timeout * 2 + .seconds(1))
        } catch OBDError.timeout(let detail) {
            try await resynchronize()
            throw OBDError.timeout(detail)
        }
        return try evaluate(exchanged.response, reply: exchanged.reply, command: command, payload: payload, target: target)
    }

    public func close() async {
        await link.close()
        identity = nil
        activeBus = nil
    }

    // MARK: - Internals

    func evaluate(_ response: ELMResponse, reply: LinkReply, command: String, payload: [UInt8], target: RequestTarget) throws -> RequestResult {
        if response.isUnknownCommand {
            throw OBDError.adapterRejected(command: command, reply: "?")
        }
        let frames = response.frames
        for error in response.errors {
            switch error {
            case .busBusy: throw OBDError.busBusy
            case .bufferFull: throw OBDError.bufferFull
            case .unableToConnect: throw OBDError.vehicleNotResponding
            case .stopped: throw OBDError.timeout("Der Adapter hat die Anfrage abgebrochen (STOPPED)")
            case .lowVoltageReset: throw OBDError.adapterError("Unterspannung, der Adapter hat neu gestartet")
            case .canError, .receiveError, .busError:
                if frames.isEmpty { throw OBDError.canError }
            case .activityAlert, .lowPowerAlert:
                continue
            default:
                if frames.isEmpty { throw OBDError.adapterError(error.rawValue) }
            }
        }
        let accepted = try ISOTPReassembler.reassemble(frames).filter { message in
            let source = message.source.value
            switch target {
            case .functional: return (0x7E8...0x7EF).contains(source)
            case .physical(_, let responseID): return source == responseID
            case .probe(let requestID): return (0x700...0x7FF).contains(source) && source != requestID
            }
        }
        return RequestResult(request: payload, target: target, messages: accepted, rawText: reply.text, elapsed: reply.elapsed)
    }

    func prepareFilter(for target: RequestTarget) async throws {
        let wanted: ReceiveFilter = switch target {
        case .functional: .standard
        case .physical(_, let responseID): .single(responseID)
        case .probe: .diagnosticRange
        }
        guard wanted != filter else { return }
        filter = .unknown
        switch wanted {
        case .standard:
            try await expectOK("ATCRA")
        case .single(let id):
            try await expectOK("ATCRA" + Hex.canID(id, extended: false))
        case .diagnosticRange:
            try await expectOK("ATCF700")
            try await expectOK("ATCM700")
        case .unknown:
            return
        }
        filter = wanted
    }

    func setHeader(_ id: UInt32) async throws {
        guard header != id else { return }
        header = nil
        try await expectOK("ATSH" + Hex.canID(id, extended: false))
        header = id
    }

    /// After a timeout the adapter may still be busy. Any character interrupts it (STOPPED), then it answers ATI again.
    func resynchronize() async throws {
        for _ in 0..<3 {
            if let response = try? await send("ATI", timeout: .seconds(1)) {
                if response.texts.contains(where: { $0.uppercased().contains("ELM327") }) { return }
                if response.errors.contains(.stopped) { continue }
            }
        }
        throw OBDError.adapterNotResponding
    }

    func expectOK(_ command: String) async throws {
        let response = try await send(command)
        guard response.isOK else {
            throw OBDError.adapterRejected(command: command, reply: response.summary)
        }
    }

    @discardableResult
    func send(_ command: String, timeout: Duration = .seconds(1)) async throws -> ELMResponse {
        try await exchange(command, timeout: timeout).response
    }

    func exchange(_ command: String, timeout: Duration) async throws -> (response: ELMResponse, reply: LinkReply) {
        traffic?(TrafficEvent(direction: .sent, text: command))
        do {
            let reply = try await link.transact(command, timeout: timeout)
            traffic?(TrafficEvent(direction: .received, text: reply.text, elapsed: reply.elapsed))
            return (ELMResponseParser.parse(reply.text, command: command), reply)
        } catch {
            let reason = (error as? OBDError)?.message ?? String(describing: error)
            traffic?(TrafficEvent(direction: .failed, text: "\(command): \(reason)"))
            throw error
        }
    }
}
