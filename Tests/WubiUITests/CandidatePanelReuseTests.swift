import AppKit
import XCTest
@testable import WubiCore
@testable import WubiUI

final class CandidatePanelReuseTests: XCTestCase {
    @MainActor func testSlotsSurviveCandidateHintAndPageChanges() throws {
        _ = NSApplication.shared
        var settings = WubiSettings()
        settings.inputScheme = .pinyin
        settings.pageSize = 2
        settings.prefixCandidates = false
        settings.userLearning = false
        settings.showFullWubiCode = false
        let engine = InputEngine(lexicon: .shared, settings: settings) { code, _, _, _ in
            let words = code == "a" ? ["甲", "乙", "较长的第三项"] : ["词语", "另一项"]
            return words.map { WubiCandidate(text: $0, weight: 1, flags: 0) }
        }
        let panel = CandidatePanel()
        let content = try XCTUnwrap(panel.contentView)
        func cells() -> [CandidateCell] {
            content.subviews.compactMap { $0 as? NSStackView }.flatMap { $0.arrangedSubviews }.compactMap { $0 as? CandidateCell }
        }
        func checkRender(hint: String) {
            panel.update(engine: engine, hint: hint)
            let freshPanel = CandidatePanel()
            freshPanel.update(engine: engine, hint: hint)
            XCTAssertEqual(panel.frame.size, freshPanel.frame.size)
            func labels(in view: NSView) -> [String] {
                if let field = view as? NSTextField { return [field.stringValue] }
                return view.subviews.flatMap { labels(in: $0) }
            }
            XCTAssertEqual(labels(in: content), labels(in: freshPanel.contentView!))
        }
        engine.append("a")
        checkRender(hint: "1/2")
        let firstPage = cells()
        XCTAssertEqual(firstPage.count, 2)
        checkRender(hint: "1/2")
        XCTAssertEqual(firstPage, cells())
        checkRender(hint: "更长的提示文字")
        XCTAssertEqual(firstPage, cells())
        XCTAssertTrue(engine.nextPage())
        checkRender(hint: "")
        XCTAssertEqual(cells(), Array(firstPage.prefix(1)))
        var selected: Int?
        panel.onSelect = { selected = $0 }
        cells().first?.onSelect?()
        XCTAssertEqual(selected, 0, "Second page still starts at offset zero")
        engine.append("b")
        checkRender(hint: "")
        let newPage = cells()
        XCTAssertEqual(newPage.count, 2)
        XCTAssertIdentical(newPage.first, firstPage.first)
        newPage.last?.onSelect?()
        XCTAssertEqual(selected, 1)
        engine.reset()
        checkRender(hint: "")
        XCTAssertTrue(cells().isEmpty)
    }
}
