import SwiftUI

/// User-selectable appearance override. `.system` means "follow the
/// device's current light/dark setting" — the app's behavior before this
/// feature existed, and the default. `.light`/`.dark` force a specific
/// scheme regardless of the device setting.
enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The value to pass to `.preferredColorScheme(_:)`. `nil` for `.system`
    /// removes any override, letting the scheme follow the device setting —
    /// this is the pre-existing app behavior.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
