import SwiftUI

/// The whoosh: a comet of particles streaming along an arc from the source to the destination,
/// with a glowing trail, a traveling head, sparkles, and arrival pulses. Purely decorative —
/// time drives the motion, never the reported work or completion state.
struct WhooshTrail: View {
    let active: Bool
    var forceReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var capped = false
    private var reduced: Bool { systemReduceMotion || forceReduceMotion }
    /// A handoff is near-instant, so the shimmer only needs to run briefly. Capping it means a
    /// hung handoff (stage stuck "in flight") can never peg a core with an endless redraw loop.
    private static let maxAnimationSeconds: UInt64 = 6
    private let teal = WhooshGeometry.teal
    private let blue = WhooshGeometry.blue

    private func bezier(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, _ u: CGFloat) -> CGPoint {
        let v = 1 - u
        let x = v*v*v*p0.x + 3*v*v*u*c1.x + 3*v*u*u*c2.x + u*u*u*p3.x
        let y = v*v*v*p0.y + 3*v*v*u*c1.y + 3*v*u*u*c2.y + u*u*u*p3.y
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        // 30fps is plenty for a decorative trail and halves the redraw work; paused unless actively
        // animating, reduce-motion is on, or the brief animation window has elapsed.
        let animating = active && !reduced && !capped
        TimelineView(.animation(minimumInterval: 1.0/30.0, paused: !animating)) { timeline in
            Canvas { ctx, size in
                let t = animating ? timeline.date.timeIntervalSinceReferenceDate : 0
                let start = CGPoint(x: 34, y: size.height/2)
                let end = CGPoint(x: size.width - 34, y: size.height/2)
                let c1 = CGPoint(x: size.width*0.38, y: size.height*0.10)
                let c2 = CGPoint(x: size.width*0.62, y: size.height*0.90)
                func at(_ u: CGFloat) -> CGPoint { bezier(start, c1, c2, end, max(0, min(1, u))) }

                var path = Path(); path.move(to: start); path.addCurve(to: end, control1: c1, control2: c2)
                // Fake glow: a wide, faint stroke under the trail — no per-frame Gaussian blur filter,
                // which is what made this canvas expensive to redraw.
                ctx.stroke(path, with: .color(blue.opacity(active ? 0.16 : 0.07)), lineWidth: 7)
                // the trail line
                ctx.stroke(path, with: .linearGradient(
                    Gradient(colors: [teal.opacity(0.15), teal, blue, blue.opacity(0.15)]),
                    startPoint: start, endPoint: end), lineWidth: 1.4)

                // flowing particles, fading in at the source and out at the destination
                let count = 24
                for i in 0..<count {
                    let u = (CGFloat(i)/CGFloat(count) + CGFloat(t * 0.22)).truncatingRemainder(dividingBy: 1)
                    let p = at(u)
                    let fade = sin(u * .pi)
                    let r = (i % 5 == 0 ? 2.6 : 1.3) * (active ? 1 : 0.55)
                    let color = u < 0.5 ? teal : blue
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x-r, y: p.y-r, width: r*2, height: r*2)),
                             with: .color(color.opacity((active ? 0.9 : 0.4) * fade)))
                }

                // sparkles just off the trail
                for i in 0..<9 {
                    let twinkle = animating ? abs(sin(t * 2.1 + Double(i) * 1.3)) : 0.25
                    let p = at(CGFloat(i)/9)
                    let off = CGFloat(i % 2 == 0 ? -1 : 1) * CGFloat(9 + i)
                    let r = CGFloat(1.1) * twinkle
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x-r, y: p.y+off-r, width: r*2, height: r*2)),
                             with: .color(.white.opacity(twinkle * 0.7)))
                }

                // the comet head racing along — soft edge from two concentric fills, no blur filter
                if animating {
                    let hp = at(CGFloat((t * 0.55).truncatingRemainder(dividingBy: 1)))
                    ctx.fill(Path(ellipseIn: CGRect(x: hp.x-7, y: hp.y-7, width: 14, height: 14)), with: .color(blue.opacity(0.35)))
                    ctx.fill(Path(ellipseIn: CGRect(x: hp.x-4.5, y: hp.y-4.5, width: 9, height: 9)), with: .color(blue.opacity(0.8)))
                    ctx.fill(Path(ellipseIn: CGRect(x: hp.x-3, y: hp.y-3, width: 6, height: 6)), with: .color(.white))
                }

                // arrival pulses at the destination
                for i in 0..<3 {
                    let pulse = animating ? (t * 0.45 + Double(i)/3).truncatingRemainder(dividingBy: 1) : Double(i)/3
                    let rad = CGFloat(16 + pulse * 36)
                    ctx.stroke(Path(ellipseIn: CGRect(x: end.x-rad, y: end.y-rad, width: rad*2, height: rad*2)),
                               with: .color(blue.opacity((1 - pulse) * (active ? 0.32 : 0.1))), lineWidth: 1.4)
                }
            }
        }
        .accessibilityHidden(true)
        .task(id: active) {
            capped = false
            guard active, !reduced else { return }
            try? await Task.sleep(nanoseconds: Self.maxAnimationSeconds * 1_000_000_000)
            capped = true
        }
    }
}

struct RelayPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Color(red: 0.04, green: 0.08, blue: 0.14) : Color.white.opacity(0.35))
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(isEnabled
                        ? LinearGradient(colors: [WhooshGeometry.teal, WhooshGeometry.blue], startPoint: .topLeading, endPoint: .bottomTrailing)
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
