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
                            MessageBubbleView(message: message)
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
                // Last message content updated in place (streaming tokens)
                .onChange(of: viewModel.activeMessages.last?.content) { _ in
                    scrollToBottom(proxy: proxy, animated: false)
                }
                // Typing indicator toggled
                .onChange(of: viewModel.isTyping) { _ in
                    scrollToBottom(proxy: proxy, animated: true)
                }
                // Session switched — instant jump, no animation
                .onChange(of: viewModel.activeSessionID) { _ in
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
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
