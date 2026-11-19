import AppKit
import Foundation

/// Draws the mode HUD exactly like WeType's: a dark translucent rounded square
/// with a single white glyph (中 / 英). Drawn natively so the text is pixel crisp
/// and the corners stay fully transparent.
///
/// Run with: swift Scripts/make_hud.swift

let outDir = FileManager.default.currentDirectoryPath + "/Sources/WubiUI/Resources"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func drawBadge(_ glyph: String, size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    // Transparent background: do not fill the canvas at all.
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    // Dark rounded square, slight translucency like the system HUD.
    let inset = size * 0.03
    let radius = size * 0.22
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
    NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 0.92).setFill()
    path.fill()

    // Hairline border for definition on light backgrounds.
    NSColor(white: 1.0, alpha: 0.10).setStroke()
    path.lineWidth = max(1, size * 0.012)
    path.stroke()

    let font = NSFont.systemFont(ofSize: size * 0.52, weight: .medium)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let text = glyph as NSString
    let bounds = text.size(withAttributes: attributes)
    // Centre on the cap box rather than the line box so 中 sits optically true.
    let origin = NSPoint(x: (size - bounds.width) / 2,
                         y: (size - bounds.height) / 2 + size * 0.02)
    text.draw(at: origin, withAttributes: attributes)

    return image
}

func writePNG(_ image: NSImage, pixels: Int, to path: String) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
}

// 4x for retina crispness: drawn at 96px, displayed at 24pt.
for (glyph, name) in [("中", "hud-zh"), ("英", "hud-en")] {
    // Render at 4x then keep the full resolution; AppKit downsamples smoothly.
    let badge = drawBadge(glyph, size: 96)
    writePNG(badge, pixels: 96, to: outDir + "/" + name + ".png")
}

print("HUD badges written: hud-zh.png (中), hud-en.png (英)")
