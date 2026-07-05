import Foundation
import Combine

// MARK: - ChatViewModel

/// Owns all session/message state and drives the API layer.
///
/// Marked `@MainActor` so every `@Published` mutation is guaranteed to happen
/// on the main thread — required by SwiftUI's `ObservableObject` on iOS 15.
/// async/await calls inside Tasks automatically hop to background threads
/// during I/O, then resume on the main actor when writing results back.
@MainActor
final class ChatViewModel: ObservableObject {

    // MARK: - Published State

    @Published var sessions: [ChatSession]
    @Published var activeSessionID: UUID
    @Published var inputText: String = ""
    @Published var isTyping: Bool = false
    @Published private(set) var isStreamingActive: Bool = false
    /// Non-nil whenever the last API call failed. Cleared on the next successful send.
    @Published var lastError: APIError? = nil

    // MARK: - Dependencies

    private var settings: SettingsViewModel
    private let apiService = ChatAPIService.shared

    /// UserDefaults key under which the full session list is stored as JSON.
    private static let sessionsKey = "persistedChatSessions"
    
    /// Maximum character count to send to the API per request, preventing unbounded growth.
    private var historyCharacterBudget: Int { settings.historyCharacterBudget }

    /// Handle to the in-flight network task so it can be cancelled on session switch.
    private var currentTask: Task<Void, Never>?

    // MARK: - Init

