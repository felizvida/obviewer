import SwiftUI

/// The fleur-de-lis that closes every note in the reader and sits on the app
/// icon. Same drawing as `scripts/generate_app_icon.py` and the reader's CSS
/// mask: a 240 × 216 design grid, scaled to fit the rect.
struct FleurDeLis: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 240, rect.height / 216)
        let origin = CGPoint(x: rect.midX - 120 * scale, y: rect.midY - 108 * scale)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        var parts = [Path()]
        parts.append(Path())
        parts[parts.count - 1].move(to: p(120, 0))
        parts[parts.count - 1].addCurve(to: p(149, 80), control1: p(132, 26), control2: p(151, 50))
        parts[parts.count - 1].addCurve(to: p(132, 136), control1: p(147, 106), control2: p(135, 120))
        parts[parts.count - 1].addLine(to: p(132, 150))
        parts[parts.count - 1].addLine(to: p(108, 150))
        parts[parts.count - 1].addLine(to: p(108, 136))
        parts[parts.count - 1].addCurve(to: p(91, 80), control1: p(105, 120), control2: p(93, 106))
        parts[parts.count - 1].addCurve(to: p(120, 0), control1: p(89, 50), control2: p(108, 26))
        parts[parts.count - 1].closeSubpath()
        parts.append(Path())
        parts[parts.count - 1].move(to: p(134, 142))
        parts[parts.count - 1].addCurve(to: p(228, 98), control1: p(158, 96), control2: p(210, 62))
        parts[parts.count - 1].addCurve(to: p(208, 126), control1: p(236, 116), control2: p(222, 134))
        parts[parts.count - 1].addCurve(to: p(152, 148), control1: p(194, 118), control2: p(172, 126))
        parts[parts.count - 1].closeSubpath()
        parts.append(Path())
        parts[parts.count - 1].move(to: p(144, 150))
        parts[parts.count - 1].addCurve(to: p(167, 199), control1: p(164, 164), control2: p(180, 184))
        parts[parts.count - 1].addCurve(to: p(152, 187), control1: p(157, 208), control2: p(145, 198))
        parts[parts.count - 1].addCurve(to: p(136, 152), control1: p(157, 178), control2: p(148, 164))
        parts[parts.count - 1].closeSubpath()
        parts.append(Path())
        parts[parts.count - 1].move(to: p(106, 142))
        parts[parts.count - 1].addCurve(to: p(12, 98), control1: p(82, 96), control2: p(30, 62))
        parts[parts.count - 1].addCurve(to: p(32, 126), control1: p(4, 116), control2: p(18, 134))
        parts[parts.count - 1].addCurve(to: p(88, 148), control1: p(46, 118), control2: p(68, 126))
        parts[parts.count - 1].closeSubpath()
        parts.append(Path())
        parts[parts.count - 1].move(to: p(96, 150))
        parts[parts.count - 1].addCurve(to: p(73, 199), control1: p(76, 164), control2: p(60, 184))
        parts[parts.count - 1].addCurve(to: p(88, 187), control1: p(83, 208), control2: p(95, 198))
        parts[parts.count - 1].addCurve(to: p(104, 152), control1: p(83, 178), control2: p(92, 164))
        parts[parts.count - 1].closeSubpath()
        parts.append(Path())
        parts[parts.count - 1].move(to: p(130, 150))
        parts[parts.count - 1].addCurve(to: p(120, 216), control1: p(133, 172), control2: p(129, 194))
        parts[parts.count - 1].addCurve(to: p(110, 150), control1: p(111, 194), control2: p(107, 172))
        parts[parts.count - 1].closeSubpath()
        parts.append(Path(
            roundedRect: CGRect(origin: p(70, 134), size: CGSize(width: 100 * scale, height: 18 * scale)),
            cornerSize: CGSize(width: 8 * scale, height: 8 * scale)
        ))
        return parts.dropFirst().reduce(Path()) { $0.union($1) }
    }
}
