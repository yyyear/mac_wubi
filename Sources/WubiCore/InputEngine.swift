import Foundation

/// The typing state machine: owns the pending code, the ranked candidates and
/// the current page. Deliberately free of AppKit so it can be unit tested and
/// driven by the command line harness.
public final class InputEngine {
    /// Original keystrokes for marked text and literal commits (Return / bare Shift).
    public private(set) var buffer = ""
    private var lookupCode: String { buffer.lowercased() }
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
    // At most 26 × 24 immutable bundled candidates per engine. Never cache
    // imported or learned results: both can change between keystrokes.
    private var firstLetterSupplements: [String: [WubiCandidate]] = [:]

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

    public var codeHint: String {
        guard settings.showCodeHint, !buffer.isEmpty else { return "" }
        if candidates.isEmpty {
            return settings.inputScheme != .wubi || buffer.count < WubiCode.maxCodeLength ? "继续输入" : "无候选"
        }
        if settings.inputScheme != .pinyin, !buffer.contains("'"),
           dictionary.hasLongerCode(than: lookupCode) {
            return "可续码"
        }
        if candidates.count > 1 { return "重码 " + String(candidates.count) }
        return ""
    }

    // MARK: - Typing

    /// A capital anywhere in the pending text signals possible English input.
    /// Keep accepting letters until the user commits it, even in four-key Wubi.
    public func requiresWubiRollover(before character: Character) -> Bool {
        settings.inputScheme == .wubi && buffer.count >= WubiCode.maxCodeLength
            && !character.isUppercase && !buffer.contains(where: { $0.isUppercase })
    }

    /// Appends one key. Returns the text to commit when the code auto-commits.
    @discardableResult
    public func append(_ character: Character) -> String? {
        let isSeparator = character == "'" && settings.inputScheme != .wubi && !buffer.isEmpty && buffer.last != "'"
        guard isSeparator || (character.isASCII && character.isLetter) else { return nil }
        guard !requiresWubiRollover(before: character) else { return nil }
        buffer.append(character)
        refresh()
        if settings.inputScheme == .wubi, buffer.count == WubiCode.maxCodeLength,
           settings.autoCommitUnique, !buffer.contains(where: { $0.isUppercase }),
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
        guard number > 0, number <= pageCandidates.count else { return nil }
        return commit(index: page * pageSize + number - 1)
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
            lexicon.recordCommit(code: lookupCode, text: candidate.text)
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
        candidates = ranked(for: lookupCode)
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
        let hasLearning = settings.userLearning && lexicon.total(for: code) > 0

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
            let remaining = limit - result.count
            guard hasLearning, values.count > 1 else {
                result.append(contentsOf: values.prefix(remaining))
                return
            }
            // One synchronized lookup per candidate, not two per comparison.
            // Stable ties retain the merge order within this tier.
            let scored = values.map { ($0, lexicon.boost(for: code, text: $0.text)) }
            result.append(contentsOf: scored.sorted { $0.1 > $1.1 }.prefix(remaining).map { $0.0 })
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
        let firstLetter = code.utf8.count == 1
        if firstLetter, let cached = firstLetterSupplements[code] { return cached }
        var collected: [WubiCandidate] = []
        collected.reserveCapacity(52)
        for scalar in Unicode.Scalar("a").value...Unicode.Scalar("z").value {
            guard let letter = Unicode.Scalar(scalar) else { continue }
            let extended = code + String(Character(letter))
            collected.append(contentsOf: dictionary.candidates(for: extended, limit: 2))
        }
        let supplements = Array(collected.sorted { $0.weight > $1.weight }.prefix(prefixSupplementLimit))
        if firstLetter { firstLetterSupplements[code] = supplements }
        return supplements
    }

}