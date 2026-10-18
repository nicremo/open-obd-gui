import Foundation

/// Small builders for the JSON Schemas of the MCP tools.
enum Schema {
    static func object(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        var schema: [String: JSONValue] = ["type": .string("object"), "properties": .object(properties), "additionalProperties": .bool(false)]
        if !required.isEmpty { schema["required"] = .array(required.sorted().map(JSONValue.string)) }
        return .object(schema)
    }

    static func string(_ description: String, values: [String]? = nil, pattern: String? = nil) -> JSONValue {
        var schema: [String: JSONValue] = ["type": .string("string"), "description": .string(description)]
        if let values { schema["enum"] = .array(values.map(JSONValue.string)) }
        if let pattern { schema["pattern"] = .string(pattern) }
        return .object(schema)
    }

    static func boolean(_ description: String) -> JSONValue {
        .object(["type": .string("boolean"), "description": .string(description)])
    }

    static func integer(_ description: String, minimum: Int, maximum: Int) -> JSONValue {
        .object(["type": .string("integer"), "description": .string(description), "minimum": .int(minimum), "maximum": .int(maximum)])
    }

    static func number(_ description: String, minimum: Double, maximum: Double) -> JSONValue {
        .object(["type": .string("number"), "description": .string(description), "minimum": .double(minimum), "maximum": .double(maximum)])
    }

    static func array(_ description: String, items: JSONValue, minItems: Int = 1) -> JSONValue {
        .object(["type": .string("array"), "description": .string(description), "items": items, "minItems": .int(minItems)])
    }

    /// Output of every tool: the `openobd.cli/1` envelope.
    static let envelope = JSONValue.object([
        "type": .string("object"),
        "properties": .object([
            "schema": .object(["type": .string("string"), "const": .string(CLI.schema)]),
            "command": .object(["type": .string("string")]),
            "ok": .object(["type": .string("boolean")]),
            "data": .object(["description": .string("Dasselbe Objekt wie bei openobd <befehl> --json.")]),
            "warnings": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
            "error": .object(["type": .array([.string("object"), .string("null")])]),
            "meta": .object(["type": .string("object")]),
        ]),
        "required": .array(["command", "ok", "schema", "warnings"].map(JSONValue.string)),
    ])
}
