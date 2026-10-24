import AppKit
import SwiftUI

/// The Whoosh mark: a comet streaking forward — motion, speed, a handoff in flight.
/// Unit-space geometry (y-down) shared by the SwiftUI mark and the rendered app icon.
enum WhooshGeometry {
    /// A comet with a rounded head on the right and a tail tapering to the lower-left.
    /// `surge` nudges the head forward for the "about to launch" state.
    static func comet(in r: CGRect, surge: CGFloat = 0) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        let s = surge * 0.06
        var path = Path()
        path.move(to: p(0.06, 0.78))                                                 // sharp tail tip, lower-left
        path.addCurve(to: p(0.74 + s, 0.22), control1: p(0.30, 0.54), control2: p(0.54, 0.26))  // sweep up to head
        path.addQuadCurve(to: p(0.80 + s, 0.46), control: p(0.96 + s, 0.30))          // rounded head front
        path.addQuadCurve(to: p(0.06, 0.78), control: p(0.40, 0.60))                  // lower edge back to tail
        path.closeSubpath()
        return path
    }
    /// Center of the comet head's specular highlight, in unit space.
    static func head(in r: CGRect, surge: CGFloat = 0) -> CGRect {
        let d = min(r.width, r.height) * 0.11
        let c = CGPoint(x: r.minX + r.width * (0.74 + surge * 0.06), y: r.minY + r.height * 0.33)
        return CGRect(x: c.x - d/2, y: c.y - d/2, width: d, height: d)
    }
    /// Two short speed streaks trailing the comet.
    static func streaks(in r: CGRect) -> [Path] {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        return [
            { var a = Path(); a.move(to: p(0.06, 0.40)); a.addQuadCurve(to: p(0.40, 0.30), control: p(0.22, 0.31)); return a }(),
            { var a = Path(); a.move(to: p(0.08, 0.84)); a.addQuadCurve(to: p(0.44, 0.74), control: p(0.24, 0.80)); return a }(),
        ]
    }
    // "Flow" palette: a teal head fading to blue — movement, a handoff in flight.
    static let teal = Color(red: 0.357, green: 0.910, blue: 0.784)
    static let blue = Color(red: 0.298, green: 0.553, blue: 1.0)
    /// The single UI accent (selected rows, primary buttons, focus) — the comet's blue.
    static let accent = blue
}

struct WhooshMark: View {
    var active = false
    var forceReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var surge: CGFloat = 0
    private var reduced: Bool { systemReduceMotion || forceReduceMotion }

    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)
            let path = WhooshGeometry.comet(in: r, surge: surge)
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [WhooshGeometry.teal.opacity(0.95), WhooshGeometry.blue]),
                startPoint: CGPoint(x: r.minX, y: r.maxY), endPoint: CGPoint(x: r.maxX, y: r.minY))
            // soft glow
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: size.width * 0.06))
                layer.fill(path, with: .color(WhooshGeometry.blue.opacity(active ? 0.9 : 0.5)))
            }
            // body
            ctx.fill(path, with: shading)
            // speed streaks
            for streak in WhooshGeometry.streaks(in: r) {
                ctx.stroke(streak, with: .color(WhooshGeometry.teal.opacity(active ? 0.9 : 0.6)),
                           style: StrokeStyle(lineWidth: size.width * 0.045, lineCap: .round))
            }
            // bright head highlight
            ctx.fill(Path(ellipseIn: WhooshGeometry.head(in: r, surge: surge)),
                     with: .color(.white.opacity(active ? 0.95 : 0.78)))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: surge)
        .task(id: active) {
            guard active, !reduced else { surge = 0; return }
            surge = 1
            try? await Task.sleep(nanoseconds: 260_000_000)
            surge = 0
        }
        .accessibilityHidden(true)
    }
}

@MainActor
enum WhooshIdentity {
    #if !BLINK_ICON_RENDERER
    static func providerIcon(_ app: RelayModel.AgentApp) -> NSImage? {
        let id = app == .codex ? "com.openai.codex" : "com.anthropic.claudefordesktop"
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
              Bundle(url: url)?.bundleIdentifier == id else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    #endif

    /// App / menu-bar icon: the comet mark, gradient on a dark rounded tile (template = flat monochrome).
    static func icon(size: CGFloat, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            if !template {
                NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1).setFill()
                NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()
            }
            let inset = rect.insetBy(dx: size * 0.16, dy: size * 0.16)
            let comet = WhooshGeometry.comet(in: inset).cgPath
            if template {
                NSColor.black.setFill(); ctx.addPath(comet); ctx.fillPath()
            } else {
                ctx.saveGState(); ctx.addPath(comet); ctx.clip()
                let colors = [NSColor(calibratedRed: 0.357, green: 0.910, blue: 0.784, alpha: 1).cgColor,
                              NSColor(calibratedRed: 0.298, green: 0.553, blue: 1.0, alpha: 1).cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    ctx.drawLinearGradient(g, start: CGPoint(x: inset.minX, y: inset.maxY),
                                           end: CGPoint(x: inset.maxX, y: inset.minY), options: [])
                }
                ctx.restoreGState()
                NSColor.white.withAlphaComponent(0.85).setFill()
                NSBezierPath(ovalIn: WhooshGeometry.head(in: inset)).fill()
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}
