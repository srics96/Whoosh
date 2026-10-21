import AppKit
import SwiftUI

/// Original split-lid blink mark; provider branding is loaded separately, unchanged.
struct BlinkAperture: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.14, y: r.minY + r.height * 0.50))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.86, y: r.minY + r.height * 0.50), control1: CGPoint(x: r.minX + r.width * 0.30, y: r.minY + r.height * 0.16), control2: CGPoint(x: r.minX + r.width * 0.70, y: r.minY + r.height * 0.16))
        p.move(to: CGPoint(x: r.minX + r.width * 0.27, y: r.minY + r.height * 0.68))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.73, y: r.minY + r.height * 0.68), control: CGPoint(x: r.midX, y: r.minY + r.height * 0.91))
        p.move(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.43))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.57))
        return p
    }
}

struct BlinkMark: View {
    var active = false
    var forceReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var closed = false
    private var reduced: Bool { systemReduceMotion || forceReduceMotion }
    var body: some View {
        BlinkAperture().stroke(Color(red: 1, green: 0.75, blue: 0.57), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .scaleEffect(x: 1, y: closed && !reduced ? 0.14 : 1)
            .opacity(active ? 1 : 0.72)
            .animation(.easeInOut(duration: reduced ? 0.15 : 0.18), value: closed)
            .animation(.easeInOut(duration: 0.15), value: active)
            .task(id: active) {
                closed = false
                guard active, !reduced else { return }
                closed = true
                do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
                closed = false
            }
            .accessibilityHidden(true)
    }
}

@MainActor
enum BlinkIdentity {
    #if !BLINK_ICON_RENDERER
    static func providerIcon(_ app: RelayModel.AgentApp) -> NSImage? {
        let id = app == .codex ? "com.openai.codex" : "com.anthropic.claudefordesktop"
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
              Bundle(url: url)?.bundleIdentifier == id else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    #endif
    static func icon(size: CGFloat, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            if !template {
                NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1).setFill()
                NSBezierPath(roundedRect: rect, xRadius: size * 0.23, yRadius: size * 0.23).fill()
            }
            (template ? NSColor.black : NSColor(calibratedRed: 1, green: 0.75, blue: 0.57, alpha: 1)).setStroke()
            let p = NSBezierPath()
            p.lineWidth = size * 0.055; p.lineCapStyle = .round; p.lineJoinStyle = .round
            p.move(to: NSPoint(x: size * 0.20, y: size * 0.50))
            p.curve(to: NSPoint(x: size * 0.80, y: size * 0.50), controlPoint1: NSPoint(x: size * 0.34, y: size * 0.78), controlPoint2: NSPoint(x: size * 0.66, y: size * 0.78))
            p.move(to: NSPoint(x: size * 0.31, y: size * 0.35))
            p.curve(to: NSPoint(x: size * 0.69, y: size * 0.35), controlPoint1: NSPoint(x: size * 0.43, y: size * 0.23), controlPoint2: NSPoint(x: size * 0.57, y: size * 0.23))
            p.move(to: NSPoint(x: size * 0.50, y: size * 0.56)); p.line(to: NSPoint(x: size * 0.50, y: size * 0.44)); p.stroke()
            return true
        }
        image.isTemplate = template
        return image
    }
}
