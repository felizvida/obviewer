import AppKit
import SwiftUI

/// The app's few colours. They mirror `Renderer/static/reader.css` so the window
/// chrome and the reader page read as one surface: paper, ink, graphite, a
/// purple ink accent (after LSU purple) and old gold for the one ornament.
enum VisualTheme {
    static let ink = dynamic(light: (0.137, 0.149, 0.169), dark: (0.898, 0.890, 0.871))
    static let softInk = dynamic(light: (0.271, 0.286, 0.310), dark: (0.769, 0.761, 0.737))
    static let quietInk = dynamic(light: (0.455, 0.471, 0.490), dark: (0.561, 0.573, 0.588))
    /// Purple ink: links, selection tint, prominent buttons.
    static let accent = dynamic(light: (0.275, 0.141, 0.478), dark: (0.780, 0.690, 0.933))
    /// Old gold: the fleur-de-lis.
    static let gold = dynamic(light: (0.690, 0.514, 0.149), dark: (0.839, 0.678, 0.341))
    /// Raised surfaces: white in light mode, a lifted graphite in dark mode.
    static let panel = dynamic(light: (1.0, 1.0, 1.0), dark: (0.137, 0.141, 0.157))
    /// Hairlines and subtle fills: black in light mode, white in dark mode.
    static let shade = dynamic(light: (0.0, 0.0, 0.0), dark: (1.0, 1.0, 1.0))
    /// Matches the reader's page (--ob-bg).
    static let readerBackground = dynamic(light: (0.992, 0.992, 0.984), dark: (0.110, 0.114, 0.125))

    /// Flat surfaces used by the graph view.
    static var heroSurface: Color { panel }
    static var sidebarSurface: Color { panel.opacity(0.92) }

    private static func dynamic(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }
}

extension View {
    /// A plain panel with a hairline edge (graph inspector).
    func premiumPanel(cornerRadius: CGFloat = 10) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(VisualTheme.sidebarSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(VisualTheme.shade.opacity(0.08), lineWidth: 1)
        )
    }
}
