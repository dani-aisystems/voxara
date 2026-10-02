import Foundation

/// Local LLM through Ollama's HTTP API (default http://localhost:11434). Nothing leaves the Mac.
public struct OllamaProvider: AIProvider {
    public let id = "ollama"
    public var displayName: String { "Ollama (\(model))" }
    public let sendsDataOffDevice = false

    public var baseURL: URL
    public var model: String
    /// How long Ollama keeps the model in memory after a request. A long value keeps the next dictation fast.
    public var keepAlive: String

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!, model: String, keepAlive: String = "2h") {
        self.baseURL = baseURL
        self.model = model
        self.keepAlive = keepAlive
    }

    public func isAvailable() async -> Bool {
        guard let installed = try? await installedModels() else { return false }
        // Ollama reports "name:tag"; a model configured without a tag means ":latest".
        let wanted = model.contains(":") ? model : model + ":latest"
        return installed.contains(wanted)
    }

    public struct ModelInfo: Sendable, Equatable, Identifiable {
        public var name: String
        public var bytes: Int64
        public var id: String { name }
    }

    public func installedModels() async throws -> [String] {
        try await installedModelDetails().map(\.name)
    }

    public func installedModelDetails() async throws -> [ModelInfo] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Tags: Decodable { struct Model: Decodable { let name: String; let size: Int64? }; let models: [Model] }
        return try JSONDecoder().decode(Tags.self, from: data).models.map { ModelInfo(name: $0.name, bytes: $0.size ?? 0) }
    }

    /// Loads the model into memory so the first real request does not pay the load cost.
    public func warmUp() async {
        _ = try? await generate([ChatMessage(.user, "ok")], options: GenerationOptions(maxTokens: 1, timeout: 60))
    }

    public func generate(_ messages: [ChatMessage], options: GenerationOptions) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "keep_alive": keepAlive,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "options": [
                "temperature": options.temperature,
                "num_predict": options.maxTokens,
                "num_ctx": 4096,
            ] as [String: Any],
        ]
        if let schema = options.jsonSchema {
            let data = try JSONEncoder().encode(schema)
            body["format"] = try JSONSerialization.jsonObject(with: data)
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = options.timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw AIProviderError.timeout
        } catch let error as URLError where [.cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost].contains(error.code) {
            throw AIProviderError.unavailable("Ollama is not running")
        }

        guard let http = response as? HTTPURLResponse else { throw AIProviderError.badResponse("no HTTP response") }
        if http.statusCode == 404 { throw AIProviderError.modelMissing(model) }
        guard http.statusCode == 200 else {
            throw AIProviderError.badResponse("HTTP \(http.statusCode): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
        }
        struct Reply: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
            let load_duration: Int64?
            let prompt_eval_count: Int?
            let prompt_eval_duration: Int64?
            let eval_count: Int?
            let eval_duration: Int64?
        }
        do {
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            func ms(_ ns: Int64?) -> Int { Int((ns ?? 0) / 1_000_000) }
            VoxaraLog.logger("ollama").info("""
            \(model, privacy: .public): load \(ms(reply.load_duration))ms · prompt \(reply.prompt_eval_count ?? 0) tok \(ms(reply.prompt_eval_duration))ms · \
            output \(reply.eval_count ?? 0) tok \(ms(reply.eval_duration))ms
            """)
            return reply.message.content
        } catch {
            throw AIProviderError.badResponse("could not decode reply")
        }
    }
}
