import Foundation

public struct ChatMessage: Sendable, Equatable {
    public enum Role: String, Sendable { case system, user, assistant }
    public var role: Role
    public var content: String

    public init(_ role: Role, _ content: String) {
        self.role = role
        self.content = content
    }
}

public struct GenerationOptions: Sendable {
    public var temperature: Double
    public var maxTokens: Int
    public var timeout: TimeInterval
    /// JSON Schema the response must conform to (structured output). Nil for free text.
    public var jsonSchema: [String: JSONValue]?

    public init(temperature: Double = 0.1, maxTokens: Int = 1024, timeout: TimeInterval = 30, jsonSchema: [String: JSONValue]? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeout = timeout
        self.jsonSchema = jsonSchema
    }
}

public enum AIProviderError: LocalizedError, Equatable {
    case unavailable(String)
    case timeout
    case badResponse(String)
    case modelMissing(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let why): "AI provider unavailable: \(why)"
        case .timeout: "The AI provider took too long to respond."
        case .badResponse(let why): "Unexpected AI response: \(why)"
        case .modelMissing(let name): "The model “\(name)” is not installed."
        }
    }
}

/// A text-generation backend. Everything above this layer (dictation refinement, prompt
/// compilation) depends only on this protocol, never on a specific vendor.
public protocol AIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// True when text leaves this Mac. Cloud providers must be explicitly opted into.
    var sendsDataOffDevice: Bool { get }
    func isAvailable() async -> Bool
    func generate(_ messages: [ChatMessage], options: GenerationOptions) async throws -> String
}

/// Minimal Codable JSON value, used for JSON Schemas and structured outputs.
public enum JSONValue: Codable, Sendable, Equatable, ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
