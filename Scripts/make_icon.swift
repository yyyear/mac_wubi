import AppKit
import Foundation

/// Draws the input method icon: a rounded square with the 五 glyph.
/// Run with: swift Scripts/make_icon.swift <output-dir>

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let fm = FileManager.default
try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.22
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.04, dy: size * 0.04),
                            xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.20, green: 0.32, blue: 0.78, alpha: 1.0),
        NSColor(srgbRed: 0.09, green: 0.16, blue: 0.44, alpha: 1.0),
    ])
    gradient?.draw(in: path, angle: -90)

    let glyph = "五" as NSString
    let font = NSFont.systemFont(ofSize: size * 0.56, weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let bounds = glyph.size(withAttributes: attributes)
    let origin = NSPoint(x: (size - bounds.width) / 2,
                         y: (size - bounds.height) / 2 + size * 0.02)
    glyph.draw(at: origin, withAttributes: attributes)

    return image
}

func writePNG(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: url)
}

// Input method menu icon (16x16 @2x) as TIFF.
let menuIcon = drawIcon(size: 32)
if let tiff = menuIcon.tiffRepresentation {
    try? tiff.write(to: URL(fileURLWithPath: outputDir).appendingPathComponent("icon.tiff"))
}

// App icon set for the bundle.
let setDir = URL(fileURLWithPath: outputDir).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: setDir)
try? fm.createDirectory(at: setDir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(drawIcon(size: CGFloat(base)), to: setDir.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(drawIcon(size: CGFloat(base * 2)), to: setDir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("icons written to \(outputDir)")
