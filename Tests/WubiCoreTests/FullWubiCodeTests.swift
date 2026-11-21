import XCTest
@testable import WubiCore

final class FullWubiCodeTests: XCTestCase {
    func testShortCodesAndPrefixCandidatesShowTheFullSpelling() throws {
        let dictionary = WubiDictionary.shared
        XCTAssertEqual(dictionary.candidates(for: "wq").first?.fullWubiCode, "wqiy")
        XCTAssertEqual(dictionary.candidates(for: "b").first?.fullWubiCode, "bnh") // a three-key full spelling
        XCTAssertEqual(BundledWubiCodes.code(for: "亻"), "wth") // not the zzpp radical group

        var settings = WubiSettings()
        settings.userLearning = false
        let engine = InputEngine(lexicon: .shared, settings: settings) { _, _, _, _ in [] }
        engine.append("w")
        let completion = try XCTUnwrap(engine.candidates.first { $0.text == "你" })
        XCTAssertEqual(completion.fullWubiCode, "wqiy")
    }

    func testPinyinCandidateUsesWubiWordCodeNotTheInputSpelling() throws {
        var settings = WubiSettings()
        settings.inputScheme = .pinyin
        settings.userLearning = false
        settings.prefixCandidates = false
        let index = SupplementalLexicon(storeURL: { _ in nil })
        let engine = InputEngine(lexicon: .shared, settings: settings, lookup: index.candidates)
        for key in "nihao" { engine.append(key) }
        let candidate = try XCTUnwrap(engine.candidates.first { $0.text == "你好" })
        XCTAssertEqual(candidate.fullWubiCode, "wqvb")
        XCTAssertNil(BundledWubiCodes.code(for: "不存在的测试词123"))
    }

    func testImportedWubiCodesRefreshWithoutConsultingPinyin() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let wubi = dir.appendingPathComponent("wubi.tsv"), pinyin = dir.appendingPathComponent("pinyin.tsv")
        let index = SupplementalLexicon { scheme in scheme == .wubi ? wubi : pinyin }
        try "abcd\t只有拼音\t100\n".write(to: pinyin, atomically: true, encoding: .utf8)
        XCTAssertNil(index.importedFullCode(for: "只有拼音"))
        try "ab\t自定义测试词\t99\nabcd\t自定义测试词\t10\n".write(to: wubi, atomically: true, encoding: .utf8)
        index.invalidate()
        XCTAssertEqual(index.importedFullCode(for: "自定义测试词"), "abcd")
        try "aaaa\t替换词\t10\n".write(to: wubi, atomically: true, encoding: .utf8)
        index.invalidate()
        XCTAssertNil(index.importedFullCode(for: "自定义测试词"))
        XCTAssertEqual(index.importedFullCode(for: "替换词"), "aaaa")
    }

    func testFullCodeSettingMigratesIndependentlyOfExistingProgressHint() throws {
        var settings = try JSONDecoder().decode(WubiSettings.self, from: Data(#"{"showCodeHint":false}"#.utf8))
        XCTAssertTrue(settings.showFullWubiCode)
        XCTAssertFalse(settings.showCodeHint)
        settings.showFullWubiCode = false
        settings.showCodeHint = true
        let saved = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(WubiSettings.self, from: saved), settings)
    }
}
