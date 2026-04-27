import SwiftUI

enum VisualTheme {
    static let ink = Color(red: 0.11, green: 0.13, blue: 0.15)
    static let softInk = Color(red: 0.28, green: 0.31, blue: 0.33)
    static let fern = Color(red: 0.20, green: 0.45, blue: 0.33)
    static let blue = Color(red: 0.18, green: 0.36, blue: 0.63)
    static let ember = Color(red: 0.72, green: 0.38, blue: 0.21)
    static let paper = Color(red: 0.98, green: 0.97, blue: 0.93)
    static let mist = Color(red: 0.90, green: 0.95, blue: 0.94)
    static let clay = Color(red: 0.94, green: 0.88, blue: 0.80)

    static var appBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.96, blue: 0.98),
                paper,
                mist,
                Color(red: 0.94, green: 0.91, blue: 0.86),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var readerSurface: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.86),
                paper.opacity(0.78),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var selectedSurface: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.96),
                mist.opacity(0.92),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
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
                    .fill(Color.white.opacity(opacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.58), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.035), radius: 12, x: 0, y: 7)
    }
}

extension View {
    func softPanel(cornerRadius: CGFloat = 24, opacity: Double = 0.64) -> some View {
        modifier(SoftPanelModifier(cornerRadius: cornerRadius, opacity: opacity))
    }
}
