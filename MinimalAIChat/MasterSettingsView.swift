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
                    
                    NavigationLink(destination: AboutView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor)
                            Text("About")
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
    @EnvironmentObject private var settings: SettingsViewModel
    @State private var showingImagePicker = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    Button {
                        showingImagePicker = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 80, height: 80)
                            
                            if let img = settings.profileImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            } else if userName.isEmpty {
                                Image(systemName: "person")
                                    .font(.system(size: 36, weight: .medium))
                                    .foregroundColor(.accentColor)
                            } else {
                                Text(String(userName.prefix(1)).uppercased())
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.accentColor)
                            }
                            
                            Circle()
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                                .frame(width: 80, height: 80)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .padding(.vertical, 10)
            } header: {
                Text("Your Profile Picture")
            }

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
        .sheet(isPresented: $showingImagePicker) {
            SystemImagePicker(selectedImage: Binding(get: { settings.profileImage }, set: { newImg in
                if let newImg = newImg {
                    settings.updateProfileImage(newImg)
                }
            }))
        }
    }
}

// MARK: - PromptSettingsView

/// Sub-view for editing the AI system prompt.
struct PromptSettingsView: View {

    @AppStorage("customSystemPrompt") private var customSystemPrompt: String = ""
    @State private var showResetAlert: Bool = false

    var body: some View {
        Form {
            Section {
                TextEditor(text: $customSystemPrompt)
                    .frame(minHeight: 150)
                    .font(.system(size: 16))
                    .padding(.vertical, 4)
                
                Button(action: {
                    showResetAlert = true
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Default")
                    }
                    .font(.system(size: 15))
                    .foregroundColor(.red)
                }
            } header: {
                Text("System Prompt")
            } footer: {
                Text("This text dictates how the AI behaves. Use {name} anywhere in your prompt to dynamically inject your profile name.")
            }
        }
        .onAppear {
            if customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customSystemPrompt = ChatConstants.defaultSystemPrompt
            }
        }
        .alert(isPresented: $showResetAlert) {
            Alert(
                title: Text("Reset system prompt?"),
                message: Text("Your custom prompt will be replaced with the default."),
                primaryButton: .destructive(Text("Reset")) {
                    withAnimation {
                        customSystemPrompt = ChatConstants.defaultSystemPrompt
                    }
                },
                secondaryButton: .cancel()
            )
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

// MARK: - AboutView

/// Simple about screen with links and version info.
struct AboutView: View {
    var body: some View {
        Form {
            Section {
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    HStack {
                        Image(systemName: "tag")
                            .foregroundColor(.secondary)
                            .frame(width: 24)
                        Text("Version")
                        Spacer()
                        Text(version)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("App Info")
            }

            Section {
                Button(action: {
                    if let url = URL(string: "https://github.com/valerioghost/MinimalAIChat") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .foregroundColor(.accentColor)
                            .frame(width: 24)
                        Text("GitHub Repository")
                            .foregroundColor(.primary)
                    }
                }

                Button(action: {
                    if let url = URL(string: "https://discord.gg/ryy2h6j5aq") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .foregroundColor(.accentColor)
                            .frame(width: 24)
                        Text("Discord Server")
                            .foregroundColor(.primary)
                    }
                }
            } header: {
                Text("Links")
            } footer: {
                Text("Join the Discord server for support & feedback.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
