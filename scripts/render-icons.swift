import AppKit
import Foundation

@main @MainActor struct RenderIcons {
    static func write(_ image: NSImage, pixels: Int, to url: URL) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
        image.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels))
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using:.png,properties:[:])!.write(to:url)
    }
    static func main() throws {
        let output = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        for size in [16,32,128,256,512] {
            for scale in [1,2] {
                let pixels=size*scale
                try write(WhooshIdentity.icon(size:CGFloat(pixels)),pixels:pixels,to:output.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
            }
        }
        let menuPreview = NSImage(size:NSSize(width:20,height:20),flipped:false) { rect in
            NSColor.white.setFill(); NSBezierPath(rect:rect).fill()
            WhooshIdentity.icon(size:20,template:true).draw(in:rect)
            return true
        }
        try write(menuPreview,pixels:20,to:output.deletingLastPathComponent().appendingPathComponent("whoosh-menu-20-preview.png"))
        try write(WhooshIdentity.icon(size:20,template:true),pixels:20,to:output.deletingLastPathComponent().appendingPathComponent("whoosh-menu-20.png"))
        try write(WhooshIdentity.icon(size:32),pixels:32,to:output.deletingLastPathComponent().appendingPathComponent("whoosh-app-32.png"))
    }
}
