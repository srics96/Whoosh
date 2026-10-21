import SwiftUI

/// Purely local ornament. Time animates the trail, never the reported work or completion state.
struct MagicTrail: View {
    let active: Bool
    var forceReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active || reduceMotion)) { timeline in
            Canvas { context, size in
                let time = active && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate : 0
                let start = CGPoint(x: 28, y: size.height / 2)
                let end = CGPoint(x: size.width - 28, y: size.height / 2)
                let cp1 = CGPoint(x: size.width * 0.38, y: size.height * 0.08)
                let cp2 = CGPoint(x: size.width * 0.62, y: size.height * 0.92)
                var path = Path()
                path.move(to: start)
                path.addCurve(to: end, control1: cp1, control2: cp2)
                let gradient = Gradient(colors: [.mint.opacity(0.1), .mint.opacity(0.65), .orange.opacity(0.7), .orange.opacity(0.1)])
                context.stroke(path, with: .linearGradient(gradient, startPoint: start, endPoint: end), lineWidth: 1)
                for index in 0..<16 {
                    let t = CGFloat((time * 0.21 + Double(index) / 16).truncatingRemainder(dividingBy: 1))
                    let one = 1 - t
                    let x = one * one * one * start.x + 3 * one * one * t * cp1.x + 3 * one * t * t * cp2.x + t * t * t * end.x
                    let y = one * one * one * start.y + 3 * one * one * t * cp1.y + 3 * one * t * t * cp2.y + t * t * t * end.y
                    let radius: CGFloat = index % 4 == 0 ? 2.5 : 1.3
                    let dot = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    context.fill(dot, with: .color(t < 0.5 ? .mint.opacity(active ? 0.8 : 0.3) : .orange.opacity(active ? 0.85 : 0.3)))
                }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for index in 0..<3 {
                    let pulse = active && !reduceMotion ? (time * 0.35 + Double(index) / 3).truncatingRemainder(dividingBy: 1) : Double(index) / 3
                    let radius = CGFloat(17 + pulse * 27)
                    let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                    context.stroke(ring, with: .color(.orange.opacity((1 - pulse) * (active ? 0.25 : 0.10))), lineWidth: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct RelayPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Color(red: 0.15, green: 0.10, blue: 0.09) : Color.white.opacity(0.35))
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(isEnabled
                        ? LinearGradient(colors: [Color(red: 1, green: 0.79, blue: 0.57), Color(red: 1, green: 0.62, blue: 0.48)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.white.opacity(0.06), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(isEnabled ? 0.22 : 0.06)))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct RelaySecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.055), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.09)))
    }
}
