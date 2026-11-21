import AppKit
import XCTest
@testable import WubiUI

final class CandidateGlyphDisplayTests: XCTestCase {
    func testSupportedQuestionMarksAndChineseStayLiteral() {
        let text = "工?？"
        for weight: NSFont.Weight in [.regular, .medium] {
            let display = CandidateGlyphDisplay.resolve(text, font: .systemFont(ofSize: 16, weight: weight))
            XCTAssertEqual(display.text, text)
            XCTAssertNil(display.toolTip)
        }
    }

    func testOnlyMissingGraphemeUsesCodePointsIncludingVariationSelector() {
        let cluster: Character = "\u{27763}\u{E0100}"
        let text = "花\(cluster)？𦾟"
        let display = CandidateGlyphDisplay.resolve(text) { $0 == cluster }
        XCTAssertEqual(display.text, "花U+27763 U+E0100？𦾟")
        XCTAssertNotNil(display.toolTip)
    }

    func testExplicitLastResortFontIsDetectedEvenForNonZeroGlyph() throws {
        let font = try XCTUnwrap(NSFont(name: "LastResort", size: 16))
        let display = CandidateGlyphDisplay.resolve("𧝣", font: font)
        XCTAssertEqual(display.text, "U+27763")
        XCTAssertNotNil(display.toolTip)
    }
}
