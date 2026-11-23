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
    private let lock = NSLock()
    // A pending item doubles as the dirty flag. Later commits share its deadline.
    private var pendingSave: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.oneself.wubi.lexicon", qos: .utility)
    private let schedule: (DispatchQueue, DispatchTimeInterval, DispatchWorkItem) -> Void
    public let fileURL: URL

    public static let shared = UserLexicon()

    public convenience init(fileURL: URL? = nil) {
        self.init(fileURL: fileURL) { queue, delay, item in
            queue.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    init(fileURL: URL?, schedule: @escaping (DispatchQueue, DispatchTimeInterval, DispatchWorkItem) -> Void) {
        self.fileURL = fileURL ?? WubiSettings.supportDirectory.appendingPathComponent("userfreq.tsv")
        self.schedule = schedule
        load()
    }

    public var entryCount: Int { lock.withLock { counts.count } }

    public func boost(for code: String, text: String) -> Int {
        lock.withLock { counts[Key(code: code, text: text)] ?? 0 }
    }

    /// How many times this code was committed at all, used to normalise.
    public func total(for code: String) -> Int {
        lock.withLock { codeTotals[code] ?? 0 }
    }

    /// Empirical probability of picking this word for this code, 0 when unseen.
    public func probability(code: String, text: String) -> Double {
        lock.withLock {
            guard let total = codeTotals[code], total > 0 else { return 0 }
            return Double(counts[Key(code: code, text: text)] ?? 0) / Double(total)
        }
    }

    /// Learn immediately; only persistence is batched.
    public func recordCommit(code: String, text: String) {
        guard !code.isEmpty, !text.isEmpty else { return }
        lock.withLock {
            counts[Key(code: code, text: text), default: 0] += 1
            codeTotals[code, default: 0] += 1
            scheduleSaveIfNeeded()
        }
    }

    public func reset() {
        lock.withLock {
            counts.removeAll()
            codeTotals.removeAll()
            scheduleSaveIfNeeded()
        }
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

    // Called with the state lock held. Never move an existing batch deadline.
    private func scheduleSaveIfNeeded() {
        guard pendingSave == nil else { return }
        let item = DispatchWorkItem { [weak self] in self?.writePending() }
        pendingSave = item
        schedule(queue, .seconds(30), item)
    }

    /// Force a pending batch to disk. Waiting also drains any write already in flight.
    public func flush(wait: Bool = false) {
        if wait {
            queue.sync { writePending() }
        } else {
            queue.async { self.writePending() }
        }
    }

    // Only the serial writer queue takes snapshots; a slow write never holds the state lock.
    private func writePending() {
        let snapshot: [Key: Int]? = lock.withLock {
            guard let item = pendingSave else { return nil }
            item.cancel()
            pendingSave = nil
            return counts
        }
        guard let snapshot else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var text = ""
            for (key, count) in snapshot where count > 0 {
                text += key.code + "\t" + key.text + "\t" + String(count) + "\n"
            }
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            // Keep the current counts dirty, including anything learned during the write.
            lock.withLock { scheduleSaveIfNeeded() }
        }
    }
}
