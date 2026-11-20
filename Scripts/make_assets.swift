import AppKit
import CoreImage
import Foundation

/// Builds every image asset the bundle needs from the two generated artworks:
///   Resources/generated/icon-raw.png   -> AppIcon.icns + icon.tiff (menu icon)
///   Resources/generated/badge-raw.png  -> WubiUI/Resources/badge-zh.png, badge-en.png
///
/// Run with: swift Scripts/make_assets.swift

let root = FileManager.default.currentDirectoryPath
let resourceDir = root + "/Resources"
let badgeDir = root + "/Sources/WubiUI/Resources"
try? FileManager.default.createDirectory(atPath: badgeDir, withIntermediateDirectories: true)

func loadImage(_ path: String) -> NSImage? {
    guard let image = NSImage(contentsOfFile: path) else { return nil }
    return image
}

func bitmap(_ image: NSImage, width: Int, height: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: width,
                                     pixelsHigh: height,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy,
               fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Transparency

/// macOS icons are squircle tiles with fully transparent corners. The generated
/// artwork fills its whole canvas, so re-mask it: transparent outside a rounded
/// rectangle, opaque inside. Without this the icon shows an ugly opaque square
/// border in the Dock, the input menu and the mode badge.
func masked(_ image: NSImage, size: Int, radiusFraction: CGFloat) -> NSImage? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: size,
                                     pixelsHigh: size,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else { return nil }
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = CGFloat(size) * radiusFraction
    let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    clip.addClip()
    image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return NSImage(size: rect.size, flipped: false) { _ in
        NSImage(cgImage: rep.cgImage!, size: rect.size).draw(in: rect)
        return true
    }
}

func maskedPNG(_ image: NSImage, pixels: Int, radiusFraction: CGFloat) -> Data? {
    guard let maskedImage = masked(image, size: pixels, radiusFraction: radiusFraction),
          let rep = bitmap(maskedImage, width: pixels, height: pixels) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

// MARK: - App icon

guard let iconSource = loadImage(resourceDir + "/generated/icon-raw.png") else {
    FileHandle.standardError.write("missing Resources/generated/icon-raw.png\n".data(using: .utf8)!)
    exit(1)
}

let iconsetPath = resourceDir + "/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

// macOS app icons use a 22.37% corner radius and transparent outside.
let appIconRadius: CGFloat = 0.2237

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        guard let data = maskedPNG(iconSource, pixels: pixels, radiusFraction: appIconRadius) else { continue }
        let suffix = scale == 1 ? "" : "@2x"
        try? data.write(to: URL(fileURLWithPath: iconsetPath + "/icon_\(base)x\(base)\(suffix).png"))
    }
}

// Menu bar icon: one TIFF holding a 16pt @1x and a 16pt @2x representation, so
// AppKit draws it at the right size instead of scaling a 32pt image into a
// 16pt slot (which is what made the icon look shifted downwards).
let menuImage = NSImage(size: NSSize(width: 16, height: 16))
for scale in [1, 2] {
    let pixels = 16 * scale
    guard let maskedMenu = masked(iconSource, size: pixels, radiusFraction: appIconRadius),
          let rep = bitmap(maskedMenu, width: pixels, height: pixels) else { continue }
    rep.size = NSSize(width: 16, height: 16)
    menuImage.addRepresentation(rep)
}
if let tiff = menuImage.tiffRepresentation {
    try? tiff.write(to: URL(fileURLWithPath: resourceDir + "/icon.tiff"))
}

// MARK: - Mode HUD icons

/// The HUD shows a single glyph badge: 中 for Chinese, A for English.
for (name, source) in [("hud-zh", "hud-zh-raw"), ("hud-en", "hud-en-raw")] {
    guard let image = loadImage(resourceDir + "/generated/" + source + ".png") else {
        FileHandle.standardError.write("missing \(source).png\n".data(using: .utf8)!)
        continue
    }
    guard let data = maskedPNG(image, pixels: 128, radiusFraction: 0.28) else { continue }
    try? data.write(to: URL(fileURLWithPath: badgeDir + "/" + name + ".png"))
}

print("assets written: icon.tiff, AppIcon.iconset, hud-zh.png, hud-en.png (transparent corners)")
