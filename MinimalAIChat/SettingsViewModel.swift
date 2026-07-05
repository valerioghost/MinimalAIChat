import Foundation
import Combine
import UIKit

// MARK: - AppSettings Keys

/// Centralised constants for UserDefaults / Keychain keys.
enum SettingsKey {
    static let baseURL    = "settings.baseURL"
    static let modelName  = "settings.modelName"
    static let apiKey     = "settings.apiKey"        // stored in Keychain
    static let userName   = "userName"               // shared with @AppStorage
    static let temperature = "settings.temperature"
    static let maxTokens   = "settings.maxTokens"
    static let historyCharacterBudget = "settings.historyCharacterBudget"
}

// MARK: - Default Values

enum SettingsDefault {
    static let baseURL   = "https://api.openai.com/v1"
    static let modelName = "gpt-4o-mini"
    static let temperature: Double = 1.0
    static let historyCharacterBudget: Int = 8000
}

// MARK: - SettingsViewModel

/// Owns all user-configurable settings.
/// - Base URL and Model Name are stored in UserDefaults via @Published + manual sync.
/// - API Key is stored in the Keychain.
///
/// iOS 15 note: We use a plain ObservableObject rather than relying on
/// @AppStorage inside the view, so the ViewModel can be the single
/// source of truth and be read from ChatViewModel too.
final class SettingsViewModel: ObservableObject {

    // MARK: - Published fields (bound to UI text fields)

    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: SettingsKey.baseURL) }
    }

    @Published var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: SettingsKey.modelName) }
    }

    /// Plain (unmasked) string edited in the UI.
    /// Never persisted in memory beyond this object; written to Keychain on change.
    @Published var apiKey: String {
        didSet { KeychainHelper.shared.save(apiKey, forKey: SettingsKey.apiKey) }
    }

    /// The user's display name — shared key with OnboardingView's @AppStorage("userName").
    @Published var userName: String {
        didSet { UserDefaults.standard.set(userName, forKey: SettingsKey.userName) }
    }

    @Published var profileImage: UIImage?
    
    @Published var temperature: Double {
        didSet { UserDefaults.standard.set(temperature, forKey: SettingsKey.temperature) }
    }
    
    @Published var maxTokens: Int? {
        didSet {
            if let maxTokens = maxTokens {
                UserDefaults.standard.set(maxTokens, forKey: SettingsKey.maxTokens)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.maxTokens)
            }
        }
    }
    
    @Published var historyCharacterBudget: Int {
        didSet { UserDefaults.standard.set(historyCharacterBudget, forKey: SettingsKey.historyCharacterBudget) }
    }

    func updateProfileImage(_ image: UIImage) {
        self.profileImage = image
        ProfileImageManager.save(image)
    }

    // MARK: - Derived helpers

    /// Whether the minimum required configuration is present.
    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !modelName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        self.baseURL   = defaults.string(forKey: SettingsKey.baseURL)   ?? SettingsDefault.baseURL
        self.modelName = defaults.string(forKey: SettingsKey.modelName) ?? SettingsDefault.modelName
        self.apiKey    = KeychainHelper.shared.read(forKey: SettingsKey.apiKey) ?? ""
        self.userName  = defaults.string(forKey: SettingsKey.userName)  ?? ""
        self.profileImage = ProfileImageManager.load()
        self.temperature = defaults.object(forKey: SettingsKey.temperature) as? Double ?? SettingsDefault.temperature
        self.maxTokens   = defaults.object(forKey: SettingsKey.maxTokens) as? Int
        self.historyCharacterBudget = defaults.object(forKey: SettingsKey.historyCharacterBudget) as? Int ?? SettingsDefault.historyCharacterBudget
    }

    // MARK: - Actions

    /// Wipes all persisted settings and resets to defaults.
    func resetToDefaults() {
        baseURL   = SettingsDefault.baseURL
        modelName = SettingsDefault.modelName
        apiKey    = ""
        KeychainHelper.shared.delete(forKey: SettingsKey.apiKey)
        temperature = SettingsDefault.temperature
        maxTokens = nil
        historyCharacterBudget = SettingsDefault.historyCharacterBudget
    }
}
