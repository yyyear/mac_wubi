import Foundation

/// The generated reverse table is sorted by the UTF-8 bytes of its text column.
/// Binary search directly on mapped rows: no startup decoding or per-word cache.
enum BundledWubiCodes {
    private static let index: Data? = {
        guard let url = Bundle.module.url(forResource: "wubi86-reverse", withExtension: "tsv") else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }()

    static func code(for text: String) -> String? {
        guard let index, !text.isEmpty else { return nil }
        return index.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> String? in
            let key = text.utf8
            var lo = 0, hi = bytes.count
            while lo < hi {
                var start = (lo + hi) / 2
                while start > lo, bytes[start - 1] != 10 { start -= 1 }
                var tab = start
                while tab < hi, bytes[tab] != 9 { tab += 1 }
                guard tab < hi else { return nil }
                let word = bytes[start..<tab]
                var end = tab + 1
                while end < hi, bytes[end] != 10 { end += 1 }
                if word.elementsEqual(key) { return String(decoding: bytes[tab+1..<end], as: UTF8.self) }
                if word.lexicographicallyPrecedes(key) { lo = end + 1 } else { hi = start }
            }
            return nil
        }
    }
}
