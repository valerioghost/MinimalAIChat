import Foundation

enum ChatConstants {
    static let defaultSystemPrompt = "You are a helpful AI assistant. The user's name is {name}. Address the user by their name when appropriate, and be concise, friendly, and accurate."
}

// MARK: - Message Role

enum MessageRole: String, Codable {
    case user      = "user"
    case assistant = "assistant"
    case system    = "system"    // reserved for future system prompts
}

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var isError: Bool
    var isComplete: Bool

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, isError, isComplete
    }

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), isError: Bool = false, isComplete: Bool = true) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isError = isError
        self.isComplete = isComplete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        // Default true: old persisted messages were always fully completed replies
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isError, forKey: .isError)
        try container.encode(isComplete, forKey: .isComplete)
    }
}

// MARK: - ChatSession

struct ChatSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var lastUpdated: Date

    init(id: UUID = UUID(), title: String, messages: [ChatMessage] = [], lastUpdated: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.lastUpdated = lastUpdated
    }
}


// MARK: - Mock Data

extension ChatSession {
    static let mockSessions: [ChatSession] = []
}
