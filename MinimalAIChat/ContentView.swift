import SwiftUI

/// Root view — owns the NavigationView + sliding side menu overlay.
struct ContentView: View {

    @EnvironmentObject private var viewModel: ChatViewModel
    @EnvironmentObject private var settings: SettingsViewModel
    @State private var isMenuOpen: Bool = false

    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    var body: some View {
        ZStack(alignment: .leading) {

            // ── Main content ──────────────────────────────────────────────
            NavigationView {
                ChatView(isMenuOpen: $isMenuOpen)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isMenuOpen.toggle()
                                }
                            } label: {
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                        }
                        ToolbarItem(placement: .principal) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.accentColor)
                                Text("MinimalAI")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                    }
            }
            .navigationViewStyle(.stack) // Ensures single-column on all iPhones
            // Slide the main content to the right when the menu is open
            .offset(x: isMenuOpen ? 280 : 0)
            .disabled(isMenuOpen)

            // ── Scrim ─────────────────────────────────────────────────────
            if isMenuOpen {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .offset(x: 280)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isMenuOpen = false
                        }
                    }
                    .transition(.opacity)
            }

            // ── Side Menu ─────────────────────────────────────────────────
            SideMenuView(isMenuOpen: $isMenuOpen)
                .frame(width: 280)
                .offset(x: isMenuOpen ? 0 : -280)
                .shadow(color: .black.opacity(0.2), radius: 12, x: 4, y: 0)
        }
        .animation(.easeInOut(duration: 0.3), value: isMenuOpen)
        // ── Onboarding (first launch only) ────────────────────────────────
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedSetup },
            set: { _ in }           // dismiss is handled inside OnboardingView
        )) {
            OnboardingView()
                .environmentObject(settings)
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let settings = SettingsViewModel()
        ContentView()
            .environmentObject(settings)
            .environmentObject(ChatViewModel(settings: settings))
    }
}
