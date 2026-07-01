import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {

    @EnvironmentObject private var settings: SettingsViewModel
    @Environment(\.presentationMode) private var presentationMode

    /// Controls whether the API key is revealed as plain text
    @State private var isAPIKeyVisible: Bool = false
    /// Toast-style saved confirmation
    @State private var showSavedBanner: Bool = false
    /// Controls the reset confirmation alert
    @State private var showResetAlert: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            // ── Form ──────────────────────────────────────────────────
            Form {
                endpointSection
                modelSection
                apiKeySection
                statusSection
                dangerSection
            }
            .navigationTitle("API & Connection")
            .navigationBarTitleDisplayMode(.inline)


                // ── Saved Banner ──────────────────────────────────────────
                if showSavedBanner {
                    savedBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: showSavedBanner)
        .alert(isPresented: $showResetAlert) {
            Alert(
                title: Text("Reset to Defaults"),
                message: Text("This will clear your API key, Base URL, and Model Name. This cannot be undone."),
                primaryButton: .destructive(Text("Reset")) {
                    withAnimation { settings.resetToDefaults() }
                    flashSavedBanner()
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Sections

    /// Base URL section
    private var endpointSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Base URL", systemImage: "network")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                TextField("https://api.openai.com/v1", text: $settings.baseURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .font(.system(size: 15, design: .monospaced))
                    .onChange(of: settings.baseURL) { _ in flashSavedBanner() }

                Text("Supports OpenAI, Azure, Ollama, or any OpenAI-compatible endpoint.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        } header: {
            sectionHeader(icon: "server.rack", title: "Endpoint")
        }
    }

    /// Model name section
    private var modelSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Model Name", systemImage: "cpu")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                TextField("gpt-4o-mini", text: $settings.modelName)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .font(.system(size: 15, design: .monospaced))
                    .onChange(of: settings.modelName) { _ in flashSavedBanner() }

                Text("Examples: gpt-4o-mini · claude-3-haiku · llama3 · mistral")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            sectionHeader(icon: "brain.head.profile", title: "Model")
        }
    }

    /// API Key section with show/hide toggle
    private var apiKeySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("API Key", systemImage: "key.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Group {
                        if isAPIKeyVisible {
                            TextField("sk-...", text: $settings.apiKey)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("sk-...", text: $settings.apiKey)
                        }
                    }
                    .font(.system(size: 15, design: .monospaced))
                    .onChange(of: settings.apiKey) { _ in flashSavedBanner() }

                    Button {
                        isAPIKeyVisible.toggle()
                    } label: {
                        Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                }

                Text("Stored securely in the iOS Keychain — never in UserDefaults or iCloud.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        } header: {
            sectionHeader(icon: "lock.shield", title: "Authentication")
        }
    }

    /// Live status summary
    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                statusDot(settings.isConfigured)
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.isConfigured ? "Configuration valid" : "Incomplete configuration")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(settings.isConfigured ? .primary : .secondary)
                    Text(settings.hasAPIKey ? "API key present ✓" : "No API key — needed for most providers")
                        .font(.system(size: 12))
                        .foregroundColor(settings.hasAPIKey ? Color.green : Color.orange)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        } header: {
            sectionHeader(icon: "checkmark.seal", title: "Status")
        }
    }

    /// Danger zone
    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset to Defaults")
                }
                .font(.system(size: 15, weight: .medium))
            }
        } header: {
            sectionHeader(icon: "exclamationmark.triangle", title: "Danger Zone")
        }
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.secondary)
    }

    private func statusDot(_ on: Bool) -> some View {
        Circle()
            .fill(on ? Color.green : Color.orange)
            .frame(width: 10, height: 10)
    }

    /// Shows the "Saved" banner briefly then hides it.
    private func flashSavedBanner() {
        showSavedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { showSavedBanner = false }
        }
    }

    private var savedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
            Text("Settings Saved")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.accentColor)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .padding(.top, 12)
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SettingsViewModel())
    }
}
