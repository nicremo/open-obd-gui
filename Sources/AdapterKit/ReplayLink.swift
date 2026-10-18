import Foundation
import OBDCore

public struct ReplayExchange: Sendable, Equatable {
    public let command: String
    public let reply: String
    /// `OBDError.code` of a recorded failure, for example TIMEOUT.
    public let failure: String?

    public init(command: String, reply: String, failure: String? = nil) {
        self.command = command
        self.reply = reply
        self.failure = failure
    }
}

/// Plays back recorded adapter traffic.
/// `strict` demands the exact command order (regression tests), `lookup` answers any known command (demos).
public actor ReplayLink: AdapterLink {
    public enum Mode: String, Sendable {
        case strict
        case lookup
    }

    public nonisolated let label: String
    private let exchanges: [ReplayExchange]
    private let mode: Mode
    private var position = 0

    public init(exchanges: [ReplayExchange], mode: Mode = .strict, label: String = "replay") {
        self.exchanges = exchanges
        self.mode = mode
        self.label = label
    }

    public static func load(_ url: URL, mode: Mode) throws -> ReplayLink {
        var exchanges: [ReplayExchange] = []
        var pending: String?
        for entry in try CaptureRecorder.load(url) {
            switch entry.type {
            case .sent:
                pending = entry.line
            case .received:
                if let command = pending {
                    exchanges.append(ReplayExchange(command: command, reply: entry.text ?? ""))
                }
                pending = nil
            case .failure:
                if let command = pending {
                    exchanges.append(ReplayExchange(command: command, reply: "", failure: entry.text ?? "IO_ERROR"))
                }
                pending = nil
            case .header, .note:
                continue
            }
        }
        return ReplayLink(exchanges: exchanges, mode: mode, label: "replay:\(url.lastPathComponent)")
    }

    public var remaining: Int { exchanges.count - position }

    public func transact(_ command: String, timeout: Duration) throws -> LinkReply {
        let wanted = Self.normalize(command)
        let exchange: ReplayExchange
        switch mode {
        case .strict:
            guard position < exchanges.count else {
                throw OBDError.malformedResponse("Wiedergabe zu Ende, unerwarteter Befehl \(command)")
            }
            let next = exchanges[position]
            guard Self.normalize(next.command) == wanted else {
                throw OBDError.malformedResponse("Wiedergabe erwartet \(next.command), erhalten \(command)")
            }
            position += 1
            exchange = next
        case .lookup:
            let order = Array(exchanges[position...]) + Array(exchanges[..<position])
            guard let index = order.firstIndex(where: { Self.normalize($0.command) == wanted }) else {
                throw OBDError.malformedResponse("Wiedergabe kennt den Befehl \(command) nicht")
            }
            exchange = order[index]
            if let absolute = exchanges.firstIndex(of: exchange) {
                position = (absolute + 1) % max(exchanges.count, 1)
            }
        }
        if let failure = exchange.failure {
            throw Self.error(for: failure, command: command)
        }
        return LinkReply(text: exchange.reply, elapsed: .zero)
    }

    public func close() {}

    static func normalize(_ command: String) -> String {
        command.uppercased().filter { !$0.isWhitespace }
    }

    static func error(for code: String, command: String) -> OBDError {
        switch code {
        case "TIMEOUT": .timeout("Wiedergabe: \(command)")
        case "DISCONNECTED": .disconnected
        case "CANCELLED": .cancelled
        default: .io("Wiedergabe: \(code)")
        }
    }
}
