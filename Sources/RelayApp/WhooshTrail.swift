import SwiftUI

/// The whoosh: a comet of particles streaming along an arc from the source to the destination,
/// with a glowing trail, a traveling head, sparkles, and arrival pulses. Purely decorative —
/// time drives the motion, never the reported work or completion state.
struct WhooshTrail: View {
    let active: Bool
    var forceReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduced: Bool { systemReduceMotion || forceReduceMotion }
    private let mint = WhooshGeometry.mint
    private let amber = WhooshGeometry.amber

    private func bezier(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, _ u: CGFloat) -> CGPoint {
        let v = 1 - u
        let x = v*v*v*p0.x + 3*v*v*u*c1.x + 3*v*u*u*c2.x + u*u*u*p3.x
        let y = v*v*v*p0.y + 3*v*v*u*c1.y + 3*v*u*u*c2.y + u*u*u*p3.y
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0, paused: !active || reduced)) { timeline in
            Canvas { ctx, size in
                let t = active && !reduced ? timeline.date.timeIntervalSinceReferenceDate : 0
                let start = CGPoint(x: 34, y: size.height/2)
                let end = CGPoint(x: size.width - 34, y: size.height/2)
                let c1 = CGPoint(x: size.width*0.38, y: size.height*0.10)
                let c2 = CGPoint(x: size.width*0.62, y: size.height*0.90)
                func at(_ u: CGFloat) -> CGPoint { bezier(start, c1, c2, end, max(0, min(1, u))) }

                var path = Path(); path.move(to: start); path.addCurve(to: end, control1: c1, control2: c2)
                // glow under the trail
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 7))
                    l.stroke(path, with: .color(amber.opacity(active ? 0.4 : 0.15)), lineWidth: 4)
                }
                // the trail line
                ctx.stroke(path, with: .linearGradient(
                    Gradient(colors: [mint.opacity(0.15), mint, amber, amber.opacity(0.15)]),
                    startPoint: start, endPoint: end), lineWidth: 1.4)

                // flowing particles, fading in at the source and out at the destination
                let count = 30
                for i in 0..<count {
                    let u = (CGFloat(i)/CGFloat(count) + CGFloat(t * 0.22)).truncatingRemainder(dividingBy: 1)
                    let p = at(u)
                    let fade = sin(u * .pi)
                    let r = (i % 5 == 0 ? 2.6 : 1.3) * (active ? 1 : 0.55)
                    let color = u < 0.5 ? mint : amber
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x-r, y: p.y-r, width: r*2, height: r*2)),
                             with: .color(color.opacity((active ? 0.9 : 0.4) * fade)))
                }

                // sparkles just off the trail
                for i in 0..<9 {
                    let twinkle = active && !reduced ? abs(sin(t * 2.1 + Double(i) * 1.3)) : 0.25
                    let p = at(CGFloat(i)/9)
                    let off = CGFloat(i % 2 == 0 ? -1 : 1) * CGFloat(9 + i)
                    let r = CGFloat(1.1) * twinkle
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x-r, y: p.y+off-r, width: r*2, height: r*2)),
                             with: .color(.white.opacity(twinkle * 0.7)))
                }

                // the comet head racing along
                if active && !reduced {
                    let hp = at(CGFloat((t * 0.55).truncatingRemainder(dividingBy: 1)))
                    ctx.drawLayer { l in
                        l.addFilter(.blur(radius: 5))
                        l.fill(Path(ellipseIn: CGRect(x: hp.x-7, y: hp.y-7, width: 14, height: 14)), with: .color(amber.opacity(0.9)))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: hp.x-3, y: hp.y-3, width: 6, height: 6)), with: .color(.white))
                }

                // arrival pulses at the destination
                for i in 0..<3 {
                    let pulse = active && !reduced ? (t * 0.45 + Double(i)/3).truncatingRemainder(dividingBy: 1) : Double(i)/3
                    let rad = CGFloat(16 + pulse * 36)
                    ctx.stroke(Path(ellipseIn: CGRect(x: end.x-rad, y: end.y-rad, width: rad*2, height: rad*2)),
                               with: .color(amber.opacity((1 - pulse) * (active ? 0.32 : 0.1))), lineWidth: 1.4)
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
                        ? LinearGradient(colors: [Color(red: 0.55, green: 0.95, blue: 0.82), Color(red: 1, green: 0.62, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
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
