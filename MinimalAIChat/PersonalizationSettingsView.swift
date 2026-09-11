import SwiftUI

/// Sub-view for customizing the app's appearance: manual light/dark theme
/// override, and a custom accent color (curated presets, a reset-to-default
/// option, or the native color wheel for any shade). Lives on its own
/// settings screen since these are cosmetic preferences unrelated to
/// network/connection settings.
struct PersonalizationSettingsView: View {
    @EnvironmentObject private var settings: SettingsViewModel

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Theme", systemImage: "circle.lefthalf.filled")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    Picker("Theme", selection: $settings.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Theme")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Accent Color", systemImage: "paintpalette")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            // Default / reset swatch — restores the app's
                            // original AccentColor asset by clearing the
                            // stored hex (nil), rather than setting a fixed
                            // color. Deliberately uses the literal
                            // Color.accentColor here, since this swatch's
                            // whole purpose is to show/restore the true,
                            // un-customized app color — not the user's
                            // current override.
                            Button(action: { settings.accentColorHex = nil }) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: settings.accentColorHex == nil ? 2 : 0)
                                            .padding(-3)
                                    )
                            }
                            .buttonStyle(.plain)

                            ForEach(PresetColor.allCases) { preset in
                                Button(action: { settings.accentColorHex = preset.hex }) {
                                    Circle()
                                        .fill(preset.color)
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary, lineWidth: settings.accentColorHex == preset.hex ? 2 : 0)
                                                .padding(-3)
                                        )
                                }
                                .buttonStyle(.plain)
                            }

                            ColorPicker("", selection: Binding(
                                get: { settings.accentColor },
                                set: { settings.accentColorHex = $0.toHexString() }
                            ))
                            .labelsHidden()
                            .frame(width: 30, height: 30)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                    }

                    Text("Tap the reset icon to restore the default color, tap a preset, or use the color wheel for any custom shade.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Accent Color")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

struct PersonalizationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PersonalizationSettingsView()
                .environmentObject(SettingsViewModel())
        }
    }
}
