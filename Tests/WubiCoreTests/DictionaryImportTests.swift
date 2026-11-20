import XCTest
@testable import WubiCore

final class DictionaryImportTests: XCTestCase {
    private var root: URL!
    private var directory: URL { root.appendingPathComponent("store") }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func file(_ name: String, _ data: Data) throws -> URL {
        let url = root.appendingPathComponent(name); try data.write(to: url); return url
    }
    @discardableResult private func add(_ name: String, _ string: String, _ scheme: InputScheme) throws -> Int {
        try DictionaryImporter.importFile(file(name, Data(string.utf8)), scheme: scheme, directory: directory)
    }
    private func words(_ scheme: InputScheme) -> [String] {
        DictionaryImporter.entries(scheme: scheme, directory: directory).map { "\($0.code) \($0.text) \($0.weight)" }
    }

    func testRimeAndTextMergeReloadAndIsolation() throws {
        let yaml = "\u{FEFF}# Rime\r\n---\nname: demo\nsort: by_weight\n...\r\n绿茶\tLÜ CHA\t23\r\n女儿\tnü'er\t81%\n绿茶\tlv cha\t4\n"
        XCTAssertEqual(try add("demo.dict.yaml", yaml, .pinyin), 2)
        XCTAssertEqual(try add("demo.dict.yaml", yaml, .pinyin), 0)
        XCTAssertEqual(try add("codes.tsv", "lvcha\t绿茶\t40\n", .pinyin), 0)
        XCTAssertEqual(try add("words.txt", "绿茶 AA 9\nBBBB 茶\n", .wubi), 2)
        XCTAssertEqual(words(.pinyin), ["lvcha 绿茶 40", "nver 女儿 81"])
        XCTAssertEqual(words(.wubi), ["aa 绿茶 9", "bbbb 茶 1"])
        XCTAssertThrowsError(try add("wrong.txt", "a 甲", .mixed)); XCTAssertTrue(words(.mixed).isEmpty)
    }

    func testQinggPinyinHomophonesAndAtomicRejection() throws {
        let table = "shi'ci 测甲 测乙 测丙 测甲\nxi 测丁\n"
        XCTAssertEqual(try add("py_table.txt", table, .pinyin), 4)
        XCTAssertEqual(try add("py_table.txt", table, .pinyin), 0)
        let rows = DictionaryImporter.entries(scheme: .pinyin, directory: directory)
        XCTAssertEqual(rows.filter { $0.code == "shici" }.sorted { $0.weight > $1.weight }.map { $0.text }, ["测甲", "测乙", "测丙"])
        let initial = words(.pinyin)
        XCTAssertThrowsError(try add("py_table.txt", "aa 新甲 新乙\nbad1 无效", .pinyin))
        XCTAssertThrowsError(try add("py_table.txt", "ni\t误用制表符", .pinyin))
        XCTAssertThrowsError(try add("py_table.txt", table, .wubi))
        XCTAssertThrowsError(try add("other.txt", table, .pinyin))
        XCTAssertEqual(words(.pinyin), initial); XCTAssertTrue(words(.wubi).isEmpty)
    }

    func testMalformedOrOversizedImportLeavesSnapshotIntact() throws {
        try add("valid.txt", "abcd 旧 8", .wubi)
        for (name, content) in [("bad.tsv", "aa\t新\nabcdef\t长码"), ("bad.tsv", "a\t字\tNaN"),
                                ("bad.dict.yaml", "---\nname: missingEnd\n"), ("bad.txt", "a\t坏\u{0}字"),
                                ("empty.tsv", "# empty\n"), ("big.txt", String(repeating: "a", count: 5000))] {
            XCTAssertThrowsError(try add(name, content, .wubi), name)
        }
        let invalid = try file("utf.txt", Data([0xfe, 0xff, 9, 100]))
        XCTAssertThrowsError(try DictionaryImporter.importFile(invalid, scheme: .wubi, directory: directory))
        let large = try file("large.txt", Data()); let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: 16 * 1024 * 1024 + 1); try handle.close()
        XCTAssertThrowsError(try DictionaryImporter.importFile(large, scheme: .wubi, directory: directory))
        XCTAssertEqual(words(.wubi), ["abcd 旧 8"])
        // A damaged previous snapshot is never silently replaced with a new import.
        let store = directory.appendingPathComponent("wubi.tsv"), broken = Data([0xFF])
        try broken.write(to: store); XCTAssertThrowsError(try add("valid.txt", "abc 新 1", .wubi))
        XCTAssertEqual(try Data(contentsOf: store), broken)
    }

    func testConcurrentImportsPreserveBothSnapshots() throws {
        let left = try file("left.txt", Data("aa 左 12".utf8)), right = try file("right.txt", Data("ab 右 15".utf8))
        let urls = [left, right], dir = directory
        DispatchQueue.concurrentPerform(iterations: urls.count) { index in
            do { _ = try DictionaryImporter.importFile(urls[index], scheme: .wubi, directory: dir) }
            catch { XCTFail("Concurrent import failed: \(error)") }
        }
        XCTAssertEqual(words(.wubi), ["aa 左 12", "ab 右 15"])
    }

    private func scel(_ type: UInt8) -> Data {
        func le(_ n: Int) -> [UInt8] { [UInt8(n & 255), UInt8(n >> 8)] }
        func utf16(_ s: String) -> [UInt8] { s.utf16.flatMap { le(Int($0)) } }
        var bytes = [UInt8](repeating: 0, count: 0x1544)
        bytes.replaceSubrange(0..<8, with: [0x40,0x15,0,0,type,0x43,0x53,1]); bytes[0x1540] = 2; bytes[0x120] = 1
        for (i,s) in ["ni","hao"].enumerated() {
            let py = utf16(s); bytes += le(i) + le(py.count) + py
        }
        bytes += Array(repeating: 0, count: (type == 0x44 ? 0x2628 : 0x26c4) - bytes.count)
        bytes += le(2) + le(4) + le(0) + le(1)
        for (word,weight) in [("你好",1234), ("拟好",7)] {
            let data = utf16(word); bytes += le(data.count) + data + le(10) + le(weight) + Array(repeating: 0, count:8)
        }
        return Data(bytes)
    }

    func testSCELVariantsAndCorruption() throws {
        for type: UInt8 in [0x44,0x45] {
            let data = scel(type), url = try file("ok.scel", data + Data(repeating: 0, count: 8))
            XCTAssertThrowsError(try DictionaryImporter.importFile(url, scheme: .wubi, directory: directory))
            XCTAssertEqual(try DictionaryImporter.importFile(url, scheme: .pinyin, directory: directory), type == 0x44 ? 2 : 0)
            let base = type == 0x44 ? 0x2628 : 0x26c4
            var unknown = data; unknown[base + 4] = 255
            var odd = data; odd[base + 2] = 3
            for bad in [Data(data.prefix(64)), Data(data.dropLast()), data + Data([0,0,1]), unknown, odd] {
                let damaged = try file("bad.scel", bad)
                XCTAssertThrowsError(try DictionaryImporter.importFile(damaged, scheme: .pinyin, directory: directory))
            }
        }
        XCTAssertEqual(words(.pinyin), ["nihao 你好 1234", "nihao 拟好 7"]); XCTAssertTrue(words(.wubi).isEmpty)
    }
}
