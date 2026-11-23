import XCTest
@testable import WubiCore

final class UserLexiconPersistenceTests: XCTestCase {
    private func temporaryURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("userfreq.tsv")
    }

    func testCommitsShareFirstDeadlineAndIdleFlushDoesNotWrite() throws {
        let url = try temporaryURL()
        var deadlines: [() -> Void] = []
        let lexicon = UserLexicon(fileURL: url) { queue, delay, item in
            XCTAssertEqual(delay, .seconds(30))
            deadlines.append { queue.sync { item.perform() } }
        }
        lexicon.recordCommit(code: "", text: "甲")
        lexicon.recordCommit(code: "x", text: "")
        lexicon.flush(wait: true)
        XCTAssertTrue(deadlines.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        for _ in 0..<50 { lexicon.recordCommit(code: "x", text: "甲") }
        XCTAssertEqual(lexicon.total(for: "x"), 50)
        XCTAssertEqual(deadlines.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try XCTUnwrap(deadlines.first)()
        XCTAssertEqual(try String(contentsOf: url), "x\t甲\t50\n")
        XCTAssertEqual(deadlines.count, 1, "Idle batches must not re-arm the timer")

        // If a clean flush rewrites the snapshot it will recreate the file.
        try FileManager.default.removeItem(at: url)
        lexicon.flush(wait: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        lexicon.recordCommit(code: "x", text: "甲")
        XCTAssertEqual(deadlines.count, 2)
        try XCTUnwrap(deadlines.last)()
        XCTAssertEqual(try String(contentsOf: url), "x\t甲\t51\n")
    }

    func testExitFlushPreservesLegacyTSVAndReset() throws {
        let url = try temporaryURL()
        try "x\t甲\t2\nx\t乙\t1\n".write(to: url, atomically: true, encoding: .utf8)
        let lexicon = UserLexicon(fileURL: url)
        lexicon.recordCommit(code: "x", text: "乙")
        XCTAssertEqual(lexicon.entryCount, 2)
        XCTAssertEqual(lexicon.probability(code: "x", text: "乙"), 0.5)
        lexicon.flush()
        lexicon.flush(wait: true)
        let reloaded = UserLexicon(fileURL: url)
        XCTAssertEqual(reloaded.total(for: "x"), 4)
        XCTAssertEqual(reloaded.boost(for: "x", text: "甲"), 2)
        XCTAssertEqual(reloaded.boost(for: "x", text: "乙"), 2)
        lexicon.reset()
        XCTAssertEqual(lexicon.total(for: "x"), 0)
        lexicon.flush(wait: true)
        XCTAssertEqual(try Data(contentsOf: url), Data())
    }

    func testFailedWriteCanRetryWithoutAnotherCommit() throws {
        let url = try temporaryURL()
        // An ordinary file at the parent path initially prevents the write.
        try Data().write(to: url)
        let destination = url.appendingPathComponent("nested.tsv")
        let lexicon = UserLexicon(fileURL: destination)
        lexicon.recordCommit(code: "x", text: "甲")
        lexicon.flush(wait: true)
        try FileManager.default.removeItem(at: url)
        lexicon.flush(wait: true)
        XCTAssertEqual(try String(contentsOf: destination), "x\t甲\t1\n")
    }
}
