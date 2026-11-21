import Foundation

public struct WubiCandidate: Equatable, Sendable {
    public let text: String
    public let weight: UInt16
    public let isWord: Bool
    public let isSimpleCode: Bool

    /// Independent of the lookup spelling; only resolve for visible candidates.
    public var fullWubiCode: String? {
        BundledWubiCodes.code(for: text) ?? SupplementalLexicon.shared.importedFullCode(for: text)
    }

    init(text: String, weight: UInt16, flags: UInt8) {
        self.text = text
        self.weight = weight
        self.isWord = flags & 1 != 0
        self.isSimpleCode = flags & 2 != 0
    }
}

/// Read-only view over the compiled dictionary. The file is memory mapped and
/// never fully decoded: candidate strings become Swift Strings only when a key
/// is actually shown, so an idle input method holds roughly 3 MB of clean pages
/// and nothing else.
public final class WubiDictionary {
    enum Layout {
        static let headerSize = 20
        static let keyStride = 4
        static let indexStride = 8
        static let recordStride = 8
    }

    public enum LoadError: Error, CustomStringConvertible {
        case corrupt(String)

        public var description: String {
            switch self {
            case .corrupt(let reason): return "dictionary corrupt: " + reason
            }
        }
    }

    public let sourceURL: URL
    public let keyCount: Int
    public let entryCount: Int

    private let data: Data
    private let keysOffset: Int
    private let indexOffset: Int
    private let recordsOffset: Int
    private let blobOffset: Int
    private let blobSize: Int

    /// The dictionary that ships inside WubiCore.
    public static let shared: WubiDictionary = {
        guard let url = Bundle.module.url(forResource: "wubi86", withExtension: "bin") else {
            fatalError("wubi86.bin missing from WubiCore resources")
        }
        do {
            return try WubiDictionary(url: url)
        } catch {
            fatalError("failed to load wubi86.bin: \(error)")
        }
    }()

    public init(url: URL) throws {
        let mapped = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard mapped.count > Layout.headerSize else { throw LoadError.corrupt("file too small") }
        guard mapped.prefix(4) == Data("WUB1".utf8) else { throw LoadError.corrupt("bad magic") }
        let entries = Int(mapped.uint32(at: 8))
        let keys = Int(mapped.uint32(at: 12))
        let blob = Int(mapped.uint32(at: 16))
        let keysOffset = Layout.headerSize
        let indexOffset = keysOffset + keys * Layout.keyStride
        let recordsOffset = indexOffset + keys * Layout.indexStride
        let blobOffset = recordsOffset + entries * Layout.recordStride
        guard blobOffset + blob == mapped.count else { throw LoadError.corrupt("truncated payload") }
        self.data = mapped
        self.sourceURL = url
        self.entryCount = entries
        self.keyCount = keys
        self.keysOffset = keysOffset
        self.indexOffset = indexOffset
        self.recordsOffset = recordsOffset
        self.blobOffset = blobOffset
        self.blobSize = blob
    }

    // MARK: - Lookup

    /// All candidates for an exact code, in dictionary (frequency) order.
    public func candidates(for code: String, limit: Int = 64) -> [WubiCandidate] {
        let packed = WubiCode.pack(code)
        guard packed != 0 else { return [] }
        return candidates(forPacked: packed, limit: limit)
    }

    public func candidates(forPacked packed: UInt32, limit: Int = 64) -> [WubiCandidate] {
        guard let slot = slot(forKey: packed) else { return [] }
        let offset = Int(data.uint32(at: indexOffset + slot * Layout.indexStride))
        let count = Int(data.uint32(at: indexOffset + slot * Layout.indexStride + 4))
        let shown = min(count, limit)
        var result: [WubiCandidate] = []
        result.reserveCapacity(shown)
        let base = recordsOffset + offset * Layout.recordStride
        for i in 0..<shown {
            let record = base + i * Layout.recordStride
            let strOffset = Int(data.uint32(at: record))
            let weight = data.uint16(at: record + 4)
            let length = Int(data[record + 6])
            let flags = data[record + 7]
            result.append(WubiCandidate(text: string(blobOffset + strOffset, length), weight: weight, flags: flags))
        }
        return result
    }

    /// Number of distinct codes that start with the prefix.
    public func codeCount(prefix: String) -> Int {
        guard !prefix.isEmpty, prefix.count <= WubiCode.maxCodeLength else { return 0 }
        let range = WubiCode.prefixRange(prefix)
        return max(0, lowerBound(of: range.upperBound &+ 1) - lowerBound(of: range.lowerBound))
    }

    /// True when a longer code exists that extends the given code.
    public func hasLongerCode(than code: String) -> Bool {
        guard !code.isEmpty, code.count < WubiCode.maxCodeLength else { return false }
        let range = WubiCode.prefixRange(code)
        var index = lowerBound(of: range.lowerBound)
        let end = lowerBound(of: range.upperBound &+ 1)
        let selfKey = WubiCode.pack(code)
        while index < end {
            if key(at: index) != selfKey { return true }
            index += 1
        }
        return false
    }

    // MARK: - Internals

    @inline(__always)
    private func key(at slot: Int) -> UInt32 {
        data.uint32(at: keysOffset + slot * Layout.keyStride)
    }

    private func slot(forKey packed: UInt32) -> Int? {
        let index = lowerBound(of: packed)
        guard index < keyCount, key(at: index) == packed else { return nil }
        return index
    }

    /// First slot whose key is greater than or equal to the packed value.
    private func lowerBound(of packed: UInt32) -> Int {
        var low = 0
        var high = keyCount
        while low < high {
            let mid = (low + high) / 2
            if key(at: mid) < packed {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private func string(_ offset: Int, _ length: Int) -> String {
        guard length > 0 else { return "" }
        return data.withUnsafeBytes { raw in
            let slice = UnsafeRawBufferPointer(rebasing: raw[offset..<(offset + length)])
            return String(decoding: slice, as: UTF8.self)
        }
    }
}

extension Data {
    @inline(__always)
    func uint32(at offset: Int) -> UInt32 {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }

    @inline(__always)
    func uint16(at offset: Int) -> UInt16 {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
    }
}
