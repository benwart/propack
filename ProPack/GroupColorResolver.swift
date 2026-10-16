import SwiftUI

/// Resolves standard ProPresenter slide group colors mimicking the Arrangements editor.
enum GroupColorResolver {
    /// Returns the appropriate ProPresenter UI color for a given group name,
    /// with optional custom color fallback and defaulting to medium gray.
    static func color(for name: String, customColor: PPColor? = nil) -> Color {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1. Standard ProPresenter group mappings
        if clean.contains("pre-chorus") || clean.contains("pre chorus") || clean.contains("prechorus") {
            return Color(red: 0.91, green: 0.48, blue: 0.12) // Orange / Amber
        } else if clean.contains("chorus") {
            return Color(red: 0.83, green: 0.17, blue: 0.30) // Red / Crimson
        } else if clean.contains("verse") {
            return Color(red: 0.17, green: 0.49, blue: 0.83) // Royal Blue
        } else if clean.contains("bridge") {
            return Color(red: 0.55, green: 0.23, blue: 0.83) // Purple / Violet
        } else if clean.contains("intro") {
            return Color(red: 0.17, green: 0.72, blue: 0.83) // Cyan / Light Blue
        } else if clean.contains("outro") {
            return Color(red: 0.17, green: 0.24, blue: 0.55) // Dark Navy
        } else if clean.contains("tag") {
            return Color(red: 0.83, green: 0.17, blue: 0.55) // Pink / Magenta
        } else if clean.contains("vamp") {
            return Color(red: 0.83, green: 0.66, blue: 0.17) // Gold / Warm Yellow
        } else if clean.contains("interlude") {
            return Color(red: 0.12, green: 0.66, blue: 0.59) // Teal
        } else if clean.contains("ending") {
            return Color(red: 0.35, green: 0.39, blue: 0.45) // Slate Charcoal
        }

        // 2. Custom color from ProPresenter API if specified
        if let c = customColor, let r = c.red, let g = c.green, let b = c.blue, (r > 0.05 || g > 0.05 || b > 0.05) {
            return Color(red: r, green: g, blue: b)
        }

        // 3. Fallback: Medium gray for Other / custom groups
        return Color(red: 0.50, green: 0.52, blue: 0.56)
    }
}

/// A compact colored badge styled like ProPresenter's Arrangement editor group pills.
struct GroupBadgeView: View {
    let name: String
    var color: Color = Color(red: 0.50, green: 0.52, blue: 0.56)

    var body: some View {
        Text(name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color)
            )
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            .fixedSize()
    }
}
