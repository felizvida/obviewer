import AppKit
import SwiftUI

enum VisualTheme {
    static let ink = dynamic(light: (0.11, 0.13, 0.15), dark: (0.90, 0.90, 0.88))
    static let softInk = dynamic(light: (0.28, 0.31, 0.33), dark: (0.76, 0.77, 0.75))
    static let quietInk = dynamic(light: (0.45, 0.48, 0.46), dark: (0.58, 0.61, 0.59))
    static let fern = dynamic(light: (0.20, 0.45, 0.33), dark: (0.47, 0.76, 0.61))
    static let blue = dynamic(light: (0.18, 0.36, 0.63), dark: (0.54, 0.72, 0.94))
    static let ember = dynamic(light: (0.72, 0.38, 0.21), dark: (0.90, 0.58, 0.40))
    static let paper = dynamic(light: (0.98, 0.97, 0.93), dark: (0.11, 0.12, 0.12))
    static let mist = dynamic(light: (0.90, 0.95, 0.94), dark: (0.13, 0.15, 0.15))
    static let clay = dynamic(light: (0.94, 0.88, 0.80), dark: (0.18, 0.16, 0.14))
    static let cream = dynamic(light: (0.99, 0.98, 0.94), dark: (0.15, 0.16, 0.16))
    static let moss = dynamic(light: (0.34, 0.46, 0.32), dark: (0.45, 0.62, 0.43))
    static let brass = dynamic(light: (0.72, 0.55, 0.28), dark: (0.82, 0.66, 0.40))
    /// Raised surfaces: white in light mode, a lifted graphite in dark mode.
    static let panel = dynamic(light: (1.0, 1.0, 1.0), dark: (0.17, 0.18, 0.19))
    /// Hairlines and subtle fills: black in light mode, white in dark mode.
    static let shade = dynamic(light: (0.0, 0.0, 0.0), dark: (1.0, 1.0, 1.0))
    /// Matches the web reader's page background.
    static let readerBackground = dynamic(light: (0.984, 0.980, 0.965), dark: (0.106, 0.114, 0.122))

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

    static var appBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                dynamic(light: (0.93, 0.96, 0.98), dark: (0.10, 0.11, 0.12)),
                paper,
                mist,
                dynamic(light: (0.94, 0.91, 0.86), dark: (0.12, 0.12, 0.11)),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var readerSurface: some ShapeStyle {
        LinearGradient(
            colors: [
                VisualTheme.panel.opacity(0.86),
                paper.opacity(0.78),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var selectedSurface: some ShapeStyle {
        LinearGradient(
            colors: [
                VisualTheme.panel.opacity(0.96),
                mist.opacity(0.92),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var sidebarSurface: some ShapeStyle {
        LinearGradient(
            colors: [
                VisualTheme.panel.opacity(0.70),
                cream.opacity(0.56),
                mist.opacity(0.44),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var heroSurface: some ShapeStyle {
        LinearGradient(
            colors: [
                VisualTheme.panel.opacity(0.92),
                cream.opacity(0.84),
                clay.opacity(0.48),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var accentGradient: some ShapeStyle {
        LinearGradient(
            colors: [
                fern,
                moss,
                brass.opacity(0.88),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var quietRule: some ShapeStyle {
        LinearGradient(
            colors: [
                VisualTheme.shade.opacity(0.10),
                VisualTheme.shade.opacity(0.025),
                .clear,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct SoftPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 24
    var opacity: Double = 0.64

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(VisualTheme.panel.opacity(opacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(VisualTheme.panel.opacity(0.58), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(VisualTheme.shade.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.035), radius: 12, x: 0, y: 7)
    }
}

extension View {
    func softPanel(cornerRadius: CGFloat = 24, opacity: Double = 0.64) -> some View {
        modifier(SoftPanelModifier(cornerRadius: cornerRadius, opacity: opacity))
    }

    func premiumPanel(cornerRadius: CGFloat = 28) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(VisualTheme.sidebarSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(VisualTheme.panel.opacity(0.64), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(VisualTheme.shade.opacity(0.045), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.055), radius: 24, x: 0, y: 14)
    }
}
