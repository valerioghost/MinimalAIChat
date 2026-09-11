import Foundation

/// A quick-select preset for common OpenAI-compatible provider endpoints.
/// Selecting a preset only sets the Base URL — Model Name and API Key are
/// left untouched, since those vary per account/model choice even within
/// the same provider.
enum APIProviderPreset: String, CaseIterable, Identifiable {
    case openAI
    case gemini
    case openRouter
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .openRouter: return "OpenRouter"
        case .other: return "Other"
        }
    }

    /// The Base URL this preset applies. `nil` for `.other`, which is a
    /// no-op by design — it exists only to represent "a custom URL not
    /// matching any known preset", not to change the field when tapped.
    var baseURL: String? {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .other: return nil
        }
    }

    /// Normalizes a URL string for comparison: trims whitespace, strips a
    /// trailing slash, and lowercases. Applied identically to both the
    /// user's input and each preset's own baseURL — asymmetric normalization
    /// (only trimming one side) was the root cause of Gemini's preset never
    /// matching, since its baseURL is the only one that ends in "/".
    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    static func matching(_ rawBaseURL: String) -> APIProviderPreset {
        let normalizedInput = normalize(rawBaseURL)

        for preset in allCases where preset != .other {
            if let presetURL = preset.baseURL, normalize(presetURL) == normalizedInput {
                return preset
            }
        }
        return .other
    }
}
