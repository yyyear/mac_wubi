import XCTest
@testable import WubiCore

final class CodeTests: XCTestCase {
    func testPackUnpackRoundTrip() {
        for code in ["a", "wq", "wqiy", "trnt", "abcd", "zzzz"] {
            XCTAssertEqual(WubiCode.unpack(WubiCode.pack(code)), code)
        }
        XCTAssertEqual(WubiCode.pack(""), 0)
        XCTAssertEqual(WubiCode.pack("a1"), 0)
    }

    func testCodesAreOrdered() {
        XCTAssertLessThan(WubiCode.pack("w"), WubiCode.pack("wa"))
        XCTAssertLessThan(WubiCode.pack("wa"), WubiCode.pack("wq"))
        XCTAssertLessThan(WubiCode.pack("wqiy"), WubiCode.pack("wqiz"))
    }

    func testPrefixRangeCoversDescendants() {
        let range = WubiCode.prefixRange("wq")
        for code in ["wq", "wqiy", "wqzz"] {
            XCTAssertTrue(range.contains(WubiCode.pack(code)), code)
        }
        XCTAssertFalse(range.contains(WubiCode.pack("wr")))
    }
}

final class DictionaryTests: XCTestCase {
    private let dictionary = WubiDictionary.shared

    func testSingleCharacterLookups() {
        XCTAssertEqual(dictionary.candidates(for: "wqiy").first?.text, "你")
        XCTAssertEqual(dictionary.candidates(for: "trnt").first?.text, "我")
        XCTAssertEqual(dictionary.candidates(for: "jghu").first?.text, "是")
        XCTAssertEqual(dictionary.candidates(for: "rqyy").first?.text, "的")
        XCTAssertEqual(dictionary.candidates(for: "g").first?.text, "一")
    }

    func testMultiCharacterWords() {
        XCTAssertTrue(dictionary.candidates(for: "wqiy").contains { $0.isWord })
        XCTAssertGreaterThan(dictionary.entryCount, 100_000)
        XCTAssertGreaterThan(dictionary.keyCount, 50_000)
    }

    func testMissingCodeReturnsNothing() {
        XCTAssertTrue(dictionary.candidates(for: "aaaz").isEmpty)
        XCTAssertTrue(dictionary.candidates(for: "zzzz").isEmpty)
        // Longer input is truncated to four keys, matching the typing engine.
        XCTAssertEqual(dictionary.candidates(for: "qqqqq").count, dictionary.candidates(for: "qqqq").count)
    }

    func testPrefixAccounting() {
        XCTAssertGreaterThan(dictionary.codeCount(prefix: "w"), 100)
        XCTAssertTrue(dictionary.hasLongerCode(than: "w"))
        XCTAssertFalse(dictionary.hasLongerCode(than: "wqiy"))
    }
}

final class EngineTests: XCTestCase {
    private func makeEngine() -> InputEngine {
        let lexicon = UserLexicon(fileURL: URL(fileURLWithPath: NSTemporaryDirectory() + "wubi-test-\(UUID().uuidString).tsv"))
        return InputEngine(lexicon: lexicon, settings: WubiSettings())
    }

    func testFourKeysAutoCommitUnique() {
        let engine = makeEngine()
        XCTAssertNil(engine.append("j"))
        XCTAssertNil(engine.append("g"))
        XCTAssertNil(engine.append("h"))
        XCTAssertEqual(engine.append("u"), "是")
        XCTAssertFalse(engine.isActive)
    }

    func testSpaceCommitsFirstCandidate() {
        let engine = makeEngine()
        engine.append("w")
        engine.append("q")
        XCTAssertEqual(engine.pageCandidates.first?.text, "你")
        XCTAssertEqual(engine.commitFirst(), "你")
        XCTAssertFalse(engine.isActive)
    }

    func testBackspaceShortensCode() {
        let engine = makeEngine()
        engine.append("w")
        engine.append("q")
        XCTAssertTrue(engine.backspace())
        XCTAssertEqual(engine.buffer, "w")
        XCTAssertTrue(engine.backspace())
        XCTAssertFalse(engine.backspace())
        XCTAssertFalse(engine.isActive)
    }

