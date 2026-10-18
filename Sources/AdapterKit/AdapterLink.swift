import Foundation
import OBDCore

/// A line to an ELM327 compatible adapter. Exactly one transaction runs at a time.
public protocol AdapterLink: Sendable {
    var label: String { get }
    /// Sends `command` plus CR and returns everything received before the `>` prompt.
    func transact(_ command: String, timeout: Duration) async throws -> LinkReply
    func close() async
}

public struct LinkReply: Sendable, Equatable {
    public var text: String
    public var elapsed: Duration

    public init(text: String, elapsed: Duration) {
        self.text = text
        self.elapsed = elapsed
    }
}

/// Raw adapter traffic for consoles and verbose logs.
public struct TrafficEvent: Sendable, Equatable, Codable {
    public enum Direction: String, Sendable, Codable {
        case sent
        case received
        case failed
    }

    public let direction: Direction
    public let text: String
    public let timestamp: Date
    public let elapsed: Duration?

    public init(direction: Direction, text: String, timestamp: Date = Date(), elapsed: Duration? = nil) {
        self.direction = direction
        self.text = text
        self.timestamp = timestamp
        self.elapsed = elapsed
    }
}
