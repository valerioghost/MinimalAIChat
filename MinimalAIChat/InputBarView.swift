import SwiftUI

/// Bottom input bar: expanding TextEditor + send button.
struct InputBarView: View {

    @EnvironmentObject private var viewModel: ChatViewModel
    @FocusState private var isTextFieldFocused: Bool

    // Height constraints for the text editor
    private let minHeight: CGFloat = 38
    private let maxHeight: CGFloat = 120

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {

            // ── Dynamic Text Input ────────────────────────────────────────
            ZStack(alignment: .leading) {
                // Placeholder
                if viewModel.inputText.isEmpty {
                    Text("Message")
                        .foregroundColor(Color(.placeholderText))
                        .font(.system(size: 16))
                        .padding(.leading, 6)
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                }

                // TextEditor grows up to maxHeight, then scrolls internally
                TextEditor(text: $viewModel.inputText)
                    .font(.system(size: 16))
                    .frame(minHeight: minHeight, maxHeight: maxHeight)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($isTextFieldFocused)
                    .scrollContentBackgroundHidden()   // custom extension below
                    .padding(.vertical, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            // ── Send Button ───────────────────────────────────────────────
            Button(action: sendTapped) {
                ZStack {
                    Circle()
                        .fill(canSend ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(width: 38, height: 38)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(canSend ? .white : Color(.tertiaryLabel))
                }
            }
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.15), value: canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: -2)
        )
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !viewModel.isTyping
    }

    private func sendTapped() {
        viewModel.sendMessage()
        // Dismiss the keyboard immediately when the user sends a message.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        isTextFieldFocused = true
    }
}

// MARK: - ScrollContentBackground helper (iOS 16 compat shim)

private extension View {
    /// On iOS 16+ hides the TextEditor default background.
    /// On iOS 15, we replicate the effect by making the background clear via UITextView appearance.
    func scrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            return AnyView(self.scrollContentBackground(.hidden))
        } else {
            return AnyView(self.onAppear {
                UITextView.appearance().backgroundColor = .clear
            })
        }
    }
}

// MARK: - Preview

struct InputBarView_Previews: PreviewProvider {
    static var previews: some View {
        let settings = SettingsViewModel()
        VStack {
            Spacer()
            InputBarView()
        }
        .environmentObject(ChatViewModel(settings: settings))
        .ignoresSafeArea(edges: .bottom)
    }
}
