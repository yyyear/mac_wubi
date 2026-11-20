import XCTest
@testable import WubiCore

final class FuzzyPinyinTests: XCTestCase {
    func testAllPairsBidirectionalIndividually() {
        let cases: [(FuzzyPair, String, String)] = [
            (.zZh,"zan","zhan"), (.cCh,"can","chan"), (.sSh,"san","shan"),
            (.nL,"nan","lan"), (.fH,"fa","ha"), (.lR,"lan","ran"),
            (.anAng,"xian","xiang"), (.enEng,"chen","cheng"), (.inIng,"lin","ling")
        ]
        XCTAssertEqual(FuzzyPair.allCases, cases.map { $0.0 })
        XCTAssertEqual(FuzzyPair.defaults, [.zZh,.cCh,.sSh,.anAng,.enEng,.inIng])
        for (rule, a, b) in cases {
            XCTAssertTrue(FuzzyPinyin.variants(for: a, rules: [rule]).contains(b), a)
            XCTAssertTrue(FuzzyPinyin.variants(for: b, rules: [rule]).contains(a), b)
            XCTAssertFalse(FuzzyPinyin.variants(for: a, rules: []).contains(b))
        }
    }

    func testWholeSyllablesBoundariesCompoundsAndBudget() {
        let all = Set(FuzzyPair.allCases)
        for code in ["zongguo", "zong'guo"] {
            XCTAssertTrue(FuzzyPinyin.variants(for: code, rules: [.zZh]).contains("zhongguo"))
        }
        XCTAssertTrue(FuzzyPinyin.variants(for: "senzeng", rules: FuzzyPair.defaults).contains("shenzhen"))
        XCTAssertTrue(FuzzyPinyin.variants(for: "fong", rules: [.fH]).contains("hong"))
        XCTAssertFalse(FuzzyPinyin.variants(for: "fen", rules: [.nL]).contains("fel"))
        XCTAssertFalse(FuzzyPinyin.variants(for: "nan", rules: [.nL, .lR]).contains("ran"))
        for code in ["xk", "qcsfj", "zz", "z'ong", "zong'", String(repeating: "san", count: 30)] {
            XCTAssertTrue(FuzzyPinyin.variants(for: code, rules: all).isEmpty, code)
        }
        let many = FuzzyPinyin.variants(for: String(repeating: "san", count: 12), rules: all)
        XCTAssertFalse(many.isEmpty); XCTAssertLessThanOrEqual(many.count, FuzzyPinyin.variantLimit)
        XCTAssertEqual(Set(many).count, many.count)
    }

    func testRankingAndDisablingInEachScheme() {
        for scheme in InputScheme.allCases {
            let word: (String, UInt16) -> WubiCandidate = { WubiCandidate(text: $0, weight: $1, flags: 0) }
            var settings = WubiSettings(); settings.inputScheme = scheme; settings.fuzzyPinyin = [.sSh]
            settings.userLearning = false; settings.autoCommitUnique = false
            var queries = [(String, InputScheme, Bool)]()
            let engine = InputEngine(lexicon: .shared, settings: settings) { key, source, prefix, _ in
                queries.append((key, source, prefix))
                switch (key, source, prefix) {
                case ("sen", .wubi, false): return [word("五精", 1)]
                case ("sen", .pinyin, false): return [word("拼精", 1)]
                case ("shen", .pinyin, false): return [word("模糊", 10),word("拼精", 20)]
                case ("sen", .pinyin, true): return [word("预测", 99),word("模糊", 99)]
                default: return []
                }
            }
            for c in "sen" { engine.append(c) }
            let texts = engine.candidates.map(\.text)
            if scheme == .wubi {
                XCTAssertFalse(texts.contains("模糊")); XCTAssertTrue(queries.allSatisfy { $0.1 == .wubi })
            } else {
                guard let fuzzy = texts.firstIndex(of:"模糊"), let exact = texts.firstIndex(of:"拼精"), let prefix = texts.firstIndex(of:"预测") else { return XCTFail() }
                XCTAssertLessThan(exact, fuzzy); XCTAssertLessThan(fuzzy, prefix)
                if scheme == .mixed { XCTAssertLessThan(texts.firstIndex(of: "五精") ?? Int.max, fuzzy) }
                XCTAssertEqual(Set(texts).count, texts.count)
                XCTAssertFalse(queries.contains { $0.0 == "shen" && ($0.1 == .wubi || $0.2) })
                engine.settings.prefixCandidates = false
                engine.settings.fuzzyPinyin = []
                XCTAssertFalse(engine.candidates.contains { $0.text == "模糊" })
            }
        }
    }

    func testShippedWordAcrossTwoSyllables() {
        var settings = WubiSettings(); settings.inputScheme = .pinyin; settings.userLearning = false
        settings.prefixCandidates = false
        let index = SupplementalLexicon(storeURL: { _ in nil })
        let engine = InputEngine(lexicon: .shared, settings: settings, lookup: index.candidates)
        for c in "zongguo" { engine.append(c) }
        XCTAssertTrue(engine.candidates.contains { $0.text == "中国" })
        engine.settings.fuzzyPinyin = []
        XCTAssertFalse(engine.candidates.contains { $0.text == "中国" })
    }
}
