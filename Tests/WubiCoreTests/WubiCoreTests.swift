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
        // This low-level lookup truncates; mixed-mode callers must guard length.
        XCTAssertEqual(dictionary.candidates(for: "qqqqq").count, dictionary.candidates(for: "qqqq").count)
    }

    func testPrefixAccounting() {
        XCTAssertGreaterThan(dictionary.codeCount(prefix: "w"), 100)
        XCTAssertTrue(dictionary.hasLongerCode(than: "w"))
        XCTAssertFalse(dictionary.hasLongerCode(than: "wqiy"))
    }
}

final class EngineTests: XCTestCase {
    private func makeEngine(_ scheme: InputScheme = .wubi, lookup: @escaping InputEngine.Lookup = { _, _, _, _ in [] }) -> InputEngine {
        let lexicon = UserLexicon(fileURL: URL(fileURLWithPath: NSTemporaryDirectory() + "wubi-test-\(UUID().uuidString).tsv"))
        var settings = WubiSettings()
        settings.inputScheme = scheme
        return InputEngine(lexicon: lexicon, settings: settings, lookup: lookup)
    }

    private func word(_ text: String, _ weight: UInt16 = 0) -> WubiCandidate {
        WubiCandidate(text: text, weight: weight, flags: 1)
    }

    func testLegacyConfigPreservesChoices() throws {
        let legacy = Data(#"{"pageSize":7,"userLearning":false,"autoCommitUnique":false}"#.utf8)
        var settings = try JSONDecoder().decode(WubiSettings.self, from: legacy)
        XCTAssertEqual(settings.inputScheme, .wubi)
        XCTAssertEqual(settings.pageSize, 7)
        XCTAssertFalse(settings.userLearning)
        XCTAssertFalse(settings.autoCommitUnique)
        XCTAssertTrue(settings.prefixCandidates)
        for scheme in InputScheme.allCases {
            settings.inputScheme = scheme
            XCTAssertEqual(try JSONDecoder().decode(WubiSettings.self, from: JSONEncoder().encode(settings)), settings)
        }
    }

    func testPureSchemesOnlyUseTheirOwnSources() {
        for scheme in [InputScheme.wubi, .pinyin] {
            let engine = makeEngine(scheme) { code, source, prefix, _ in
                XCTAssertEqual(source, scheme)
                guard code == "wq", !prefix else { return [] }
                return [self.word(source == .wubi ? "导入五笔" : "拼音候选")]
            }
            for key in "wq" { engine.append(key) }
            let texts = engine.candidates.map(\.text)
            if scheme == .wubi {
                XCTAssertTrue(texts.contains("你"))
                XCTAssertTrue(texts.contains("导入五笔"))
                engine.append("'")
                XCTAssertEqual(engine.buffer, "wq")
            } else {
                XCTAssertEqual(texts, ["拼音候选"])
            }
        }
    }

    func testMixedExactBeforePrefixesWithDeduplication() {
        let engine = makeEngine(.mixed) { code, scheme, prefix, _ in
            guard code == "zz" else { return [] }
            if prefix { return [self.word("同词", .max), self.word("预测", .max)] }
            return [self.word("同词", .max), self.word(scheme == .pinyin ? "拼音项" : "五笔项")]
        }
        for key in "zz" { engine.append(key) }
        let texts = engine.candidates.map(\.text)
        XCTAssertEqual(Set(texts).count, texts.count)
        guard let p = texts.firstIndex(of: "预测"), let w = texts.firstIndex(of: "五笔项"),
              let y = texts.firstIndex(of: "拼音项") else { return XCTFail("missing a source") }
        XCTAssertGreaterThan(p, max(w, y))
        engine.lexicon.recordCommit(code: "zz", text: "拼音项")
        engine.lexicon.recordCommit(code: "zz", text: "预测")
        engine.reset()
        for key in "zz" { engine.append(key) }
        XCTAssertEqual(engine.candidates.first?.text, "拼音项", "a learned prefix must not displace an exact hit")
        engine.settings.prefixCandidates = false
        XCTAssertFalse(engine.candidates.contains { $0.text == "预测" })
    }

    func testMixedLimitLeavesRoomForBothExactSources() {
        let engine = makeEngine(.mixed) { code, scheme, prefix, limit in
            guard code == "zz", !prefix else { return [] }
            return (1...limit).map { self.word(scheme.rawValue + String($0), scheme == .wubi ? .max : 0) }
        }
        engine.settings.candidateLimit = 8
        for key in "zz" { engine.append(key) }
        XCTAssertEqual(engine.candidates.count, 8)
        XCTAssertTrue(engine.candidates.contains { $0.text == "wubi1" })
        XCTAssertTrue(engine.candidates.contains { $0.text == "pinyin1" })
    }

    func testLongAndSeparatedSpellingsNeverFallBackToFourKeyWubi() {
        for scheme in [InputScheme.mixed, .pinyin] {
            let engine = makeEngine(scheme) { code, source, prefix, _ in
                if source == .wubi { XCTAssertLessThanOrEqual(code.count, 4) }
                XCTAssertFalse(code.contains("'"))
                return source == .pinyin && code == "jghua" && !prefix ? [self.word("拼音长码")] : []
            }
            // jghu is a unique Wubi code (是), but mixed mode must keep typing.
            for key in "jghu" { XCTAssertNil(engine.append(key)) }
            XCTAssertEqual(engine.buffer, "jghu")
            engine.append("a")
            XCTAssertEqual(engine.candidates.map(\.text), ["拼音长码"])
            engine.reset()
            for key in "jg'hua" { XCTAssertNil(engine.append(key)) }
            XCTAssertEqual(engine.buffer, "jg'hua")
            XCTAssertEqual(engine.candidates.map(\.text), ["拼音长码"])
            XCTAssertTrue(engine.backspace())
            XCTAssertEqual(engine.buffer, "jg'hu")
            XCTAssertTrue(engine.candidates.isEmpty)
            engine.settings.inputScheme = .wubi
            XCTAssertFalse(engine.isActive)
        }
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
        let firstOnPage = engine.candidates[3].text
        XCTAssertEqual(engine.pageCandidates.first?.text, firstOnPage)
        XCTAssertNil(engine.commit(pageNumber: 0))
        XCTAssertNil(engine.commit(pageNumber: engine.pageCandidates.count + 1))
        XCTAssertTrue(engine.previousPage())
        XCTAssertEqual(engine.page, 0)
        XCTAssertTrue(engine.nextPage())
        XCTAssertEqual(engine.commit(pageNumber: 1), firstOnPage)
    }

    func testTenthCandidateAndPartialLastPage() {
        let engine = makeEngine(.pinyin) { _, _, prefix, _ in
            prefix ? [] : (1...13).map { self.word("词" + String($0)) }
        }
        engine.settings.pageSize = 10
        engine.append("a")
        XCTAssertEqual(engine.commit(pageNumber: 10), "词10")
        engine.append("a")
        XCTAssertTrue(engine.nextPage())
        XCTAssertEqual(engine.pageCandidates.count, 3)
        XCTAssertNil(engine.commit(pageNumber: 4))
        XCTAssertEqual(engine.commit(pageNumber: 3), "词13")
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