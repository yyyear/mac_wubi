import Foundation
import Darwin

/// Imports explicit word/code pairs only. The bundled dictionaries are never modified.
public enum DictionaryImporter {
    public enum ImportError: LocalizedError {
        case target, format, size, invalid(String)
        public var errorDescription: String? {
            switch self {
            case .target: return "请选择五笔或拼音词库；搜狗 SCEL 和清歌拼音表仅支持拼音。"
            case .format: return "仅支持 Rime .dict.yaml、搜狗拼音 .scel、UTF-8 .tsv/.txt。"
            case .size: return "词库超过大小、行长或条数限制。"
            case .invalid(let reason): return "词库格式错误：" + reason
            }
        }
    }

    /// Number of new unique (normalized code, text) pairs. Reimports keep the higher weight.
    public static func importFile(_ url: URL, scheme: InputScheme) throws -> Int {
        try importFile(url, scheme: scheme, directory: directory)
    }

    internal static func entries(scheme: InputScheme) -> [(code: String, text: String, weight: UInt16)] {
        entries(scheme: scheme, directory: directory)
    }

    /// Sorted UTF-8 code<TAB>text<TAB>weight snapshot. Remap after each successful import.
    internal static func indexedStoreURL(scheme: InputScheme) -> URL? {
        try? store(scheme, in: directory)
    }

    private struct Key: Hashable { let code: String; let text: String }
    private typealias Table = [Key: UInt16]
    private static var directory: URL { WubiSettings.supportDirectory.appendingPathComponent("ImportedDictionaries", isDirectory: true) }
    private static let maxFile = 16 * 1024 * 1024, maxStore = 32 * 1024 * 1024, maxEntries = 300_000

    private static func store(_ scheme: InputScheme, in directory: URL) throws -> URL {
        switch scheme {
        case .wubi: return directory.appendingPathComponent("wubi.tsv")
        case .pinyin: return directory.appendingPathComponent("pinyin.tsv")
        case .mixed: throw ImportError.target
        }
    }

