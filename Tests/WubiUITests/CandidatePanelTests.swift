import AppKit
import XCTest
@testable import WubiCore
@testable import WubiUI

final class CandidatePanelTests: XCTestCase {
    @MainActor func testNumberLabelsMatchEachPageAndCodeHintsAreOptional() throws {
        _ = NSApplication.shared
        var settings = WubiSettings()
        settings.pageSize = 10
        settings.userLearning = false
        let engine = InputEngine(lexicon: .shared, settings: settings, lookup: { _, _, _, _ in [] })
        engine.append("w"); engine.append("q")
        let panel = CandidatePanel()
        func render() -> [[String]] {
            panel.update(engine: engine, hint: "")
            let cells = views(in: panel.contentView!).compactMap { $0 as? CandidateCell }
            return cells.map { views(in: $0).compactMap { ($0 as? NSTextField)?.stringValue } }
        }
        let first = render()
        XCTAssertTrue(first.contains { $0.contains("你") && $0.contains("wqiy") })
        engine.settings.showFullWubiCode = false
        repeat {
            let cells = render()
            XCTAssertEqual(cells.count, engine.pageCandidates.count)
            for (offset, labels) in cells.enumerated() {
                XCTAssertEqual(labels.count, 2, "Only the word and the number should remain")
                XCTAssertTrue(labels.contains(String(offset + 1)))
            }
        } while engine.nextPage()
        XCTAssertGreaterThan(engine.page, 0)
    }

    @MainActor private func views(in view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + views(in: $0) }
    }
}
