import Foundation

// MARK: - OpenAI-Compatible Request / Response Models

/// Represents the `content` field of an API message. Plain-text messages
/// (system prompts, tool results, synthesis prompts, echoing an assistant
/// tool-call message back) encode as a bare JSON string, identical to
/// pre-vision behavior. Messages that include one or more images encode as
/// an array of typed parts, per the OpenAI-compatible vision format:
/// [{"type":"text",...}, {"type":"image_url","image_url":{"url":"..."}}]
enum APIContent: Codable {
    case text(String)
    case parts([Part])

    enum Part: Codable {
        case text(String)
        case imageURL(String)

        private enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }
        private struct ImageURLBody: Codable { let url: String }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let t):
                try container.encode("text", forKey: .type)
                try container.encode(t, forKey: .text)
            case .imageURL(let url):
                try container.encode("image_url", forKey: .type)
                try container.encode(ImageURLBody(url: url), forKey: .imageURL)
            }
        }

        init(from decoder: Decoder) throws {
            // Decoding is only a defensive fallback (some provider echoing
            // structured content back). We only ever encode this type when
            // building outgoing requests.
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decodeIfPresent(String.self, forKey: .type) ?? "text"
            if type == "image_url", let body = try? container.decode(ImageURLBody.self, forKey: .imageURL) {
                self = .imageURL(body.url)
            } else {
                let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
                self = .text(text)
            }
        }
    }

    /// Extracts the plain text portion, if any. API responses are always
    /// `.text` in practice; `.parts` is handled defensively by concatenating
    /// any text parts and ignoring images.
    var plainText: String? {
        switch self {
        case .text(let t):
            return t
        case .parts(let parts):
            let combined = parts.compactMap { part -> String? in
                if case .text(let t) = part { return t }
                return nil
            }.joined()
            return combined.isEmpty ? nil : combined
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let t):
            try container.encode(t)
        case .parts(let p):
            try container.encode(p)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        let parts = try container.decode([Part].self)
        self = .parts(parts)
    }
}

/// A single message in the `messages` array sent to the API.
struct APIMessage: Codable {
    let role: String
    let content: APIContent?
    let toolCallId: String?
    let toolCalls: [ToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCallId = "tool_call_id"
        case toolCalls = "tool_calls"
    }

    /// Plain-text convenience initializer — covers every pre-vision call site
    /// (system prompts, tool results, synthesis prompts) unchanged, since a
    /// String argument is automatically wrapped as `.text`.
    init(role: String, content: String? = nil, toolCallId: String? = nil, toolCalls: [ToolCall]? = nil) {
        self.role = role
        self.content = content.map { APIContent.text($0) }
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }

    /// Used when a message may need multipart content (text + one or more
    /// images), and when passing through an already-decoded APIContent
    /// (e.g. echoing an assistant's own tool-call message back into history).
    init(role: String, content: APIContent?, toolCallId: String? = nil, toolCalls: [ToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }
}

/// Arguments expected for the web_search tool.
private struct WebSearchArguments: Decodable {
    let query: String
}

/// The full request body for `POST /chat/completions`.
struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [APIMessage]
    let stream: Bool
    let temperature: Double
    let maxTokens: Int?
    var tools: [ToolDefinition]? = nil
    /// Explicit tool-choice directive ("auto", "none", etc). Omitted when nil,
    /// which lets the API fall back to its own default ("auto"-like) behavior.
    /// Set to "none" to explicitly force a text-only answer — this is the
    /// documented, unambiguous way to disable tool calls, unlike simply
    /// omitting `tools`, which some providers (observed with Gemini) don't
    /// reliably honor as "don't call anything."
    var toolChoice: String? = nil

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, tools
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
    }
    
    // Explicit encode(to:) to ensure max_tokens/tool_choice are omitted entirely when nil
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encode(temperature, forKey: .temperature)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(toolChoice, forKey: .toolChoice)
    }
}

