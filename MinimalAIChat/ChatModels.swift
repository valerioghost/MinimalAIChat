import Foundation

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
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
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
