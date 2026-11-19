import Foundation

/// The typing state machine: owns the pending code, the ranked candidates and
/// the current page. Deliberately free of AppKit so it can be unit tested and
/// driven by the command line harness.
public final class InputEngine {
    public private(set) var buffer = ""
    public private(set) var candidates: [WubiCandidate] = []
    public private(set) var page = 0

    public var settings: WubiSettings
    public let dictionary: WubiDictionary
    public let lexicon: UserLexicon

    /// How many extra candidates a prefix may contribute.
    private let prefixSupplementLimit = 24

    public init(dictionary: WubiDictionary = .shared,
                lexicon: UserLexicon = .shared,
                settings: WubiSettings = .load()) {
        self.dictionary = dictionary
        self.lexicon = lexicon
        self.settings = settings
    }

    // MARK: - State

    public var isActive: Bool { !buffer.isEmpty }

    /// 1 to 10, defaulting to 5.
    public var pageSize: Int { settings.effectivePageSize }

    public var pageCount: Int {
        guard !candidates.isEmpty else { return 0 }
        return (candidates.count + pageSize - 1) / pageSize
    }

    public var pageCandidates: ArraySlice<WubiCandidate> {
        guard !candidates.isEmpty else { return [][...] }
        let start = min(page * pageSize, candidates.count)
        let end = min(start + pageSize, candidates.count)
        return candidates[start..<end]
    }

    /// Number of the first candidate on the current page (1-based).
    public var pageStartNumber: Int { page * pageSize + 1 }

    public var codeHint: String {
        guard settings.showCodeHint, !buffer.isEmpty else { return "" }
        if candidates.isEmpty {
            return buffer.count < WubiCode.maxCodeLength ? "继续输入" : "无候选"
        }
        if buffer.count < WubiCode.maxCodeLength, dictionary.hasLongerCode(than: buffer) {
            return "可续码"
        }
        if candidates.count > 1 { return "重码 " + String(candidates.count) }
        return ""
    }

    // MARK: - Typing

    /// Appends one key. Returns the text to commit when the code auto-commits.
    @discardableResult
    public func append(_ character: Character) -> String? {
        guard character.isLetter, character.isASCII else { return nil }
        guard buffer.count < WubiCode.maxCodeLength else { return nil }
        buffer.append(Character(character.lowercased()))
        refresh()
        if buffer.count == WubiCode.maxCodeLength,
           settings.autoCommitUnique,
           let only = candidates.first,
           candidates.count == 1 {
            return finish(with: only)
        }
        return nil
    }

    /// Removes the last key. Returns false when there was nothing to remove.
    @discardableResult
    public func backspace() -> Bool {
        guard !buffer.isEmpty else { return false }
        buffer.removeLast()
        refresh()
        return true
    }

    public func reset() {
        buffer = ""
        candidates = []
        page = 0
    }

    // MARK: - Selection

    /// Commits a candidate by its absolute index in the ranked list.
    public func commit(index: Int) -> String? {
        guard candidates.indices.contains(index) else { return nil }
        return finish(with: candidates[index])
    }

    /// Commits a candidate by its 1-based number on the current page.
    public func commit(pageNumber number: Int) -> String? {
        commit(index: page * pageSize + number - 1)
    }

    public func commitFirst() -> String? {
        commit(index: page * pageSize)
    }

    @discardableResult
    public func nextPage() -> Bool {
        guard page + 1 < pageCount else { return false }
        page += 1
        return true
    }

    @discardableResult
    public func previousPage() -> Bool {
        guard page > 0 else { return false }
        page -= 1
        return true
    }

    // MARK: - Internals

    private func finish(with candidate: WubiCandidate) -> String {
        if settings.userLearning {
            lexicon.recordCommit(code: buffer, text: candidate.text)
        }
        let text = candidate.text
        reset()
        return text
    }

    private func refresh() {
        page = 0
        guard !buffer.isEmpty else {
            candidates = []
            return
        }
        candidates = ranked(for: buffer)
    }

    /// Exact-code candidates first, then words whose code merely starts with the
    /// typed keys. The second group makes a partial code productive: typing "wq"
    /// offers every "wqa"..."wqz" word too, instead of staying silent until the
    /// full four keys are in.
    private func ranked(for code: String) -> [WubiCandidate] {
        var result = boosted(dictionary.candidates(for: code, limit: settings.effectiveCandidateLimit), code: code)

        guard settings.prefixCandidates, code.count < WubiCode.maxCodeLength else { return result }

        var seen = Set(result.map { $0.text })
        for candidate in prefixSupplements(for: code) {
            guard !seen.contains(candidate.text) else { continue }
            seen.insert(candidate.text)
            result.append(candidate)
            if result.count >= settings.effectiveCandidateLimit { break }
        }
        return result
    }

    /// Candidates reachable by extending the prefix with one more key.
    /// Only the next code length is probed (never the whole subtree), so this
    /// stays a bounded 26 lookups no matter how short the prefix is.
    private func prefixSupplements(for code: String) -> [WubiCandidate] {
        var collected: [WubiCandidate] = []
        collected.reserveCapacity(52)
        for scalar in Unicode.Scalar("a").value...Unicode.Scalar("z").value {
            guard let letter = Unicode.Scalar(scalar) else { continue }
            let extended = code + String(Character(letter))
            collected.append(contentsOf: dictionary.candidates(for: extended, limit: 2))
        }
        return collected
            .sorted { $0.weight > $1.weight }
            .prefix(prefixSupplementLimit)
            .map { $0 }
    }

    /// Ranks candidates by how likely the user is to commit them.
    ///
    /// The dictionary weight is the prior; every commit for this exact code is
    /// evidence. A word committed n times out of m for the code gets a score
    /// proportional to n/m, so repeated picks converge on the top while words
    /// nobody has picked keep the shipped order.
    private func boosted(_ base: [WubiCandidate], code: String) -> [WubiCandidate] {
        guard settings.userLearning, !base.isEmpty else { return base }
        let total = lexicon.total(for: code)
        guard total > 0 else { return base }

        let scored = base.map { candidate -> (WubiCandidate, Double) in
            let probability = lexicon.probability(code: code, text: candidate.text)
            // Prior sits just under 1.0 so a single commit already outranks it.
            let prior = Double(candidate.weight) / 65535.0
            return (candidate, probability + prior * 0.35)
        }
        return scored.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.weight > rhs.0.weight
        }.map { $0.0 }
    }
}