    internal static func importFile(_ url: URL, scheme: InputScheme, directory: URL) throws -> Int {
        let out = try store(scheme, in: directory)
        let ext = url.pathExtension.lowercased()
        guard ["yaml", "scel", "tsv", "txt"].contains(ext) else { throw ImportError.format }
        // This particular Qingg file uses whitespace-separated homophone groups,
        // not the single-entry rows accepted by a generic TXT import.
        let qinggPinyin = url.lastPathComponent == "py_table.txt"
        if (ext == "scel" || qinggPinyin) && scheme != .pinyin { throw ImportError.target }
        let bytes = try readFile(url, limit: maxFile)
        var incoming = Table()
        if ext == "scel" { try parseSCEL(bytes, into: &incoming) }
        else { try parseText(bytes, scheme, rime: ext == "yaml", qinggPinyin: qinggPinyin, into: &incoming) }
        guard !incoming.isEmpty else { throw ImportError.invalid("没有显式词条") }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Serialize the read/merge/replace, including across two settings processes.
        let lock = open(out.appendingPathExtension("lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw posixError() }
        defer { close(lock) }
        while flock(lock, LOCK_EX) != 0 { if errno != EINTR { throw posixError() } }
        var merged = try load(out, scheme)
        let oldCount = merged.count
        var changed = false
        for (key, weight) in incoming where merged[key].map({ $0 < weight }) ?? true {
            merged[key] = weight
            changed = true
        }
        guard merged.count <= maxEntries else { throw ImportError.size }
        if changed {
            var data = Data()
            for (key, weight) in merged.sorted(by: { ($0.key.code, $0.key.text) < ($1.key.code, $1.key.text) }) {
                let line = "\(key.code)\t\(key.text)\t\(weight)\n"
                guard line.utf8.count <= maxStore - data.count else { throw ImportError.size }
                data.append(contentsOf: line.utf8)
            }
            try data.write(to: out, options: .atomic)
        }
        return merged.count - oldCount
    }

    internal static func entries(scheme: InputScheme, directory: URL) -> [(code: String, text: String, weight: UInt16)] {
        // Atomic replacement gives readers either snapshot without locking or stale caches.
        guard let url = try? store(scheme, in: directory), let rows = try? load(url, scheme) else { return [] }
        return rows.map { ($0.key.code, $0.key.text, $0.value) }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
    }

    private static func load(_ url: URL, _ scheme: InputScheme) throws -> Table {
        let bytes: Data
        do { bytes = try readFile(url, limit: maxStore) }
        catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) { return [:] }
        var rows = Table()
        try parseText(bytes, scheme, rime: false, stored: true, into: &rows)
        guard !rows.isEmpty else { throw ImportError.invalid("已保存的词库为空") }
        return rows
    }

    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    private static func readFile(_ url: URL, limit: Int) throws -> Data {
        guard url.isFileURL else { throw ImportError.format }
        // Check the opened descriptor rather than a path that could change; never block on a FIFO.
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw posixError() }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw posixError() }
        guard info.st_mode & S_IFMT == S_IFREG else { throw ImportError.invalid("不是普通文件") }
        guard info.st_size <= limit else { throw ImportError.size }
        var result = Data()
        while let chunk = try file.read(upToCount: min(65536, limit - result.count + 1)), !chunk.isEmpty {
            guard chunk.count <= limit - result.count else { throw ImportError.size }
            result.append(chunk)
        }
        return result
    }

    private static func code(_ raw: String, _ scheme: InputScheme) -> String? {
        guard raw.utf8.count <= 256 else { return nil }
        var s = raw.lowercased()
        if scheme == .pinyin {
            s = s.replacingOccurrences(of: "ü", with: "v").replacingOccurrences(of: "u:", with: "v")
            s.removeAll { $0 == "'" || $0 == "’" || $0 == " " }
        }
        guard (1...(scheme == .wubi ? 4 : 128)).contains(s.utf8.count),
              s.utf8.allSatisfy({ (97...122).contains($0) }) else { return nil }
        return s
    }

    private static func put(_ c: String, _ word: String, _ weight: UInt16, into rows: inout Table) throws {
        guard !word.isEmpty, word.utf8.count <= 512,
              !word.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) })
        else { throw ImportError.invalid("无效词条") }
        let key = Key(code: c, text: word)
        rows[key] = max(rows[key] ?? 0, weight)
        guard rows.count <= maxEntries else { throw ImportError.size }
    }

    private static func parseText(_ bytes: Data, _ scheme: InputScheme, rime: Bool,
                                  stored: Bool = false, qinggPinyin: Bool = false, into rows: inout Table) throws {
        var start = bytes.startIndex, lineNumber = 0, inHeader = rime, sawStart = false
        while start < bytes.endIndex {
            let end = bytes[start...].firstIndex(of: 10) ?? bytes.endIndex
            guard end - start <= 4096 else { throw ImportError.size }
            guard var line = String(bytes: bytes[start..<end], encoding: .utf8), !line.utf8.contains(0) else {
                throw ImportError.invalid("非 UTF-8 文本")
            }
            start = end < bytes.endIndex ? end + 1 : end
            lineNumber += 1
            guard lineNumber <= maxEntries * 2 else { throw ImportError.size }
            if lineNumber == 1 && line.first == "\u{feff}" { line.removeFirst() }
            if line.last == "\r" { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if inHeader {
                if !sawStart { guard trimmed == "---" else { throw ImportError.invalid("缺少 Rime 文档头 ---") }; sawStart = true }
                else if trimmed == "..." { inHeader = false }
                continue
            }
            if qinggPinyin {
                let parts = trimmed.split(separator: " ")
                guard !line.contains("\t"), parts.count >= 2,
                      let rawCode = parts.first, let c = code(String(rawCode), .pinyin) else {
                    throw ImportError.invalid("第 \(lineNumber) 行需要拼音编码和空格分隔的候选词")
                }
                // There are no frequencies; retain the supplied order within this code.
                for (rank, word) in parts.dropFirst().enumerated() {
                    try put(c, String(word), UInt16.max - UInt16(rank), into: &rows)
                }
                continue
            }
            let fields: [String]
            if line.contains("\t") { fields = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) } }
            else if !rime && !stored { fields = trimmed.split(whereSeparator: { $0 == " " }).map(String.init) }
            else { fields = [] }
            let invalid = ImportError.invalid("第 \(lineNumber) 行需要词条、编码及可选权重")
            guard (2...3).contains(fields.count), !stored || fields.count == 3 else { throw invalid }
            let c: String, text: String
            if !rime, let first = code(fields[0], scheme) { c = first; text = fields[1] }
            else if !stored, let second = code(fields[1], scheme) { c = second; text = fields[0] }
            else { throw invalid }
            var weight: UInt16 = 1
            if fields.count == 3, !fields[2].isEmpty {
                var number = fields[2]
                if rime && number.last == "%" { number.removeLast() }
                guard let n = Double(number), n.isFinite, n >= 0 else { throw invalid }
                weight = UInt16(min(n, Double(UInt16.max)))
            } else if stored { throw invalid }
            try put(c, text, weight, into: &rows)
        }
        if inHeader { throw ImportError.invalid("缺少 Rime 文档头结束标记 ...") }
    }

    /// Classic Sogou 0x44/0x45 SCEL variants. All offsets and lengths are byte based.
    private static func parseSCEL(_ bytes: Data, into rows: inout Table) throws {
        let bad = ImportError.invalid("SCEL 数据损坏或版本不支持")
        guard bytes.count >= 8, bytes.prefix(4).elementsEqual([0x40,0x15,0,0]),
              [0x44,0x45].contains(bytes[4]), bytes[5] == 0x43, bytes[6] == 0x53, bytes[7] == 1 else { throw bad }
        let words = bytes[4] == 0x44 ? 0x2628 : 0x26c4
        guard bytes.count > words else { throw bad }
        var i = 0x1544, limit = words
        func u16() throws -> Int {
            guard i <= limit - 2 else { throw bad }; defer { i += 2 }
            return Int(bytes[i]) | Int(bytes[i + 1]) << 8
        }
        func utf16(_ length: Int, max: Int) throws -> String {
            guard length > 0, length.isMultiple(of: 2), length <= max, length <= limit - i else { throw bad }
            // Reject isolated surrogates instead of importing repaired replacement characters.
            let units = stride(from: i, to: i + length, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
            let s = String(decoding: units, as: UTF16.self)
            guard s.utf16.elementsEqual(units) else { throw bad }
            i += length; return s
        }
        var syllables: [Int: String] = [:]
        while i < words {
            let idx = try u16(), n = try u16()
            if idx == 0 && n == 0 { guard bytes[i..<words].allSatisfy({ $0 == 0 }) else { throw bad }; break }
            guard syllables[idx] == nil, let s = code(try utf16(n, max: 24), .pinyin) else { throw bad }
            syllables[idx] = s
        }
        // The classic header reports homophone groups (not individual words).
        // Some producers zero-fill an aligned tail. Ignore it only AFTER the
        // declared groups, never mistake a partial word for valid padding.
        let groupCount = (0..<4).reduce(0) { $0 | Int(bytes[0x120 + $1]) << (8 * $1) }
        var groups = 0
        i = words; limit = bytes.count
        while i < limit {
            if groupCount > 0 && groups == groupCount {
                guard bytes[i...].allSatisfy({ $0 == 0 }) else { throw bad }
                break
            }
            groups += 1
            let count = try u16(), n = try u16()
            guard count > 0, n > 0, n.isMultiple(of: 2), n <= 256, n <= limit - i else { throw bad }
            var c = ""
            for _ in 0..<n/2 {
                guard let s = syllables[try u16()] else { throw bad }; c += s
            }
            guard c.utf8.count <= 128 else { throw bad }
            for _ in 0..<count {
                let word = try utf16(try u16(), max: 1024), extra = try u16()
                guard extra >= 2, extra <= limit - i else { throw bad }
                let weight = UInt16(try u16()); i += extra - 2
                try put(c, word, weight, into: &rows)
            }
        }
        guard groupCount == 0 || groups == groupCount else { throw bad }
    }
}
