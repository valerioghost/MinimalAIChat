import Foundation

// MARK: - OpenAI-Compatible Request / Response Models

/// A single message in the `messages` array sent to the API.
struct APIMessage: Codable {
    let role: String
    let content: String
}

/// The full request body for `POST /chat/completions`.
struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [APIMessage]
    let stream: Bool

    // Explicit CodingKeys so `stream` is always serialised even if false.
    enum CodingKeys: String, CodingKey {
        case model, messages, stream
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
        settings: SettingsViewModel
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
        let defaultPrompt = "You are a helpful AI assistant. The user's name is {name}. Address the user by their name when appropriate, and be concise, friendly, and accurate."

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
        // System messages are always first — personality, then temporal context.
        let personalityMessage = APIMessage(role: "system", content: personalityContent)
        let temporalMessage    = APIMessage(role: "system", content: temporalContent)

        let userMessages  = messages.map { APIMessage(role: $0.role.rawValue, content: $0.content) }
        let apiMessages   = [personalityMessage, temporalMessage] + userMessages

        let body = ChatCompletionRequest(
            model: model,
            messages: apiMessages,
            stream: false
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
        do {
            let completion = try decoder.decode(ChatCompletionResponse.self, from: data)
            guard let text = completion.choices.first?.message.content, !text.isEmpty else {
                throw APIError.emptyResponse
            }
            return text
        } catch let decodingError as DecodingError {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw APIError.decodingFailed(underlying: "\(decodingError) | Raw body: \(raw.prefix(300))")
        }
    }

    // MARK: - Private Helpers

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
