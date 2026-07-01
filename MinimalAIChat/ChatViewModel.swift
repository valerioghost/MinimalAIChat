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
    /// Non-nil whenever the last API call failed. Cleared on the next successful send.
    @Published var lastError: APIError? = nil

    // MARK: - Dependencies

    private var settings: SettingsViewModel
    private let apiService = ChatAPIService.shared

    /// UserDefaults key under which the full session list is stored as JSON.
    private static let sessionsKey = "persistedChatSessions"

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

    // MARK: - Actions

    /// Validates input, appends the user message, and fires the network request.
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


    /// Dismisses the current error alert (called from the view's alert handler).
    func dismissError() {
        lastError = nil
    }

    // MARK: - Network

    private func fetchAssistantReply() async {
        isTyping = true

        // Snapshot messages so switching session mid-flight doesn't corrupt state
        let messagesToSend = activeMessages
        let sessionIDAtDispatch = activeSessionID

        do {
            let reply = try await apiService.sendChatCompletion(
                messages: messagesToSend,
                settings: settings
            )

            // Only apply the reply if the user hasn't switched sessions
            guard !Task.isCancelled, activeSessionID == sessionIDAtDispatch else { return }

            isTyping = false
            appendMessage(ChatMessage(role: .assistant, content: reply), toSession: sessionIDAtDispatch)

        } catch APIError.cancelled {
            // Silently swallow cancellations — the user switched sessions or view
            isTyping = false

        } catch {
            guard !Task.isCancelled, activeSessionID == sessionIDAtDispatch else { return }
            isTyping = false

            // Surface as typed error for the alert
            lastError = error as? APIError ?? APIError.networkFailure(underlying: error)

            // Also append an inline error bubble for in-context feedback
            let errorText = buildErrorMessage(for: error)
            appendMessage(ChatMessage(role: .assistant, content: errorText), toSession: sessionIDAtDispatch)
        }
    }

    // MARK: - Private Helpers

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

        sessions = saved

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
}