/// Top-level response from `POST /chat/completions` (non-streaming).
struct ChatCompletionResponse: Decodable {
    let id: String?
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let index: Int?
        let message: APIMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens     = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens      = "total_tokens"
        }
    }
}

/// Top-level response from `POST /chat/completions` (streaming).
struct ChatCompletionStreamResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
        let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }
}

// MARK: - Typed API Errors

enum APIError: LocalizedError {

    case invalidURL(String)
    case emptyModel
    case timedOut
    case httpError(statusCode: Int, serverMessage: String)
    case emptyResponse
    case decodingFailed(underlying: String)
    case networkFailure(underlying: Error)
    case cancelled
    case unsupportedToolFormat

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "'\(url)' is not a valid URL. Check Base URL in Settings."
        case .emptyModel:
            return "Model name is empty. Set it in Settings → Model."
        case .timedOut:
            return "The request timed out (120 s). The server may be overloaded or unreachable — please try again."
        case .httpError(let code, let msg):
            let detail = msg.isEmpty ? "" : "\n\n\(msg)"
            return "Server responded with HTTP \(code).\(detail)"
        case .emptyResponse:
            return "The server returned an empty response."
        case .decodingFailed(let reason):
            return "Could not parse the server response.\n\(reason)"
        case .networkFailure(let error):
            return "Network error: \(error.localizedDescription)"
        case .cancelled:
            return "Request was cancelled."
        case .unsupportedToolFormat:
            return "This model tried to use a tool in a way this app doesn't support. Try rephrasing your question, or disable web search for this model in Settings."
        }
    }
}

// MARK: - ChatAPIService

/// Stateless service — constructs and fires a single `POST /chat/completions`
/// request to any OpenAI-compatible endpoint.
///
/// Compatible with: OpenAI, Azure OpenAI (with correct base URL),
/// Ollama (`/v1/chat/completions`), LM Studio, Groq, Mistral, etc.
final class ChatAPIService {

    static let shared = ChatAPIService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        // Allow up to 120 s for the server to begin responding.
        // Long-context or slow model calls can take well over 60 s.
        config.timeoutIntervalForRequest  = 120
        // Give the full resource (incl. upload + download) up to 300 s.
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = ["User-Agent": "MinimalAIChat/1.0 iOS"]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Sends the full conversation history and returns the assistant reply text.
    ///
    /// - Parameters:
    ///   - messages: All `ChatMessage` values in the active session.
    ///   - settings: The live `SettingsViewModel` (Base URL, model, API key).
    /// - Returns: The trimmed text content of the first completion choice.
    /// - Throws: A typed `APIError` on any failure.
    func sendChatCompletion(
        messages: [ChatMessage],
        settings: SettingsViewModel,
        onSearchStarted: (@Sendable () -> Void)? = nil
    ) async throws -> String {

        // ── 1. Validate inputs ─────────────────────────────────────────────
        let trimmedBase = settings.baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedBase.isEmpty, let url = URL(string: trimmedBase + "/chat/completions") else {
            throw APIError.invalidURL(settings.baseURL)
        }

        let model = settings.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw APIError.emptyModel }

        // ── 2. Build system prompt ─────────────────────────────────────────
        // Read the username directly from UserDefaults at call time so the
        // value is always fresh, regardless of SettingsViewModel sync state.
        let defaultPrompt = ChatConstants.defaultSystemPrompt

