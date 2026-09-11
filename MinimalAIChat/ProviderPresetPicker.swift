import SwiftUI

/// A horizontal row of pill buttons for quickly setting a Base URL to a
/// known provider's endpoint. Reused in both SettingsView (bound to the
/// live SettingsViewModel) and OnboardingView (bound to a local @State
/// before the user finishes setup).
struct ProviderPresetPicker: View {
    @EnvironmentObject private var settings: SettingsViewModel
    @Binding var baseURL: String

    private var selected: APIProviderPreset {
        APIProviderPreset.matching(baseURL)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(APIProviderPreset.allCases) { preset in
                    Button(action: { apply(preset) }) {
                        Text(preset.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    selected == preset ? settings.accentColor : Color(.secondarySystemBackground)
                                )
                            )
                            .foregroundColor(selected == preset ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Applies a preset's Base URL. `.other` explicitly clears the field,
    /// acting as a reset button for typing a fully custom endpoint.
    private func apply(_ preset: APIProviderPreset) {
        if preset == .other {
            baseURL = ""
        } else if let url = preset.baseURL {
            baseURL = url
        }
    }
}
