import SwiftUI

/// Sliding side menu — shows chat history sessions and a "New Chat" button.
struct SideMenuView: View {

    @EnvironmentObject private var viewModel: ChatViewModel
    @EnvironmentObject private var settings: SettingsViewModel
    @Binding var isMenuOpen: Bool

    @AppStorage("userName") private var userName: String = ""
    @State private var showClearAlert: Bool = false
    @State private var isShowingMasterSettings: Bool = false

    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Header ────────────────────────────────────────────────
                menuHeader

                Divider()
                    .padding(.vertical, 8)

                // ── New Chat Button ────────────────────────────────────────
                newChatButton

                // ── Clear Chat Button ─────────────────────────────────────
                clearChatButton

                // ── Section Title ─────────────────────────────────────────
                Text("Recent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 6)

                // ── Session List ──────────────────────────────────────────
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.sessions) { session in
                            SessionRowView(
                                session: session,
                                isActive: session.id == viewModel.activeSessionID
                            ) {
                                viewModel.selectSession(session)
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isMenuOpen = false
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }

                Spacer()

                Divider()

                // ── Footer ────────────────────────────────────────────────
                menuFooter
            }
        }
        .sheet(isPresented: $isShowingMasterSettings) {
            MasterSettingsView()
                .environmentObject(settings)
        }
        // ── Clear Chat confirmation alert ─────────────────────────────────
        .alert(isPresented: $showClearAlert) {
            Alert(
                title: Text("Delete Chat"),
                message: Text("This chat will be permanently removed from your history."),
                primaryButton: .destructive(Text("Delete")) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isMenuOpen = false
                    }
                    // Small delay so the menu slides away before the list updates
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        viewModel.deleteCurrentSession()
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Sub-views

    private var menuHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 38, height: 38)
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("MinimalAI")
                    .font(.system(size: 17, weight: .bold))
                Text("Your AI assistant")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var newChatButton: some View {
        Button {
            viewModel.startNewChat()
            withAnimation(.easeInOut(duration: 0.3)) {
                isMenuOpen = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                Text("New Chat")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
            }
            .foregroundColor(.accentColor)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private var clearChatButton: some View {
        Button {
            showClearAlert = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 22)
                Text("Delete Chat")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
            }
            .foregroundColor(Color(.systemRed))
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background(Color(.systemRed).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private var menuFooter: some View {
        Button {
            isShowingMasterSettings = true
        } label: {
            HStack(spacing: 14) {
                // Avatar: first character of the user's name, or a person icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                    if userName.isEmpty {
                        Image(systemName: "person")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.accentColor)
                    } else {
                        Text(String(userName.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(userName.isEmpty ? "Set up your name" : userName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(userName.isEmpty ? .secondary : .primary)
                    Text("Personal Plan")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            // A clear background ensures the entire area is tappable
            .background(Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Row

struct SessionRowView: View {

    let session: ChatSession
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? .accentColor : .primary)
                        .lineLimit(1)

                    Text(relativeDate(session.lastUpdated))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                isActive
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview

struct SideMenuView_Previews: PreviewProvider {
    static var previews: some View {
        let settings = SettingsViewModel()
        SideMenuView(isMenuOpen: .constant(true))
            .environmentObject(ChatViewModel(settings: settings))
            .frame(width: 280)
            .previewLayout(.sizeThatFits)
    }
}
