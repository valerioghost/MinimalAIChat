import Foundation

enum ChatConstants {
    static let defaultSystemPrompt = "You are a helpful AI assistant. The user's name is {name}. Address the user by their name when appropriate, and be concise, friendly, and accurate.\n\nCRITICAL FORMATTING RULE: Every distinct item in a list MUST be on its own line, with a line break before it. Never write two list items on the same line or run them together. For example, when listing ingredients, format them exactly like this:\n\n**Ingredients:**\n- Pasta: 200g\n- Guanciale: 100g\n- Egg yolks: 3\n\nNOT like this (never do this):\nIngredients:Pasta: 200gGuanciale: 100gEgg yolks: 3\n\nApply this same one-item-per-line rule to numbered steps, sections, and any other list content. Use Markdown bold for headers or key terms."
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
    var imageAttachments: [ImageAttachment]
    var fileAttachments: [FileAttachment]
    var isWelcomeMessage: Bool

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, isError, isComplete, imageAttachments, fileAttachments, isWelcomeMessage
    }

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), isError: Bool = false, isComplete: Bool = true, imageAttachments: [ImageAttachment] = [], fileAttachments: [FileAttachment] = [], isWelcomeMessage: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isError = isError
        self.isComplete = isComplete
        self.imageAttachments = imageAttachments
        self.fileAttachments = fileAttachments
        self.isWelcomeMessage = isWelcomeMessage
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
        // Default []: old persisted messages predate the vision feature and had no attachments
        imageAttachments = try container.decodeIfPresent([ImageAttachment].self, forKey: .imageAttachments) ?? []
        // Default []: old persisted messages predate the file-attachments feature
        fileAttachments = try container.decodeIfPresent([FileAttachment].self, forKey: .fileAttachments) ?? []
        // Default false: old persisted messages predate this flag; treating them
        // as non-welcome messages is safe since only genuinely new welcome
        // messages need the copy button hidden going forward.
        isWelcomeMessage = try container.decodeIfPresent(Bool.self, forKey: .isWelcomeMessage) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isError, forKey: .isError)
        try container.encode(isComplete, forKey: .isComplete)
        try container.encode(imageAttachments, forKey: .imageAttachments)
        try container.encode(fileAttachments, forKey: .fileAttachments)
        try container.encode(isWelcomeMessage, forKey: .isWelcomeMessage)
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
