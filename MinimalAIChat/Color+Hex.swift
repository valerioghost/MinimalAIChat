import SwiftUI
import UIKit

extension Color {
    /// Creates a Color from a "#RRGGBB" hex string. Returns nil if the
    /// string isn't a valid 6-digit hex color, so callers can fall back to
    /// a default instead of silently producing black or crashing.
    init?(hex: String) {
        let sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard sanitized.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: sanitized).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255,
            green: Double((rgb & 0x00FF00) >> 8) / 255,
            blue: Double(rgb & 0x0000FF) / 255
        )
    }

    /// Converts this color to a "#RRGGBB" hex string via its resolved RGB
    /// components. Used to persist a color picked via the native ColorPicker
    /// or a preset swatch as a simple, storage-friendly string.
    func toHexString() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}