        var basePrompt = UserDefaults.standard.string(forKey: "customSystemPrompt") ?? defaultPrompt
        if basePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            basePrompt = defaultPrompt
        }

        let savedName = UserDefaults.standard.string(forKey: "userName") ?? "User"

        // Dynamically replace the {name} placeholder with the actual saved name
        let personalityContent = basePrompt.replacingOccurrences(of: "{name}", with: savedName)

        // Generate today's date string for temporal grounding.
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        let todayString = dateFormatter.string(from: Date())

        // Temporal context is injected as a separate system message immediately
        // before the user's chat history so the model always has an accurate
        // date reference regardless of its training cut-off.
        let temporalContent = "You are a minimalist AI assistant. Today's date is \(todayString). Your temporal context must strictly be based on this current date."

        // ── 3. Build request body ──────────────────────────────────────────
        let combinedSystemContent = personalityContent + "\n\n" + temporalContent
        let systemMessage = APIMessage(role: "system", content: combinedSystemContent)

        let userMessages  = messages.map { APIMessage(role: $0.role.rawValue, content: apiContent(for: $0)) }
        let apiMessages   = [systemMessage] + userMessages

        let toolsToSend: [ToolDefinition]? = settings.hasTavilyKey ? [ToolDefinition.webSearch] : nil

        let body = ChatCompletionRequest(
            model: model,
            messages: apiMessages,
            stream: false,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens,
            tools: toolsToSend
        )

        let encoder = JSONEncoder()
        let bodyData: Data
        do {
            bodyData = try encoder.encode(body)
        } catch {
            throw APIError.networkFailure(underlying: error)
        }

        // ── 3. Assemble URLRequest ─────────────────────────────────────────
        var request = URLRequest(url: url)
        request.assumesHTTP3Capable = false
        request.httpMethod  = "POST"
        request.httpBody    = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        // ── 4. Fire request ────────────────────────────────────────────────
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw APIError.timedOut
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw APIError.cancelled
        } catch {
            throw APIError.networkFailure(underlying: error)
        }

        // ── 5. Validate HTTP status ────────────────────────────────────────
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            // Try to extract an error message from the response body
            let serverMsg = extractServerError(from: data)
            throw APIError.httpError(statusCode: http.statusCode, serverMessage: serverMsg)
        }

        // ── 6. Decode ─────────────────────────────────────────────────────
        guard !data.isEmpty else { throw APIError.emptyResponse }

        let decoder = JSONDecoder()
        let completion: ChatCompletionResponse
        do {
            completion = try decoder.decode(ChatCompletionResponse.self, from: data)
        } catch let decodingError as DecodingError {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw APIError.decodingFailed(underlying: "\(decodingError) | Raw body: \(raw.prefix(300))")
        }

        // ── 7. Handle Tool Calls or Return Text (bounded loop) ─────────────
        // Some providers (observed with Gemini via the OpenAI-compatible endpoint)
        // can request another web_search even when `tools` is omitted from the
        // follow-up request. A single rigid follow-up isn't enough for legitimate
        // multi-step lookups either (e.g. "what formation did each team use" needs
        // two separate searches). This loop allows a small, fixed number of search
        // rounds, then forces a final text answer on the last one.
        guard let firstMessage = completion.choices.first?.message else {
            throw APIError.emptyResponse
        }

        var currentMessages = apiMessages
        var pendingMessage = firstMessage
        let maxSearchRounds = 3
        var roundsUsed = 0
        var aggregatedSearchResults: [String] = []

        while let toolCalls = pendingMessage.toolCalls,
              toolCalls.contains(where: { $0.function.name == "web_search" }) {

            if roundsUsed == 0 {
                onSearchStarted?()
            }

            roundsUsed += 1

            // a. & b. Resolve EVERY tool call in this turn, not just the first.
            // The API requires exactly one 'tool' message per 'tool_call_id' that
            // appeared in the assistant message — sending back a mismatched count
            // (e.g. when the model requests two searches in the same turn) causes
            // a 400 ("insufficient tool messages following tool_calls message").
            var toolResultMessages: [APIMessage] = []

            for call in toolCalls {
                guard call.function.name == "web_search" else {
                    // Unrecognized/hallucinated tool call — still must respond so
                    // its tool_call_id isn't left unanswered.
                    toolResultMessages.append(
                        APIMessage(role: "tool", content: "This tool is not available.", toolCallId: call.id)
                    )
                    continue
                }

                var query = ""
                if let argumentsString = call.function.arguments,
                   let argsData = argumentsString.data(using: .utf8),
                   let args = try? decoder.decode(WebSearchArguments.self, from: argsData) {
                    query = args.query
                }

                var toolResultContent = ""
                do {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        throw URLError(.badURL) // generic failure if parsing failed
                    }
                    toolResultContent = try await TavilySearchService.shared.search(query: query, apiKey: settings.tavilyApiKey)
                } catch {
                    toolResultContent = "Web search failed: \(error.localizedDescription)"
                }

                aggregatedSearchResults.append(toolResultContent)

                toolResultMessages.append(
                    APIMessage(role: "tool", content: toolResultContent, toolCallId: call.id)
                )
            }

            // c. Append this round's assistant tool-calls + ALL matching tool results
            let assistantMessage = APIMessage(role: "assistant", content: pendingMessage.content, toolCalls: toolCalls)
            currentMessages += [assistantMessage] + toolResultMessages

            // On the last allowed round, keep the tool declared but explicitly forbid
            // using it via tool_choice: "none" — this is the documented, unambiguous
            // way to force a text-only answer. Simply omitting `tools` was tried
            // previously and isn't reliably honored by every provider.
            let isFinalRound = roundsUsed >= maxSearchRounds
            let followUpBody = ChatCompletionRequest(
                model: model,
                messages: currentMessages,
                stream: false,
                temperature: settings.temperature,
                maxTokens: settings.maxTokens,
                tools: [ToolDefinition.webSearch],
                toolChoice: isFinalRound ? "none" : nil
            )

            let followUpData: Data
            do {
                followUpData = try encoder.encode(followUpBody)
            } catch {
                throw APIError.networkFailure(underlying: error)
            }

            var followUpRequest = request
            followUpRequest.assumesHTTP3Capable = false
            followUpRequest.httpBody = followUpData

            // d. Send follow-up request
            let (followUpResponseData, followUpResponse): (Data, URLResponse)
            do {
                (followUpResponseData, followUpResponse) = try await session.data(for: followUpRequest)
            } catch let urlError as URLError where urlError.code == .timedOut {
                throw APIError.timedOut
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw APIError.cancelled
            } catch {
                throw APIError.networkFailure(underlying: error)
            }

            if let http2 = followUpResponse as? HTTPURLResponse, !(200..<300).contains(http2.statusCode) {
                let serverMsg = extractServerError(from: followUpResponseData)
                throw APIError.httpError(statusCode: http2.statusCode, serverMessage: serverMsg)
            }

            let followUpCompletion: ChatCompletionResponse
            do {
                followUpCompletion = try decoder.decode(ChatCompletionResponse.self, from: followUpResponseData)
            } catch let decodingError as DecodingError {
                let raw = String(data: followUpResponseData, encoding: .utf8) ?? "<binary>"
                throw APIError.decodingFailed(underlying: "\(decodingError) | Raw body: \(raw.prefix(300))")
            }

            guard let nextMessage = followUpCompletion.choices.first?.message else {
                throw APIError.emptyResponse
            }

            if let text = nextMessage.content?.plainText, !text.isEmpty {
                guard !looksLikeUnsupportedToolCallArtifact(text) else {
                    throw APIError.unsupportedToolFormat
                }
                return text
            }

            // No text yet. tool_choice: "none" was set on this round but Gemini
            // still returned another tool call — confirmed via testing that this
            // provider doesn't always honor it once a conversation is a few turns
            // deep into function-calling. Rather than give up, make one final,
            // completely separate plain-text request with no tool-calling shape
            // at all (no tools, no tool_choice, no prior assistant/tool turns) so
            // the model has nothing to pattern-match back into "call a tool" —
            // just a normal writing task using what was already found.
            if isFinalRound {
                let originalQuestion = messages.last(where: { $0.role == .user })?.content ?? ""
                let combinedFindings = aggregatedSearchResults.enumerated()
                    .map { "Search \($0.offset + 1) results:\n\($0.element)" }
                    .joined(separator: "\n\n")

                // NOTE: intentionally text-only — does not re-attach any image from
                // the original user message. Acceptable because this path only runs
                // when a provider ignores tool_choice: "none" on the final round.
                let synthesisPrompt = """
                Answer the user's question below using ONLY the search findings provided. \
                Do not attempt to search again — just write your best answer now, in plain text, \
                and say so if some details are still missing.

                User's question: \(originalQuestion)

                \(combinedFindings)
                """

                let synthesisMessages = [
                    systemMessage,
                    APIMessage(role: "user", content: synthesisPrompt)
                ]

                let synthesisBody = ChatCompletionRequest(
                    model: model,
                    messages: synthesisMessages,
                    stream: false,
                    temperature: settings.temperature,
                    maxTokens: settings.maxTokens,
                    tools: nil,
                    toolChoice: nil
                )

                let synthesisData: Data
                do {
                    synthesisData = try encoder.encode(synthesisBody)
                } catch {
                    throw APIError.networkFailure(underlying: error)
                }

                var synthesisRequest = request
                synthesisRequest.assumesHTTP3Capable = false
                synthesisRequest.httpBody = synthesisData

                let (synthesisResponseData, synthesisResponse): (Data, URLResponse)
                do {
                    (synthesisResponseData, synthesisResponse) = try await session.data(for: synthesisRequest)
                } catch let urlError as URLError where urlError.code == .timedOut {
                    throw APIError.timedOut
                } catch let urlError as URLError where urlError.code == .cancelled {
                    throw APIError.cancelled
                } catch {
                    throw APIError.networkFailure(underlying: error)
                }

                if let httpSynth = synthesisResponse as? HTTPURLResponse, !(200..<300).contains(httpSynth.statusCode) {
                    let serverMsg = extractServerError(from: synthesisResponseData)
                    throw APIError.httpError(statusCode: httpSynth.statusCode, serverMessage: serverMsg)
                }

                let synthesisCompletion: ChatCompletionResponse
                do {
                    synthesisCompletion = try decoder.decode(ChatCompletionResponse.self, from: synthesisResponseData)
                } catch let decodingError as DecodingError {
                    let raw = String(data: synthesisResponseData, encoding: .utf8) ?? "<binary>"
                    throw APIError.decodingFailed(underlying: "\(decodingError) | Raw body: \(raw.prefix(300))")
                }

                guard let synthesisText = synthesisCompletion.choices.first?.message.content?.plainText, !synthesisText.isEmpty else {
                    throw APIError.emptyResponse
                }
                guard !looksLikeUnsupportedToolCallArtifact(synthesisText) else {
                    throw APIError.unsupportedToolFormat
                }

                return synthesisText
            }

            pendingMessage = nextMessage
        }

        // No (further) tool call — return this message's text directly.
        guard let text = pendingMessage.content?.plainText, !text.isEmpty else {
            throw APIError.emptyResponse
        }
        guard !looksLikeUnsupportedToolCallArtifact(text) else {
            throw APIError.unsupportedToolFormat
        }
        return text
    }

    /// Sends the full conversation history and returns an async stream of assistant reply chunks.
    ///
    /// This method is only used for the no-search case (no Tavily key configured).
    /// It intentionally never declares tools and never handles tool calls — Gemini's
    /// streaming implementation breaks when a tool call is involved, which is why
    /// the search-enabled path goes through the non-streaming `sendChatCompletion()`
    /// instead. Keeping this method free of any tool-handling code prevents that
    /// already-documented bug from being reintroduced by accident later.
    ///
    /// - Parameters:
    ///   - messages: All `ChatMessage` values in the active session.
    ///   - settings: The live `SettingsViewModel` (Base URL, model, API key).
    /// - Returns: An `AsyncThrowingStream` yielding text deltas.
    func streamChatCompletion(
        messages: [ChatMessage],
        settings: SettingsViewModel
    ) -> AsyncThrowingStream<String, Error> {
        
        return AsyncThrowingStream { continuation in
            let innerTask = Task {
                do {
                    // ── 1. Validate inputs ─────────────────────────────────────────────
                    let trimmedBase = settings.baseURL
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    guard !trimmedBase.isEmpty, let url = URL(string: trimmedBase + "/chat/completions") else {
                        throw APIError.invalidURL(settings.baseURL)
                    }

                    let model = settings.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !model.isEmpty else { throw APIError.emptyModel }

                    // ── 2. Build system prompt ─────────────────────────────────────────
                    let defaultPrompt = ChatConstants.defaultSystemPrompt

                    var basePrompt = UserDefaults.standard.string(forKey: "customSystemPrompt") ?? defaultPrompt
                    if basePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        basePrompt = defaultPrompt
                    }

                    let savedName = UserDefaults.standard.string(forKey: "userName") ?? "User"
                    let personalityContent = basePrompt.replacingOccurrences(of: "{name}", with: savedName)

                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .long
                    let todayString = dateFormatter.string(from: Date())
                    let temporalContent = "You are a minimalist AI assistant. Today's date is \(todayString). Your temporal context must strictly be based on this current date."

                    // ── 3. Build request body ──────────────────────────────────────────
                    let combinedSystemContent = personalityContent + "\n\n" + temporalContent
                    let systemMessage = APIMessage(role: "system", content: combinedSystemContent)

                    let userMessages  = messages.map { APIMessage(role: $0.role.rawValue, content: apiContent(for: $0)) }
                    let apiMessages   = [systemMessage] + userMessages

                    // This method never declares tools — see the doc comment above.
                    let body = ChatCompletionRequest(
                        model: model,
                        messages: apiMessages,
                        stream: true,
                        temperature: settings.temperature,
                        maxTokens: settings.maxTokens,
                        tools: nil
                    )

                    let encoder = JSONEncoder()
                    let bodyData = try encoder.encode(body)

                    // ── 4. Assemble URLRequest ─────────────────────────────────────────
                    var request = URLRequest(url: url)
                    request.assumesHTTP3Capable = false
                    request.httpMethod  = "POST"
                    request.httpBody    = bodyData
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("application/json", forHTTPHeaderField: "Accept")

                    let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !apiKey.isEmpty {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }

                    // ── 5. Fire request ────────────────────────────────────────────────
                    let (result, response) = try await self.session.bytes(for: request)

                    // ── 6. Validate HTTP status ────────────────────────────────────────
                    if let http = response as? HTTPURLResponse,
                       !(200..<300).contains(http.statusCode) {
                        var errorData = Data()
                        for try await byte in result {
                            errorData.append(byte)
                        }
                        let serverMsg = self.extractServerError(from: errorData)
                        throw APIError.httpError(statusCode: http.statusCode, serverMessage: serverMsg)
                    }

                    // ── 7. Read Stream ─────────────────────────────────────────────────
                    let decoder = JSONDecoder()

                    for try await line in result.lines {
                        if Task.isCancelled {
                            throw APIError.cancelled
                        }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = line.dropFirst(6)
                        if payload == "[DONE]" {
                            break
                        }
                        if let data = payload.data(using: .utf8) {
                            do {
                                let chunk = try decoder.decode(ChatCompletionStreamResponse.self, from: data)
                                if let text = chunk.choices.first?.delta.content {
                                    continuation.yield(text)
                                }
                            } catch {
                                // Silently skip malformed SSE payloads — a single
                                // bad chunk shouldn't interrupt the stream.
                            }
                        }
                    }

                    continuation.finish()

                } catch let urlError as URLError where urlError.code == .timedOut {
                    continuation.finish(throwing: APIError.timedOut)
                } catch let urlError as URLError where urlError.code == .cancelled {
                    continuation.finish(throwing: APIError.cancelled)
                } catch let apiError as APIError {
                    continuation.finish(throwing: apiError)
                } catch {
                    continuation.finish(throwing: APIError.networkFailure(underlying: error))
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                innerTask.cancel()
            }
        }
    }

    // MARK: - Private Helpers

    /// Builds the OpenAI-compatible `content` value for a single ChatMessage,
    /// embedding any image attachments as base64 data URIs via
    /// ImageAttachmentManager. Messages without attachments encode as a plain
    /// string — identical to pre-vision behavior — so providers/models that
    /// never see an image are completely unaffected.
    private func apiContent(for message: ChatMessage) -> APIContent {
        // Build the combined plain-text portion first: the user's typed text,
        // plus the extracted text of any file attachments, each wrapped with
        // a clear delimiter so the model can tell where the attachment starts
        // and ends and what it's called.
        var textSegments: [String] = []
        if !message.content.isEmpty {
            textSegments.append(message.content)
        }
        for fileAttachment in message.fileAttachments {
            if let extractedText = FileAttachmentManager.loadText(fileAttachment) {
                textSegments.append("--- Attached file: \(fileAttachment.displayName) ---\n\(extractedText)\n--- End of \(fileAttachment.displayName) ---")
            }
        }
        let combinedText = textSegments.joined(separator: "\n\n")

        guard !message.imageAttachments.isEmpty else {
            return .text(combinedText)
        }

        var parts: [APIContent.Part] = []
        if !combinedText.isEmpty {
            parts.append(.text(combinedText))
        }
        for attachment in message.imageAttachments {
            if let dataURI = ImageAttachmentManager.dataURI(for: attachment) {
                parts.append(.imageURL(dataURI))
            }
        }
        // Fallback: if every attachment failed to load (e.g. file deleted
        // between save and send) and there's no text either, send a plain
        // text part rather than an empty parts array, which some providers
        // may reject outright.
        if parts.isEmpty {
            parts.append(.text(combinedText))
        }
        return .parts(parts)
    }

    /// Detects the non-standard, provider-specific "fake tool call" text some
    /// models (observed with DeepSeek) emit as plain content instead of a
    /// structured `tool_calls` response. Confirmed via a real raw response body
    /// that the actual text contains LITERAL SPACES between symbols, e.g.
    /// `< | | DSML | | tool_calls>` — not the tighter `<|DSML||tool_calls>`
    /// originally assumed. This syntax is undocumented, provider-specific, and
    /// its exact spacing isn't guaranteed to be stable, so the check below is
    /// whitespace-tolerant rather than relying on an exact substring match.
    private func looksLikeUnsupportedToolCallArtifact(_ text: String) -> Bool {
        let lowered = text.lowercased()

        // Strongest, most specific signal: "dsml" is extremely unlikely to
        // appear in any normal conversational answer, in any language, so its
        // mere presence is enough on its own.
        if lowered.contains("dsml") {
            return true
        }

        // Secondary, whitespace-tolerant structural check: strip all whitespace
        // before looking for the "<|" shape, so stray spaces between symbols
        // (as seen in the real DeepSeek output) don't defeat the match. This
        // also gives some coverage for similar-but-not-identical artifacts
        // from other providers that don't literally say "dsml".
        let compact = text.filter { !$0.isWhitespace }
        guard compact.contains("<|") else { return false }
        let loweredCompact = compact.lowercased()
        return loweredCompact.contains("tool_call") || loweredCompact.contains("invoke")
    }

    /// Attempts to parse `{"error":{"message":"..."}}` (OpenAI error format).
    private func extractServerError(from data: Data) -> String {
        struct ErrorWrapper: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        if let wrapper = try? JSONDecoder().decode(ErrorWrapper.self, from: data),
           let msg = wrapper.error?.message {
            return msg
        }
        return String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? ""
    }

}
