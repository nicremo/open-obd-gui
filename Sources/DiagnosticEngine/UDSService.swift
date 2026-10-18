import AdapterKit
import Foundation
import OBDCore

public struct UDSReply: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case positive([UInt8])
        case negative(UInt8)
        case noResponse
    }

    public let outcome: Outcome
    public let request: [UInt8]
    /// Complete final response message, including the service byte.
    public let response: [UInt8]?
    public let elapsed: Duration

    public init(outcome: Outcome, request: [UInt8], response: [UInt8]?, elapsed: Duration) {
        self.outcome = outcome
        self.request = request
        self.response = response
        self.elapsed = elapsed
    }
}

/// Physical UDS requests to one Ford module (request ID, response ID = request + 8).
public struct UDSService: Sendable {
    let driver: AdapterDriver

    public init(driver: AdapterDriver) {
        self.driver = driver
    }

    /// Sends a request, skips "response pending" (7F xx 78) and retries once with a longer timeout if only pending arrived.
    public func send(_ payload: [UInt8], to module: UInt32, timeout: Duration = .milliseconds(500)) async throws -> UDSReply {
        guard let service = payload.first else { throw OBDError.policyDenied("leere Anfrage") }
        var wait = timeout
        for attempt in 0..<2 {
            let result = try await driver.request(payload, to: .module(module), timeout: wait, expectedResponses: 1)
            var pending = false
            for response in result.payloads(from: module + 8) {
                switch try UDSResponse.classify(response, service: service) {
                case .pending:
                    pending = true
                case .positive(let data):
                    return UDSReply(outcome: .positive(data), request: payload, response: response, elapsed: result.elapsed)
                case .negative(let code):
                    return UDSReply(outcome: .negative(code), request: payload, response: response, elapsed: result.elapsed)
                }
            }
            if !pending {
                return UDSReply(outcome: .noResponse, request: payload, response: nil, elapsed: result.elapsed)
            }
            if attempt == 1 {
                throw OBDError.timeout("Steuergerät \(Hex.canID(module, extended: false)) meldet nur, dass die Antwort folgt")
            }
            wait = .seconds(2)
        }
        return UDSReply(outcome: .noResponse, request: payload, response: nil, elapsed: .zero)
    }

    /// Positive outcome contains only the record value, without the echoed DID.
    public func readDID(_ did: UInt16, from module: UInt32) async throws -> UDSReply {
        let reply = try await send(UDSCodec.readDataByIdentifier(did), to: module)
        guard case .positive(let data) = reply.outcome else { return reply }
        let value = try UDSCodec.decodeReadDataByIdentifier(data, did: did)
        return UDSReply(outcome: .positive(value), request: reply.request, response: reply.response, elapsed: reply.elapsed)
    }

    public func readDTCs(from module: UInt32) async throws -> (list: UDSCodec.DTCList?, reply: UDSReply) {
        let reply = try await send(UDSCodec.reportDTCByStatusMask(), to: module, timeout: .milliseconds(800))
        guard case .positive(let data) = reply.outcome else { return (nil, reply) }
        return (try UDSCodec.decodeDTCByStatusMask(data), reply)
    }

    public func readSnapshot(_ dtc: UDSDTC, from module: UInt32) async throws -> UDSReply {
        try await send(UDSCodec.reportSnapshotRecord(dtc), to: module, timeout: .milliseconds(800))
    }

    public func readExtendedData(_ dtc: UDSDTC, from module: UInt32) async throws -> UDSReply {
        try await send(UDSCodec.reportExtendedDataRecord(dtc), to: module, timeout: .milliseconds(800))
    }
}
