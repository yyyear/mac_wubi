import Foundation

/// Frequency learning for committed words.
///
/// The shipped dictionary stays immutable; this side table records how often
/// each word was actually committed for a code. Ranking uses those counts as
/// an empirical probability, so the word you pick most often for a code floats
/// to the top without losing the curated order for unseen words.
public final class UserLexicon {
    public struct Key: Hashable, Sendable {
        public let code: String
        public let text: String
    }

    private var counts: [Key: Int] = [:]
    private var codeTotals: [String: Int] = [:]
    private var dirty = false
    private var saveWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.oneself.wubi.lexicon", qos: .utility)
    public let fileURL: URL

    public static let shared = UserLexicon()

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? WubiSettings.supportDirectory.appendingPathComponent("userfreq.tsv")
        load()
    }

    public var entryCount: Int { counts.count }

    public func boost(for code: String, text: String) -> Int {
        counts[Key(code: code, text: text)] ?? 0
    }

    /// How many times this code was committed at all, used to normalise.
    public func total(for code: String) -> Int {
        codeTotals[code] ?? 0
    }

    /// Empirical probability of picking this word for this code, 0 when unseen.
    public func probability(code: String, text: String) -> Double {
        let total = total(for: code)
        guard total > 0 else { return 0 }
        return Double(boost(for: code, text: text)) / Double(total)
    }

    /// Records a commit and schedules a debounced save.
    public func recordCommit(code: String, text: String) {
        guard !code.isEmpty, !text.isEmpty else { return }
        counts[Key(code: code, text: text), default: 0] += 1
        codeTotals[code, default: 0] += 1
        dirty = true
        scheduleSave()
    }

    public func reset() {
        counts.removeAll()
        codeTotals.removeAll()
        dirty = true
        scheduleSave()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = String(data: data, encoding: .utf8) else { return }
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count >= 3, let count = Int(parts[2]) else { continue }
            let code = String(parts[0])
            counts[Key(code: code, text: String(parts[1]))] = count
            codeTotals[code, default: 0] += count
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flush() }
        saveWorkItem = item
        queue.asyncAfter(deadline: .now() + 5, execute: item)
    }

    public func flush(wait: Bool = false) {
        guard dirty else { return }
        dirty = false
        let snapshot = counts
        let url = fileURL
        let work = {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var text = ""
            for (key, count) in snapshot where count > 0 {
                text += key.code + "\t" + key.text + "\t" + String(count) + "\n"
            }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        if wait {
            queue.sync(execute: work)
        } else {
            queue.async(execute: work)
        }
    }
}