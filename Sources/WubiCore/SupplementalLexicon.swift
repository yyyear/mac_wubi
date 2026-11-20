import Foundation

/// Sorted UTF-8 rows: code<TAB>text<TAB>weight. Only decode candidates that
/// can enter the result; the shipped dictionary stays memory-mapped.
private struct WordTable {
    let data: Data
    let starts: [Int]

    init(_ data: Data) {
        self.data = data
        starts = data.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
            guard !b.isEmpty else { return [] }
            var offsets = [0]
            for i in 0..<b.count where b[i] == 10 && i + 1 < b.count { offsets.append(i + 1) }
            return offsets
        }
    }

    func candidates(_ code: String, prefix: Bool, limit: Int) -> [WubiCandidate] {
        guard !code.isEmpty, limit > 0 else { return [] }
        let key = Array(code.utf8)
        return data.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
            // Compare just the code column. A tab sorts before any letter.
            func lowerBound(_ query: [UInt8]) -> Int {
                var lo = 0, hi = starts.count
                while lo < hi {
                    let mid = (lo + hi) / 2, pos = starts[mid]
                    var j = 0
                    while j < query.count && pos+j < b.count && b[pos+j] == query[j] { j += 1 }
                    if j < query.count && (pos+j >= b.count || b[pos+j] < query[j]) { lo = mid+1 } else { hi = mid }
                }
                return lo
            }
            // Codes contain only a-z: bytes 10 and 123 bound exact/prefix runs.
            let exactEnd = lowerBound(key + [10])
            let lo = prefix ? exactEnd : lowerBound(key)
            let hi = prefix ? lowerBound(key + [123]) : exactEnd
            var best = [WubiCandidate]()
            var seen = Set<String>()
            for row in lo..<hi {
                let pos = starts[row], end = row+1 < starts.count ? starts[row+1]-1 : (b.last == 10 ? b.count-1 : b.count)
                var sep = end
                while sep > pos && b[sep-1] != 9 { sep -= 1 }
                guard sep > pos, sep < end else { continue }
                var w = 0
                for i in sep..<end { let n = b[i]; guard n >= 48 && n <= 57 else { break }; w = min(65535, w*10 + Int(n-48)) }
                if best.count == limit && w <= Int(best[limit-1].weight) { continue }
                var field = pos + key.count
                while field < sep-1 && b[field] != 9 { field += 1 }
                guard field+1 < sep-1 else { continue }
                let text = String(decoding: b[field+1..<sep-1], as: UTF8.self)
                if seen.contains(text) {
                    guard let i = best.firstIndex(where: { $0.text == text }), w > Int(best[i].weight) else { continue }
                    best.remove(at: i)
                }
                seen.insert(text)
                let entry = WubiCandidate(text: text, weight: UInt16(w), flags: text.count > 1 ? 1 : 0)
                if let i = best.firstIndex(where: { $0.weight < entry.weight }) { best.insert(entry, at: i) } else { best.append(entry) }
                if best.count > limit { seen.remove(best.removeLast().text) }
            }
            return best
        }
    }
}

public enum LexiconEvents {
    public static let changed = Notification.Name("com.sifang.wubi.dictionaryChanged")
}

final class SupplementalLexicon {
    static let shared = SupplementalLexicon()
    // Construct only on the first pinyin lookup; pure Wubi never touches this resource.
    private static let pinyin: WordTable = {
        guard let url = Bundle.module.url(forResource: "pinyin", withExtension: "tsv"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return WordTable(Data()) }
        return WordTable(data)
    }()
    private let lock = NSLock()
    private var imported = [InputScheme: WordTable]()

    private let storeURL: (InputScheme) -> URL?
    init(storeURL: @escaping (InputScheme) -> URL? = DictionaryImporter.indexedStoreURL) {
        self.storeURL = storeURL
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(invalidate), name: LexiconEvents.changed, object: nil, suspensionBehavior: .deliverImmediately)
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    @objc func invalidate() { lock.lock(); imported.removeAll(); lock.unlock() }

    private func userTable(_ scheme: InputScheme) -> WordTable {
        lock.lock(); defer { lock.unlock() }
        if let table = imported[scheme] { return table }
        let data = storeURL(scheme).flatMap { url -> Data? in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 32 * 1024 * 1024 else { return nil }
            return try? Data(contentsOf: url, options: .mappedIfSafe)
        }
        let table = WordTable(data ?? Data()); imported[scheme] = table
        return table
    }

    func candidates(for code: String, scheme: InputScheme, prefix: Bool, limit: Int) -> [WubiCandidate] {
        guard scheme != .mixed else { return [] }
        var result = userTable(scheme).candidates(code, prefix: prefix, limit: limit)
        if scheme == .pinyin && result.count < limit {
            var seen = Set(result.map(\.text))
            for c in Self.pinyin.candidates(code, prefix: prefix, limit: limit) where seen.insert(c.text).inserted {
                result.append(c); if result.count == limit { break }
            }
        }
        return result
    }
}
