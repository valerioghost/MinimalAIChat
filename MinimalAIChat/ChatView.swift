import SwiftUI
import Combine

/// Main chat screen: scrollable message list + bottom input bar.
struct ChatView: View {

    @EnvironmentObject private var viewModel: ChatViewModel
    @Binding var isMenuOpen: Bool

    // Scroll proxy anchor
    private let bottomAnchor = "BOTTOM_ANCHOR"

    /// Publishes keyboard frame changes so we can auto-scroll when it appears.
    @State private var keyboardHeight: CGFloat = 0

    /// Tracks the ID of the last message whose content we've already seen become
    /// non-empty. Used to distinguish "this message's content just appeared for
    /// the first time" (instant/Tavily replies, or the very first streaming
    /// token) from "this message is still growing" (subsequent streaming
    /// chunks), so each case can scroll appropriately — see the content-change
    /// handler below.
    @State private var lastSeenNonEmptyMessageID: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {

            // ── Message List ──────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    // ⚠️  VStack, NOT LazyVStack.
                    // LazyVStack de-realises off-screen rows and loses their
                    // heights, causing scrollTo to jump to stale positions
                    // whenever content grows in place (streaming / regenerate).
                    VStack(spacing: 8) {
                        ForEach(viewModel.activeMessages) { message in
                            MessageBubbleView(message: message, isSearching: viewModel.isSearchingWeb)
                                .id(message.id)
                        }

                        if viewModel.canRetry {
                            Button(action: {
                                viewModel.retryLastReply()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry")
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color(.secondarySystemBackground)))
                                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                            }
                            .padding(.top, 4)
                            .id("retryButton")
                        }

                        // Stable, non-zero anchor at the very bottom.
                        // GeometryReader gives it a concrete frame so
                        // scrollTo never targets a zero-height phantom.
                        GeometryReader { _ in Color.clear }
                            .frame(height: 1)
                            .id(bottomAnchor)
                    }
                    .padding(.vertical, 12)
                    // Keep padding at the very bottom so the last bubble
                    // is never hidden behind the input bar.
                    .padding(.bottom, 8)
                }
                .background(Color(.systemBackground))
                // Tapping anywhere in the message area dismisses the keyboard.
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }

                // ── Auto-scroll triggers ──────────────────────────────────

                // New message appended (count changes)
                .onChange(of: viewModel.activeMessages.count) { _ in
                    scrollToBottom(proxy: proxy, animated: true)
                }
                // Last message content updated in place (streaming tokens, or a
                // single instant update for the non-streaming Tavily path). The
                // first time a message's content becomes non-empty, jump to the
                // TOP of that specific message instead of the bottom anchor —
                // this matters most for instant replies, where the full text
                // appears in one step and landing at the very bottom would
                // otherwise hide the beginning of a long answer. Subsequent
                // updates to the same message (streaming growth) keep scrolling
                // toward the bottom exactly as before.
                .onChange(of: viewModel.activeMessages.last?.content) { newContent in
                    guard let lastMessage = viewModel.activeMessages.last,
                          let newContent = newContent,
                          !newContent.isEmpty else { return }

                    if lastSeenNonEmptyMessageID != lastMessage.id {
                        lastSeenNonEmptyMessageID = lastMessage.id
                        // Defer by one run-loop tick so SwiftUI has finished laying
                        // out this row at its new (much taller) height before we
                        // scroll — otherwise scrollTo computes its target using the
                        // row's stale, near-empty-placeholder height and the view
                        // still lands close to the bottom. Same pattern already
                        // used below for the keyboard-appearance and initial-render
                        // scroll calls in this same file.
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.2)) {
                                // Slightly negative y instead of exact .top (y: 0) —
                                // gives a little breathing room above the message
                                // instead of landing it flush against the nav bar.
                                proxy.scrollTo(lastMessage.id, anchor: UnitPoint(x: 0.5, y: -0.03))
                            }
                        }
                    } else {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                // Typing indicator toggled
                .onChange(of: viewModel.isTyping) { _ in
                    scrollToBottom(proxy: proxy, animated: true)
                }
                // Session switched — instant jump, no animation. Deferred by
                // one run-loop tick so SwiftUI has finished laying out the
                // NEW session's message list (which can be a very different
                // size than the previous one) before we scroll — otherwise
                // scrollTo computes its target against the stale, previous
                // session's geometry and visibly "bounces" once the real
                // layout commits a frame later. Same pattern already used
                // elsewhere in this file (content-growth and keyboard
                // scrolls).
                .onChange(of: viewModel.activeSessionID) { _ in
                    lastSeenNonEmptyMessageID = nil
                    DispatchQueue.main.async {
                        proxy.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                }
                // Keyboard appeared — defer one frame so the layout has
                // already inset the scroll view before we scroll
                .onChange(of: keyboardHeight) { newHeight in
                    if newHeight > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(bottomAnchor, anchor: .bottom)
                            }
                        }
                    }
                }
                // Initial render — defer one frame so VStack has measured itself
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                }
            }

            Divider()

            // ── Input Bar ─────────────────────────────────────────────────
            InputBarView()
        }
        .background(Color(.systemBackground))
        // ── Restore persisted sessions on first render ─────────────────────
        .onAppear {
            viewModel.loadSessions()
        }
        // ── Keyboard height tracking (iOS 15 — uses NotificationCenter) ──
        .onReceive(keyboardPublisher) { height in
            keyboardHeight = height
        }
        // ── Error Alert ───────────────────────────────────────────────────
        // Shows whenever the VM surfaces a typed APIError.
        // Uses the iOS 15-safe Alert(isPresented:) API.
        .alert(isPresented: errorAlertBinding) {
            buildErrorAlert()
        }
    }

    // MARK: - Scroll Helper

    /// Scrolls to the stable bottom anchor.
    /// - Parameter animated: pass `false` for in-place content updates (streaming)
    ///   to avoid the jitter caused by animating every individual token append.
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    // MARK: - Error Alert Helpers

    /// Binding<Bool> derived from viewModel.lastError so alert dismissal clears the error.
    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.lastError != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    private func buildErrorAlert() -> Alert {
        let error = viewModel.lastError

        // Special-case common errors with tailored recovery suggestions
        let (title, message, action): (String, String, String) = {
            switch error {
            case .invalidURL:
                return ("Invalid Endpoint", error?.errorDescription ?? "", "Open Settings")
            case .emptyModel:
                return ("Model Not Set", error?.errorDescription ?? "", "Open Settings")
            case .httpError(let code, _) where code == 401:
                return ("Unauthorized", "Your API key was rejected by the server. Please check it in Settings.", "Open Settings")
            case .httpError(let code, _) where code == 429:
                return ("Rate Limited", "You have exceeded your API quota. Please wait before retrying.", "OK")
            case .networkFailure:
                return ("Network Error", error?.errorDescription ?? "Check your internet connection.", "OK")
            default:
                return ("Request Failed", error?.errorDescription ?? "An unexpected error occurred.", "OK")
            }
        }()

        if action == "Open Settings" {
            // On iOS 15 we can open the app's Settings URL
            return Alert(
                title: Text(title),
                message: Text(message),
                primaryButton: .default(Text(action)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    viewModel.dismissError()
                },
                secondaryButton: .cancel(Text("Dismiss")) {
                    viewModel.dismissError()
                }
            )
        } else {
            return Alert(
                title: Text(title),
                message: Text(message),
                dismissButton: .default(Text(action)) {
                    viewModel.dismissError()
                }
            )
        }
    }

    // MARK: - Keyboard Publisher

    /// Emits the keyboard height whenever it appears, and 0 when it hides.
    /// Uses UIResponder notifications — available on all iOS 15+ devices.
    private var keyboardPublisher: AnyPublisher<CGFloat, Never> {
        let willShow = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { note -> CGFloat? in
                (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height
            }

        let willHide = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }

        return Publishers.Merge(willShow, willHide)
            .eraseToAnyPublisher()
    }
}

// MARK: - Preview

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        let settings = SettingsViewModel()
        ChatView(isMenuOpen: .constant(false))
            .environmentObject(ChatViewModel(settings: settings))
    }
}
