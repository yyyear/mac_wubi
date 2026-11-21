import XCTest
@testable import WubiCore

final class LiteralCompositionTests: XCTestCase {
    private func engine(_ scheme: InputScheme = .wubi,
                        lookup: @escaping InputEngine.Lookup = { _, _, _, _ in [] }) -> InputEngine {
        var settings = WubiSettings()
        settings.inputScheme = scheme
        settings.prefixCandidates = false
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return InputEngine(lexicon: UserLexicon(fileURL: file), settings: settings, lookup: lookup)
    }

    func testCapitalizedUniqueCodeWaitsForExplicitSelection() {
        let input = engine()
        for c in "JgHu" { XCTAssertNil(input.append(c)) }
        XCTAssertEqual(input.buffer, "JgHu")
        XCTAssertEqual(input.commitFirst(), "是")
        XCTAssertEqual(input.lexicon.boost(for: "jghu", text: "是"), 1)
        XCTAssertTrue(input.buffer.isEmpty)
        for c in "jgh" { XCTAssertNil(input.append(c)) }
        XCTAssertEqual(input.append("u"), "是")
    }

    func testLongMixedCaseLiteralSurvivesRolloverAndBackspace() {
        let input = engine()
        for c in "SwiftUI" {
            XCTAssertFalse(input.requiresWubiRollover(before: c))
            XCTAssertNil(input.append(c))
        }
        XCTAssertEqual(input.buffer, "SwiftUI")
        XCTAssertTrue(input.backspace())
        XCTAssertEqual(input.buffer, "SwiftU")
        input.reset()
        XCTAssertFalse(input.isActive)
    }

    func testCapitalCanExtendAnAlreadyFullLowercaseCode() {
        let input = engine()
        for c in "zzzz" { XCTAssertNil(input.append(c)) }
        XCTAssertTrue(input.requiresWubiRollover(before: "a"))
        XCTAssertFalse(input.requiresWubiRollover(before: "A"))
        XCTAssertNil(input.append("A"))
        XCTAssertEqual(input.buffer, "zzzzA")
        XCTAssertTrue(input.backspace())
        XCTAssertTrue(input.requiresWubiRollover(before: "a"))
    }

    func testMixedCasePinyinKeepsLiteralWhileMatchingLowercase() {
        for scheme in [InputScheme.pinyin, .mixed] {
            let input = engine(scheme) { code, source, prefix, _ in
                guard source == .pinyin, !prefix, code == "xian" else { return [] }
                return [WubiCandidate(text: "西安", weight: 1, flags: 1)]
            }
            for c in "Xi'An" { XCTAssertNil(input.append(c)) }
            XCTAssertEqual(input.buffer, "Xi'An")
            XCTAssertEqual(input.commitFirst(), "西安")
        }
    }
}
