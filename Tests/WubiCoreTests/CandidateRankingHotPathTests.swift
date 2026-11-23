import XCTest
@testable import WubiCore

final class CandidateRankingHotPathTests: XCTestCase {
    func testWarmFirstLetterPrefixesMatchUncachedDictionaryOrder() {
        let dictionary = WubiDictionary.shared
        let letters = "abcdefghijklmnopqrstuvwxyz"
        var settings = WubiSettings(); settings.userLearning = false
        let engine = InputEngine(lexicon: .shared, settings: settings, lookup: { _, _, _, _ in [] })
        for letter in letters {
            let code = String(letter)
            let exact = dictionary.candidates(for: code, limit: settings.effectiveCandidateLimit)
            let prefixes = letters.flatMap { dictionary.candidates(for: code + String($0), limit: 2) }
                .sorted { $0.weight > $1.weight }.prefix(24)
            var seen = Set<String>()
            let expected = (exact + prefixes).filter { seen.insert($0.text).inserted }
            for _ in 0..<2 {
                engine.reset(); engine.append(letter)
                XCTAssertEqual(engine.candidates, expected, code)
            }
        }
    }

    func testWarmPrefixStillRereadsImportsAndLearningWithoutReorderingTies() throws {
        let lexicon = UserLexicon(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                  schedule: { _, _, _ in })
        var custom = [WubiCandidate]()
        let engine = InputEngine(lexicon: lexicon, settings: WubiSettings()) { _, _, prefix, _ in prefix ? custom : [] }
        engine.append("w")
        let original = engine.candidates
        let exact = Set(WubiDictionary.shared.candidates(for: "w").map(\.text))
        let prefix = original.filter { !exact.contains($0.text) }
        let selected = try XCTUnwrap(prefix.last)
        XCTAssertGreaterThan(prefix.count, 1)
        custom = [WubiCandidate(text: "自定义测试", weight: .max, flags: 1)]
        lexicon.recordCommit(code: "w", text: selected.text)
        engine.reset(); engine.append("W")
        XCTAssertEqual(engine.candidates, original.filter { exact.contains($0.text) } + [selected] + custom + prefix.dropLast())
    }
}
