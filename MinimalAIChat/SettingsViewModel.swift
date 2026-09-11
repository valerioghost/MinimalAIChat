import Foundation
import Combine
import SwiftUI
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
    static let tavilyApiKey = "settings.tavilyApiKey"
    static let appearanceMode = "settings.appearanceMode"
    static let accentColorHex = "settings.accentColorHex"
}

// MARK: - Default Values

enum SettingsDefault {
    static let baseURL   = "https://api.openai.com/v1"
    static let modelName = "gpt-4o-mini"
    static let temperature: Double = 1.0
    static let historyCharacterBudget: Int = 8000
    static let appearanceMode: AppearanceMode = .system
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

    @Published var tavilyApiKey: String {
        didSet { KeychainHelper.shared.save(tavilyApiKey, forKey: SettingsKey.tavilyApiKey) }
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

    /// Manual light/dark/system override. Defaults to `.system`, meaning
    /// this feature changes nothing for users who never open the new
    /// Appearance settings — identical to the app's prior behavior.
    @Published var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: SettingsKey.appearanceMode) }
    }

    /// User-chosen accent color, stored as a "#RRGGBB" hex string. `nil`
    /// means "no custom color chosen" — in that case `accentColor` below
    /// falls back to the app's existing Assets-catalog AccentColor,
    /// completely unchanged from before this feature existed.
    @Published var accentColorHex: String? {
        didSet {
            if let accentColorHex {
                UserDefaults.standard.set(accentColorHex, forKey: SettingsKey.accentColorHex)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.accentColorHex)
            }
        }
    }

    /// Resolved accent color for use throughout the app. Prefer this over a
    /// literal `Color.accentColor` reference wherever the person's custom
    /// color choice should be respected — a later stage replaces existing
    /// `Color.accentColor` call sites with this property.
    var accentColor: Color {
        if let accentColorHex, let color = Color(hex: accentColorHex) {
            return color
        }
        return Color.accentColor
    }

    /// The device's true current light/dark setting, read via UIScreen
    /// rather than SwiftUI's @Environment(\.colorScheme) — the latter gets
    /// self-contaminated by our own .preferredColorScheme() calls, since
    /// that modifier works by overriding the app window's
    /// overrideUserInterfaceStyle, and @Environment(\.colorScheme) reads
    /// that same overridden value back instead of the true device setting.
    /// UIScreen's trait collection is not part of that override cascade, so
    /// it always reflects the real device appearance. Refreshed at launch
    /// and whenever the app returns to foreground (see RootView).
    @Published var systemColorScheme: ColorScheme = SettingsViewModel.readSystemColorScheme()

    /// The color scheme actually applied to the app: the person's explicit
    /// Light/Dark choice if set, otherwise the true device setting. Single
    /// source of truth used by every .preferredColorScheme() call site in
    /// the app, so they all stay in sync without each needing their own
    /// environment-reading logic.
    var resolvedColorScheme: ColorScheme {
        appearanceMode.colorScheme ?? systemColorScheme
    }

    /// Re-reads the device's true appearance from UIScreen. Call this at
    /// points where the system setting may have changed while the app
    /// wasn't actively rendering — app launch and foreground return are
    /// the two that matter in practice, since a live mid-session system
    /// appearance toggle while this app is frontmost is a rare edge case.
    func refreshSystemColorScheme() {
        systemColorScheme = Self.readSystemColorScheme()
    }

    private static func readSystemColorScheme() -> ColorScheme {
        UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
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
    var hasTavilyKey: Bool { !tavilyApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        self.baseURL   = defaults.string(forKey: SettingsKey.baseURL)   ?? SettingsDefault.baseURL
        self.modelName = defaults.string(forKey: SettingsKey.modelName) ?? SettingsDefault.modelName
        self.apiKey    = KeychainHelper.shared.read(forKey: SettingsKey.apiKey) ?? ""
        self.tavilyApiKey = KeychainHelper.shared.read(forKey: SettingsKey.tavilyApiKey) ?? ""
        self.userName  = defaults.string(forKey: SettingsKey.userName)  ?? ""
        self.profileImage = ProfileImageManager.load()
        self.temperature = defaults.object(forKey: SettingsKey.temperature) as? Double ?? SettingsDefault.temperature
        self.maxTokens   = defaults.object(forKey: SettingsKey.maxTokens) as? Int
        self.historyCharacterBudget = defaults.object(forKey: SettingsKey.historyCharacterBudget) as? Int ?? SettingsDefault.historyCharacterBudget
        if let rawMode = defaults.string(forKey: SettingsKey.appearanceMode), let mode = AppearanceMode(rawValue: rawMode) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = SettingsDefault.appearanceMode
        }
        self.accentColorHex = defaults.string(forKey: SettingsKey.accentColorHex)
    }

    // MARK: - Actions

    /// Wipes all persisted settings and resets to defaults.
    func resetToDefaults() {
        baseURL   = SettingsDefault.baseURL
        modelName = SettingsDefault.modelName
        apiKey    = ""
        KeychainHelper.shared.delete(forKey: SettingsKey.apiKey)
    }
}
