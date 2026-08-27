import Foundation

enum JSONValue: Encodable {
    case string(String), int(Int), bool(Bool), array([JSONValue]), object([String: JSONValue]), null
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let v): try c.encode(v); case .int(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .array(let v): try c.encode(v); case .object(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
}
