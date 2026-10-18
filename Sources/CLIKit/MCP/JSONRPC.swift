import Foundation

/// Any JSON value. MCP messages, arguments and results pass through it unchanged.
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { object[key] } else { nil }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    /// Re-reads any encodable value as JSON, with the same date format as the CLI.
    static func from<T: Encodable>(_ value: T) throws -> JSONValue {
        try parse(CLI.encode(value, pretty: false))
    }

    static func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// One line without line breaks, as the stdio transport requires.
    var line: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: encoder.encode(self), as: UTF8.self)) ?? "null"
    }
}

/// JSON-RPC 2.0 error with the standard codes.
struct RPCError: Error, Equatable {
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603

    let code: Int
    let message: String
}

/// One incoming message. `id == nil` means notification.
struct RPCRequest: Sendable {
    let id: JSONValue?
    let method: String
    let params: JSONValue?

    /// `nil` for messages the server ignores (responses from the client).
    static func parse(_ line: String) -> Result<RPCRequest?, RPCFailure> {
        guard let value = try? JSONValue.parse(line) else {
            return .failure(RPCFailure(id: .null, error: RPCError(code: RPCError.parseError, message: "Parse error")))
        }
        if case .array = value {
            return .failure(RPCFailure(id: .null, error: RPCError(code: RPCError.invalidRequest, message: "Batch requests are not supported")))
        }
        guard let object = value.object, object["jsonrpc"] == .string("2.0") else {
            return .failure(RPCFailure(id: value["id"] ?? .null, error: RPCError(code: RPCError.invalidRequest, message: "Invalid Request")))
        }
        let id = object["id"]
        if let id, !id.isValidID {
            return .failure(RPCFailure(id: .null, error: RPCError(code: RPCError.invalidRequest, message: "Invalid id")))
        }
        guard let method = object["method"]?.string else {
            if object["result"] != nil || object["error"] != nil { return .success(nil) }
            return .failure(RPCFailure(id: id ?? .null, error: RPCError(code: RPCError.invalidRequest, message: "Missing method")))
        }
        return .success(RPCRequest(id: id, method: method, params: object["params"]))
    }
}

struct RPCFailure: Error {
    let id: JSONValue
    let error: RPCError
}

enum RPC {
    static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "result": result])
    }

    static func error(id: JSONValue, _ error: RPCError) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .int(error.code), "message": .string(error.message)])])
    }

    static func notification(_ method: String, _ params: JSONValue) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "method": .string(method), "params": params])
    }
}

private extension JSONValue {
    var isValidID: Bool {
        switch self {
        case .int, .string: true
        default: false
        }
    }
}
