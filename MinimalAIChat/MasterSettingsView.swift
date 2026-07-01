import SwiftUI

// MARK: - MasterSettingsView

/// Master settings sheet presenting navigation options for Profile and API settings.
struct MasterSettingsView: View {

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section {
                    NavigationLink(destination: ProfileSettingsView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor)
                            Text("Edit Profile Name")
                                .font(.system(size: 16))
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink(destination: PromptSettingsView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor)
                            Text("AI Personality")
                                .font(.system(size: 16))
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink(destination: SettingsView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "network")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor)
                            Text("API & Connection Settings")
                                .font(.system(size: 16))
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Settings")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - ProfileSettingsView

/// Sub-view for editing the user's display name.
struct ProfileSettingsView: View {

    @AppStorage("userName") private var userName: String = ""

    var body: some View {
        Form {
            Section {
                TextField("e.g. Valerio", text: $userName)
                    .font(.system(size: 16))
                    .padding(.vertical, 4)
            } header: {
                Text("Your Name")
            } footer: {
                Text("Used to personalise your AI conversations.")
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PromptSettingsView

/// Sub-view for editing the AI system prompt.
struct PromptSettingsView: View {

    let defaultPrompt = "You are a helpful AI assistant. The user's name is {name}. Address the user by their name when appropriate, and be concise, friendly, and accurate."
    @AppStorage("customSystemPrompt") private var customSystemPrompt: String = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $customSystemPrompt)
                    .frame(minHeight: 150)
                    .font(.system(size: 16))
                    .padding(.vertical, 4)
            } header: {
                Text("System Prompt")
            } footer: {
                Text("This text dictates how the AI behaves. Use {name} anywhere in your prompt to dynamically inject your profile name.")
            }
        }
        .onAppear {
            if customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customSystemPrompt = defaultPrompt
            }
        }
        .navigationTitle("AI Personality")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

struct MasterSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        MasterSettingsView()
            .environmentObject(SettingsViewModel())
    }
}