    init(settings: SettingsViewModel) {
        self.settings = settings

        var loadedSessions: [ChatSession] = []
        if let data = UserDefaults.standard.data(forKey: Self.sessionsKey),
           let saved = try? JSONDecoder().decode([ChatSession].self, from: data),
           !saved.isEmpty {
            // Clean up any stale, empty "New Chat" sessions from previous launches
            // so we don't accumulate an endless list of unused chats.
            loadedSessions = saved.filter { session in
                !(session.title == "New Chat" && session.messages.count <= 1)
            }
            
            let initialCount = loadedSessions.reduce(0) { $0 + $1.messages.count }
            loadedSessions = Self.purgeStuckPlaceholders(in: loadedSessions)
            if loadedSessions.reduce(0, { $0 + $1.messages.count }) < initialCount {
                if let data = try? JSONEncoder().encode(loadedSessions) {
                    UserDefaults.standard.set(data, forKey: Self.sessionsKey)
                }
            }
        }

        // Always start with a fresh welcoming session on launch
        let fresh = ChatSession(title: "New Chat", messages: [
            ChatMessage(
                role: .assistant,
                content: "Hello! I'm your AI assistant. How can I help you today? 👋"
            )
        ])
        loadedSessions.insert(fresh, at: 0)
        
        self.sessions = loadedSessions
        self.activeSessionID = fresh.id
        
        // Persist immediately so that ChatView's .onAppear loadSessions() hook 
        // doesn't overwrite this fresh state.
        if let data = try? JSONEncoder().encode(self.sessions) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
        }
    }

    /// Called by RootView once both @StateObjects are fully live in SwiftUI's
    /// graph. Replaces the temporary SettingsViewModel created during App init
    /// with the real shared instance.
    func configure(settings: SettingsViewModel) {
        self.settings = settings
    }

    // MARK: - Computed Helpers

    var activeSession: ChatSession? {
        sessions.first { $0.id == activeSessionID }
    }

    var activeMessages: [ChatMessage] {
        activeSession?.messages ?? []
    }

    var canRetry: Bool {
        !isTyping && !isStreamingActive && (
            activeMessages.last?.role == .user ||
            activeMessages.last?.isError == true ||
            (activeMessages.last?.role == .assistant && activeMessages.last?.isComplete == false)
        )
    }

    // MARK: - Actions

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTyping else { return }

        inputText = ""
        appendMessage(ChatMessage(role: .user, content: text))

        // Cancel any stale in-flight request before starting a new one
        currentTask?.cancel()
        currentTask = Task {
            await fetchAssistantReply()
        }
    }

    /// Retries the last user request (or re-attempts after an error or interrupted stream).
    func retryLastReply() {
        guard canRetry else { return }

        if let lastMsg = activeMessages.last, lastMsg.role == .assistant {
            // Remove both error bubbles AND incomplete partial replies before retrying
            if lastMsg.isError || !lastMsg.isComplete {
                if let sessionIdx = sessions.firstIndex(where: { $0.id == activeSessionID }) {
                    sessions[sessionIdx].messages.removeAll(where: { $0.id == lastMsg.id })
                    persistSessions()
                }
            }
        }

        currentTask?.cancel()
        currentTask = Task {
            await fetchAssistantReply()
        }
    }

    /// Creates and activates a brand-new chat session, cancelling any in-flight request.
    func startNewChat() {
        currentTask?.cancel()
        isTyping = false
        let session = ChatSession(title: "New Chat", messages: [
            ChatMessage(
                role: .assistant,
                content: "Hello! I'm your AI assistant. How can I help you today? 👋"
            )
        ])
        sessions.insert(session, at: 0)
        activeSessionID = session.id
        persistSessions()
    }

    /// Switches to an existing session, cancelling any in-flight request.
    func selectSession(_ session: ChatSession) {
        currentTask?.cancel()
        isTyping = false
        activeSessionID = session.id
    }

    /// Deletes the active session entirely and switches to the next available one.
    /// If no other session exists a fresh "New Chat" is created automatically.
    func deleteCurrentSession() {
        currentTask?.cancel()
        isTyping = false

        // Remove the active session
        sessions.removeAll { $0.id == activeSessionID }

        // Activate the first remaining session, or create a brand-new one
        if let next = sessions.first {
            activeSessionID = next.id
        } else {
            startNewChat()  // startNewChat() already calls persistSessions()
            return
        }
        persistSessions()
    }

    /// Cancels any in-flight API request. Call this when backgrounding the app.
    func cancelInFlightTask() {
        currentTask?.cancel()
    }

    /// Dismisses the current error alert (called from the view's alert handler).
    func dismissError() {
        lastError = nil
    }

    // MARK: - Network

    private func fetchAssistantReply() async {
        isTyping = true
        isStreamingActive = true

        // Snapshot messages so switching session mid-flight doesn't corrupt state
        let messagesToSend = trimmedHistory(from: activeMessages)
        let sessionIDAtDispatch = activeSessionID

        // Placeholder starts as incomplete; only the clean-finish path marks it done
        let initialMessage = ChatMessage(role: .assistant, content: "", isComplete: false)
        appendMessage(initialMessage, toSession: sessionIDAtDispatch)
        let messageID = initialMessage.id

        let stream = apiService.streamChatCompletion(
            messages: messagesToSend,
            settings: settings
        )

        var firstChunkReceived = false
        var chunkCount = 0

        do {
            for try await chunk in stream {
                // Check cancellation *before* modifying state
                guard !Task.isCancelled else {
                    cleanupPartialMessage(messageID: messageID, inSession: sessionIDAtDispatch, wasCancelled: true)
                    isStreamingActive = false
                    return
                }
                
                // If the user just switched sessions, stop streaming
                guard activeSessionID == sessionIDAtDispatch else {
                    cleanupPartialMessage(messageID: messageID, inSession: sessionIDAtDispatch, wasCancelled: true)
                    isStreamingActive = false
                    return
                }

                if !firstChunkReceived {
                    isTyping = false
                    firstChunkReceived = true
                }

                if let sessionIdx = sessions.firstIndex(where: { $0.id == sessionIDAtDispatch }),
                   let msgIdx = sessions[sessionIdx].messages.firstIndex(where: { $0.id == messageID }) {
                    
                    sessions[sessionIdx].messages[msgIdx].content += chunk
                    sessions[sessionIdx].lastUpdated = Date()
                    
                    chunkCount += 1
                    // Throttle persistence to avoid excessive disk I/O on every token
                    if chunkCount % 10 == 0 {
                        persistSessions()
                    }
                }
            }
            
            if !firstChunkReceived {
                isTyping = false
            }

            // Mark the message complete BEFORE cleanup, so persisted state is correct
            if let sessionIdx = sessions.firstIndex(where: { $0.id == sessionIDAtDispatch }),
               let msgIdx = sessions[sessionIdx].messages.firstIndex(where: { $0.id == messageID }) {
                sessions[sessionIdx].messages[msgIdx].isComplete = true
            }

            // Final cleanup for the clean-finish case
            cleanupPartialMessage(messageID: messageID, inSession: sessionIDAtDispatch, wasCancelled: false)
            isStreamingActive = false

        } catch APIError.cancelled {
            // Silently swallow cancellations — the user switched sessions or view
            isTyping = false
            cleanupPartialMessage(messageID: messageID, inSession: sessionIDAtDispatch, wasCancelled: true)
            isStreamingActive = false

        } catch {
            guard !Task.isCancelled else {
                cleanupPartialMessage(messageID: messageID, inSession: sessionIDAtDispatch, wasCancelled: true)
                isStreamingActive = false
                return 
            }
            guard activeSessionID == sessionIDAtDispatch else {
                cleanupPartialMessage(messageID: messageID, inSession: sessionIDAtDispatch, wasCancelled: true)
                isStreamingActive = false
                return 
            }
            
            isTyping = false
            cleanupPartialMessage(messageID: messageID, inSession: sessionIDAtDispatch, wasCancelled: false)

            // Surface as typed error for the alert
            lastError = error as? APIError ?? APIError.networkFailure(underlying: error)

            // Also append an inline error bubble for in-context feedback
            let errorText = buildErrorMessage(for: error)
            appendMessage(ChatMessage(role: .assistant, content: errorText, isError: true), toSession: sessionIDAtDispatch)
            isStreamingActive = false
        }
    }

    private func cleanupPartialMessage(messageID: UUID, inSession sessionID: UUID, wasCancelled: Bool) {
        guard let sessionIdx = sessions.firstIndex(where: { $0.id == sessionID }),
              let msgIdx = sessions[sessionIdx].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        let content = sessions[sessionIdx].messages[msgIdx].content

        if content.isEmpty {
            // Remove the empty placeholder bubble completely
            sessions[sessionIdx].messages.remove(at: msgIdx)
        } else if wasCancelled {
            // Keep the partial text but mark it as interrupted
            sessions[sessionIdx].messages[msgIdx].content += " [interrupted]"
        }

        sessions[sessionIdx].lastUpdated = Date()
        persistSessions()
    }

    // MARK: - Private Helpers

    /// Returns a subset of recent messages whose total character count fits within the budget.
    /// Guarantees that at least the single most recent message is included, regardless of length.
    private func trimmedHistory(from messages: [ChatMessage]) -> [ChatMessage] {
        guard !messages.isEmpty else { return [] }
        
        var result: [ChatMessage] = []
        var currentLength = 0
        
        for message in messages.reversed() {
            let length = message.content.count
            
            // Stop if adding this message exceeds budget AND we already have at least one message
            if currentLength + length > historyCharacterBudget && !result.isEmpty {
                break
            }
            
            result.insert(message, at: 0)
            currentLength += length
        }
        
        return result
    }

    private func appendMessage(_ message: ChatMessage, toSession sessionID: UUID? = nil) {
        let targetID = sessionID ?? activeSessionID
        guard let idx = sessions.firstIndex(where: { $0.id == targetID }) else { return }
        sessions[idx].messages.append(message)
        sessions[idx].lastUpdated = Date()

        // Auto-title the session from the first user message
        if message.role == .user && sessions[idx].title == "New Chat" {
            let words = message.content
                .split(separator: " ")
                .prefix(5)
                .joined(separator: " ")
            sessions[idx].title = words.isEmpty ? "New Chat" : words
        }

        persistSessions()
    }

    // MARK: - Persistence

    /// Encodes the full sessions array to JSON and writes it to UserDefaults.
    private func persistSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
        }
    }

    /// Decodes the sessions array from UserDefaults and restores state.
    /// Called from ChatView's .onAppear to re-hydrate after a view re-mount.
    /// Safe to call repeatedly — no-ops if nothing is stored or decoding fails.
    func loadSessions() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.sessionsKey),
            let saved = try? JSONDecoder().decode([ChatSession].self, from: data),
            !saved.isEmpty
        else { return }

        let initialCount = saved.reduce(0) { $0 + $1.messages.count }
        let purged = Self.purgeStuckPlaceholders(in: saved)
        sessions = purged

        if purged.reduce(0, { $0 + $1.messages.count }) < initialCount {
            persistSessions()
        }

        // Keep the active session pointer valid; fall back to the most recent one.
        if !sessions.contains(where: { $0.id == activeSessionID }) {
            activeSessionID = sessions[0].id
        }
    }

    /// Converts a caught error into a user-friendly assistant message.
    private func buildErrorMessage(for error: Error) -> String {
        if let apiError = error as? APIError,
           let description = apiError.errorDescription {
            return "⚠️ \(description)"
        }
        return "⚠️ An unexpected error occurred: \(error.localizedDescription)"
    }

    /// Removes any empty assistant messages that were orphaned by a hard app termination mid-stream.
    private static func purgeStuckPlaceholders(in sessions: [ChatSession]) -> [ChatSession] {
        return sessions.map { session in
            var updated = session
            updated.messages.removeAll { $0.role == .assistant && $0.content.isEmpty }
            return updated
        }
    }
}
