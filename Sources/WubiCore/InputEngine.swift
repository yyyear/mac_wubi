import Foundation

/// The typing state machine: owns the pending code, the ranked candidates and
/// the current page. Deliberately free of AppKit so it can be unit tested and
/// driven by the command line harness.
public final class InputEngine {
    public private(set) var buffer = ""
    public private(set) var candidates: [WubiCandidate] = []
    public private(set) var page = 0

    public var settings: WubiSettings {
        didSet {
            if oldValue.inputScheme != settings.inputScheme { reset() }
            else if isActive { refresh() }
        }
    }
    public let dictionary: WubiDictionary
    public let lexicon: UserLexicon

    /// How many extra candidates a prefix may contribute.
    private let prefixSupplementLimit = 24

    typealias Lookup = (String, InputScheme, Bool, Int) -> [WubiCandidate]
    private let lookup: Lookup

    public convenience init(dictionary: WubiDictionary = .shared,
                            lexicon: UserLexicon = .shared,
                            settings: WubiSettings = .load()) {
        self.init(dictionary: dictionary, lexicon: lexicon, settings: settings) { code, scheme, prefix, limit in
            SupplementalLexicon.shared.candidates(for: code, scheme: scheme, prefix: prefix, limit: limit)
        }
    }

    init(dictionary: WubiDictionary = .shared, lexicon: UserLexicon, settings: WubiSettings,
         lookup: @escaping Lookup) {
        self.lookup = lookup
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
            return settings.inputScheme != .wubi || buffer.count < WubiCode.maxCodeLength ? "继续输入" : "无候选"
        }
        if settings.inputScheme != .pinyin, !buffer.contains("'"),
           dictionary.hasLongerCode(than: buffer) {
            return "可续码"
        }
        if candidates.count > 1 { return "重码 " + String(candidates.count) }
        return ""
    }

    // MARK: - Typing

    /// Appends one key. Returns the text to commit when the code auto-commits.
    @discardableResult
    public func append(_ character: Character) -> String? {
        let isSeparator = character == "'" && settings.inputScheme != .wubi && !buffer.isEmpty && buffer.last != "'"
        guard isSeparator || (character.isASCII && character.isLetter) else { return nil }
        guard settings.inputScheme != .wubi || buffer.count < WubiCode.maxCodeLength else { return nil }
        buffer.append(Character(character.lowercased()))
        refresh()
        if settings.inputScheme == .wubi, buffer.count == WubiCode.maxCodeLength,
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

    /// Exact results always precede completions. Interleave Wubi and Pinyin
    /// by rank within each tier: their weights are not on a common scale, and
    /// one dictionary should not consume the entire limit before the other.
    private func ranked(for code: String) -> [WubiCandidate] {
        let limit = settings.effectiveCandidateLimit
        // The packed dictionary truncates long keys. Never probe it with a
        // long spelling, or with a Pinyin syllable boundary, even in mixed mode.
        let useWubi = settings.inputScheme != .pinyin && code.utf8.count <= WubiCode.maxCodeLength && !code.contains("'")
        let usePinyin = settings.inputScheme != .wubi
        let spelling = usePinyin ? code.replacingOccurrences(of: "'", with: "") : ""
        var seen = Set<String>()
        var result: [WubiCandidate] = []

        func appendTier(prefix: Bool) {
            var wubi: [WubiCandidate] = []
            if useWubi && (!prefix || code.utf8.count < WubiCode.maxCodeLength) {
                wubi = prefix ? prefixSupplements(for: code) : dictionary.candidates(for: code, limit: limit)
                let imported = lookup(code, .wubi, prefix, limit)
                if !imported.isEmpty {
                    wubi = (wubi + imported).sorted { $0.weight > $1.weight }
                }
            }
            let pinyin = usePinyin ? lookup(spelling, .pinyin, prefix, limit) : []
            var tier: [WubiCandidate] = []
            for i in 0..<max(wubi.count, pinyin.count) {
                if i < wubi.count, seen.insert(wubi[i].text).inserted { tier.append(wubi[i]) }
                if i < pinyin.count, seen.insert(pinyin[i].text).inserted { tier.append(pinyin[i]) }
            }
            appendRanked(tier)
        }

        func appendRanked(_ values: [WubiCandidate]) {
            var tier = values
            // A learned pick can lead either scheme, but never jump from the
            // prefix tier ahead of an exact match. Stable ties retain the merge order.
            if settings.userLearning, lexicon.total(for: code) > 0 {
                tier.sort { lexicon.boost(for: code, text: $0.text) > lexicon.boost(for: code, text: $1.text) }
            }
            result.append(contentsOf: tier.prefix(limit - result.count))
        }

        appendTier(prefix: false)
        if result.count < limit, usePinyin {
            // Only exact lookup of bounded alternate spellings; never fan out
            // prefix scans or send fuzzy codes to the Wubi dictionary.
            let variants = FuzzyPinyin.variants(for: code, rules: settings.fuzzyPinyin)
            let hits = variants.flatMap { lookup($0, .pinyin, false, limit) }
                .sorted { $0.weight > $1.weight }
            appendRanked(hits.filter { seen.insert($0.text).inserted })
        }
        if result.count < limit, settings.prefixCandidates { appendTier(prefix: true) }
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

}