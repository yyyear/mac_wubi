import XCTest
@testable import WubiCore

final class LookupIntegrationTests: XCTestCase {
    func testShippedPinyinAndMixedComposition() {
        var settings = WubiSettings()
        settings.inputScheme = .mixed
        settings.userLearning = false
        let index = SupplementalLexicon(storeURL: { _ in nil })
        let engine = InputEngine(lexicon: .shared, settings: settings, lookup: index.candidates)
        for (code, word) in [("nihao", "你好"), ("zhongguo", "中国"), ("chongqing", "重庆"), ("nv", "女"), ("wqiy", "你")] {
            engine.reset()
            for key in code { XCTAssertNil(engine.append(key)) }
            XCTAssertTrue(engine.candidates.contains { $0.text == word }, code)
            XCTAssertEqual(Set(engine.candidates.map(\.text)).count, engine.candidates.count)
        }
    }

    func testFuzzyLookupReadsImportedAndBundledWordsWithoutChangingWubi() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("custom.txt")
        try "zhongguo\t我的自定义词\t999\n".write(to: url, atomically: true, encoding: .utf8)
        _ = try DictionaryImporter.importFile(url, scheme: .pinyin, directory: dir)
        let index = SupplementalLexicon { dir.appendingPathComponent($0.rawValue + ".tsv") }
        var s = WubiSettings(); s.inputScheme = .pinyin; s.prefixCandidates = false; s.userLearning = false
        let e = InputEngine(lexicon: .shared, settings: s, lookup: index.candidates)
        func type(_ code: String) -> [String] { e.reset(); for c in code { e.append(c) }; return e.candidates.map(\.text) }
        for scheme in [InputScheme.pinyin, .mixed] {
            e.settings.inputScheme = scheme
            let found = type("zongguo")
            XCTAssertTrue(found.contains("中国")); XCTAssertTrue(found.contains("我的自定义词"))
        }
        e.settings.fuzzyPinyin = []; XCTAssertFalse(type("zongguo").contains("我的自定义词"))
        e.settings.inputScheme = .wubi; e.settings.fuzzyPinyin = FuzzyPair.defaults
        XCTAssertFalse(type("zong").contains("我的自定义词"))
    }

    func testUpgradingSettingsAndRoundTripAfterCustomising() throws {
        let decoder = JSONDecoder()
        var s = try decoder.decode(WubiSettings.self, from: Data(#"{"pageSize":7,"inputScheme":"mixed"}"#.utf8))
        XCTAssertEqual(s.fuzzyPinyin, FuzzyPair.defaults)
        XCTAssertEqual(s.pageSize, 7); XCTAssertEqual(s.inputScheme, .mixed)
        s.fuzzyPinyin = []
        let decoded = try decoder.decode(WubiSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s); XCTAssertTrue(decoded.fuzzyPinyin.isEmpty)
    }

    func testLegacySchemeShortcutsAreIgnoredWithoutResettingPreferences() throws {
        let data = Data("""
        {"inputScheme":"pinyin","fuzzyPinyin":["n-l"],"pageSize":8,"shiftTogglesEnglish":false,
         "schemeShortcuts":{"pinyin":{"keyCode":35,"modifiers":6}}}
        """.utf8)
        var settings = try JSONDecoder().decode(WubiSettings.self, from: data)
        XCTAssertEqual(settings.inputScheme, .pinyin)
        XCTAssertEqual(settings.fuzzyPinyin, [.nL])
        XCTAssertEqual(settings.pageSize, 8)
        XCTAssertFalse(settings.shiftTogglesEnglish)

        settings.inputScheme = .mixed
        let updated = try JSONEncoder().encode(settings)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: updated) as? [String: Any])
        XCTAssertNil(json["schemeShortcuts"])
        XCTAssertEqual(try JSONDecoder().decode(WubiSettings.self, from: updated), settings)
    }

    func testImportedFileToExactAndPrefixCandidates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let index = SupplementalLexicon { dir.appendingPathComponent($0.rawValue + ".tsv") }
        func exact(_ key: String) -> [String] { index.candidates(for: key, scheme: .pinyin, prefix: false, limit: 8).map(\.text) }
        let url = dir.appendingPathComponent("demo.txt")
        XCTAssertFalse(exact("nihao").contains("测试词甲"))
        try "nihao\t测试词甲\t99\nnihaoa\t测试词乙\t88\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try DictionaryImporter.importFile(url, scheme: .pinyin, directory: dir), 2)
        index.invalidate()
        XCTAssertEqual(exact("nihao").first, "测试词甲")
        XCTAssertTrue(exact("nihao").contains("你好")); XCTAssertFalse(exact("nihao").contains("测试词乙"))
        let longer = index.candidates(for: "nihao", scheme: .pinyin, prefix: true, limit: 8).map(\.text)
        XCTAssertEqual(longer.first, "测试词乙"); XCTAssertFalse(longer.contains("测试词甲"))
        XCTAssertTrue(index.candidates(for: "nihao", scheme: .wubi, prefix: false, limit: 8).isEmpty)
    }
}
