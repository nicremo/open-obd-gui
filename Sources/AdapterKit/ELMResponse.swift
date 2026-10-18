import Foundation
import OBDCore

/// Error lines documented in the OBDLink FRPM, section 10.
public enum ELMErrorKind: String, Sendable, Equatable, CaseIterable {
    case canError = "CAN ERROR"
    case busBusy = "BUS BUSY"
    case busError = "BUS ERROR"
    case bufferFull = "BUFFER FULL"
    case dataError = "DATA ERROR"
    case dataCheckError = "<DATA ERROR"
    case receiveError = "<RX ERROR"
    case feedbackError = "FB ERROR"
    case flowControlTimeout = "FC RX TIMEOUT"
    case stopped = "STOPPED"
    case lowVoltageReset = "LV RESET"
    case unableToConnect = "UNABLE TO CONNECT"
    case outOfMemory = "OUT OF MEMORY"
    case uartOverflow = "UART RX OVERFLOW"
    case activityAlert = "ACT ALERT"
    case lowPowerAlert = "LP ALERT"
}

public enum ELMLine: Sendable, Equatable {
    case frame(CANFrame)
    case ok
    case unknownCommand
    case noData
    case searching
    case error(ELMErrorKind)
    case text(String)
}

public struct ELMResponse: Sendable, Equatable {
    public let lines: [ELMLine]

    public init(lines: [ELMLine]) {
        self.lines = lines
    }

    public var frames: [CANFrame] {
        lines.compactMap { if case .frame(let frame) = $0 { frame } else { nil } }
    }

    public var errors: [ELMErrorKind] {
        lines.compactMap { if case .error(let kind) = $0 { kind } else { nil } }
    }

    public var texts: [String] {
        lines.compactMap { if case .text(let text) = $0 { text } else { nil } }
    }

    public var isOK: Bool { lines.contains(.ok) && errors.isEmpty && !isUnknownCommand }
    public var isUnknownCommand: Bool { lines.contains(.unknownCommand) }
    public var isNoData: Bool { lines.contains(.noData) }

    public var summary: String {
        let parts = lines.map { line -> String in
            switch line {
            case .frame(let frame): "\(frame.id) \(Hex.encode(frame.data, separator: " "))"
            case .ok: "OK"
            case .unknownCommand: "?"
            case .noData: "NO DATA"
            case .searching: "SEARCHING..."
            case .error(let kind): kind.rawValue
            case .text(let text): text
            }
        }
        return parts.isEmpty ? "(keine Antwort)" : parts.joined(separator: " | ")
    }
}

public enum ELMResponseParser {
    /// Splits the adapter text at CR/LF, drops the echo of `command` and classifies every line.
    /// Requires headers on (ATH1) and spaces on (ATS1) for frame lines.
    public static func parse(_ text: String, command: String, extendedIDs: Bool = false) -> ELMResponse {
        // "\r\n" is a single Character in Swift, so split on any newline character.
        var rawLines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let first = rawLines.first, normalize(first) == normalize(command) {
            rawLines.removeFirst()
        }
        return ELMResponse(lines: rawLines.map { classify($0, extendedIDs: extendedIDs) })
    }

    static func normalize(_ text: some StringProtocol) -> String {
        text.uppercased().filter { !$0.isWhitespace }
    }

    static func classify(_ line: String, extendedIDs: Bool) -> ELMLine {
        let upper = line.uppercased()
        switch upper {
        case "OK": return .ok
        case "?": return .unknownCommand
        case "NO DATA": return .noData
        default: break
        }
        if upper.hasPrefix("SEARCHING") || upper.hasPrefix("BUS INIT") {
            return .searching
        }
        if let kind = ELMErrorKind.allCases.first(where: { upper.hasPrefix($0.rawValue) }) {
            return .error(kind)
        }
        if let frame = parseFrame(upper, extendedIDs: extendedIDs) {
            return .frame(frame)
        }
        return .text(line)
    }

    static func parseFrame(_ line: String, extendedIDs: Bool) -> CANFrame? {
        let tokens = line.split(separator: " ")
        let headerTokens = extendedIDs ? 4 : 1
        guard tokens.count > headerTokens else { return nil }
        let header = tokens.prefix(headerTokens)
        let data = tokens.dropFirst(headerTokens)
        guard data.allSatisfy({ $0.count == 2 && Hex.isHexDigits($0) }) else { return nil }
        let id: UInt32
        if extendedIDs {
            guard header.allSatisfy({ $0.count == 2 && Hex.isHexDigits($0) }),
                  let value = UInt32(header.joined(), radix: 16) else { return nil }
            id = value
        } else {
            guard let first = header.first, first.count == 3, let value = Hex.parseCANID(first) else { return nil }
            id = value
        }
        let bytes = data.compactMap { UInt8($0, radix: 16) }
        guard bytes.count == data.count else { return nil }
        return CANFrame(id: CANIdentifier(id, extended: extendedIDs), data: bytes)
    }
}