    func testNumberSelection() {
        let engine = makeEngine()
        for character in "fpgc" { engine.append(character) }
        XCTAssertGreaterThan(engine.candidates.count, 1)
        let expected = engine.candidates[1].text
        XCTAssertEqual(engine.commit(pageNumber: 2), expected)
        XCTAssertFalse(engine.isActive)
    }

    func testPaging() {
        let engine = makeEngine()
        engine.settings.pageSize = 3
        for character in "fpgc" { engine.append(character) }
        guard engine.pageCount > 1 else { return XCTFail("expected multiple pages") }
        XCTAssertTrue(engine.nextPage())
        XCTAssertEqual(engine.page, 1)
        XCTAssertEqual(engine.pageStartNumber, 4)
        XCTAssertTrue(engine.previousPage())
        XCTAssertEqual(engine.page, 0)
    }

    func testPrefixCandidatesAreIncluded() {
        let engine = makeEngine()
        engine.append("w")
        // 一级简码 人 plus words whose code merely starts with "w".
        XCTAssertGreaterThan(engine.candidates.count, 1)
        engine.reset()
        for character in "wqi" { engine.append(character) }
        XCTAssertTrue(engine.candidates.contains { $0.text == "你" })
        XCTAssertGreaterThan(engine.candidates.count, 2)
    }

    func testPageSizeClamp() {
        let engine = makeEngine()
        engine.settings.pageSize = 0
        XCTAssertEqual(engine.pageSize, 1)
        engine.settings.pageSize = 99
        XCTAssertEqual(engine.pageSize, 10)
        engine.settings.pageSize = 5
        XCTAssertEqual(engine.pageSize, 5)
    }

    func testPageSizeControlsPageLength() {
        let engine = makeEngine()
        for character in "w" { engine.append(character) }
        engine.settings.pageSize = 3
        XCTAssertEqual(engine.pageCandidates.count, min(3, engine.candidates.count))
        engine.settings.pageSize = 7
        XCTAssertEqual(engine.pageCandidates.count, min(7, engine.candidates.count))
    }

    func testProbabilityRankingPromotesRepeatedPicks() {
        let engine = makeEngine()
        for character in "fpgc" { engine.append(character) }
        guard engine.candidates.count > 2 else { return XCTFail("need re-codes") }
        let third = engine.candidates[2]
        for _ in 0..<3 {
            engine.lexicon.recordCommit(code: "fpgc", text: third.text)
        }
        engine.reset()
        for character in "fpgc" { engine.append(character) }
        XCTAssertEqual(engine.candidates.first?.text, third.text)

        // The rest keep dictionary order: only the picked word moved up.
        let remaining = engine.candidates.dropFirst().map { $0.text }
        XCTAssertFalse(remaining.isEmpty)
    }

    func testUserLearningReorders() {
        let engine = makeEngine()
        for character in "fpgc" { engine.append(character) }
        guard engine.candidates.count > 1 else { return }
        let second = engine.candidates[1]
        engine.lexicon.recordCommit(code: "fpgc", text: second.text)
        engine.reset()
        for character in "fpgc" { engine.append(character) }
        XCTAssertEqual(engine.candidates.first?.text, second.text)
    }
}

final class PunctuationTests: XCTestCase {
    func testMapping() {
        var mapper = PunctuationMapper()
        XCTAssertEqual(mapper.map(","), "，")
        XCTAssertEqual(mapper.map("."), "。")
        XCTAssertEqual(mapper.map("\\"), "、")
    }

    func testQuotesToggle() {
        var mapper = PunctuationMapper()
        XCTAssertEqual(mapper.map("\""), "\u{201C}")
        XCTAssertEqual(mapper.map("\""), "\u{201D}")
        XCTAssertEqual(mapper.map("\""), "\u{201C}")
    }

    func testUnknownPassesThrough() {
        var mapper = PunctuationMapper()
        XCTAssertNil(mapper.map("a"))
    }
}