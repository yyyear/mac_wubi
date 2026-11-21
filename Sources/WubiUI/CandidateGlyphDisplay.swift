import AppKit
import CoreText

/// Presentation only: selection still uses the original candidate string.
struct CandidateGlyphDisplay {
    let text: String
    let toolTip: String?

    // Include the actual font (size/weight) in the key, not just the scalar.
    private static let missingCache: NSCache<NSAttributedString, NSNumber> = {
        let cache = NSCache<NSAttributedString, NSNumber>()
        cache.countLimit = 4096
        return cache
    }()

    static func resolve(_ text: String, font: NSFont) -> Self {
        resolve(text) { character in
            let sample = NSAttributedString(string: String(character), attributes: [.font: font])
            if let cached = missingCache.object(forKey: sample) { return cached.boolValue }
            let missing = hasMissingGlyph(in: sample)
            missingCache.setObject(NSNumber(value: missing), forKey: sample)
            return missing
        }
    }

    static func resolve(_ original: String, isMissing: (Character) -> Bool) -> Self {
        var display = ""
        var substituted = false
        for character in original {
            if isMissing(character) {
                display += character.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
                substituted = true
            } else {
                display.append(character)
            }
        }
        return Self(text: display, toolTip: substituted ? "当前字体无法显示部分字符，已用 Unicode 码位标示。选择后仍会输入原文。" : nil)
    }

    private static func hasMissingGlyph(in sample: NSAttributedString) -> Bool {
        // Shape the entire grapheme, including supplementary scalars and variation
        // selectors. Checking only the base font would reject working fallbacks.
        let line = CTLineCreateWithAttributedString(sample)
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let font = attributes[kCTFontAttributeName] as! CTFont
            // LastResort draws a visible placeholder, often with a NON-zero glyph ID.
            if (CTFontCopyPostScriptName(font) as String).lowercased().hasSuffix("lastresort") { return true }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            if glyphs.contains(0) { return true }
        }
        return false
    }
}
