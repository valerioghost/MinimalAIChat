import SwiftUI

/// A small curated palette of accent color choices shown as tappable
/// swatches. The default blue is included first so switching back to the
/// original app color is always one tap away, without needing the
/// ColorPicker.
enum PresetColor: String, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return Color(hex: "#007AFF") ?? .blue
        case .purple: return Color(hex: "#AF52DE") ?? .purple
        case .pink: return Color(hex: "#FF2D55") ?? .pink
        case .red: return Color(hex: "#FF3B30") ?? .red
        case .orange: return Color(hex: "#FF9500") ?? .orange
        case .yellow: return Color(hex: "#FFCC00") ?? .yellow
        case .green: return Color(hex: "#34C759") ?? .green
        case .teal: return Color(hex: "#5AC8FA") ?? .teal
        }
    }

    var hex: String { color.toHexString() }
}
