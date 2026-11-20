import Foundation

public enum FuzzyPair: String, Codable, CaseIterable, Sendable {
    case zZh = "z-zh", cCh = "c-ch", sSh = "s-sh"
    case nL = "n-l", fH = "f-h", lR = "l-r"
    case anAng = "an-ang", enEng = "en-eng", inIng = "in-ing"

    public static let defaults: Set<Self> = [.zZh, .cCh, .sSh, .anAng, .enEng, .inIng]
    public var label: String { rawValue.replacingOccurrences(of: "-", with: " = ") }

    fileprivate var isInitial: Bool {
        switch self { case .anAng, .enEng, .inIng: return false; default: return true }
    }

    /// Match the full initial (z is not the initial of zhang), or the nasal
    /// suffix of the final (this includes e.g. ian/iang and uan/uang).
    fileprivate func swap(in syllable: String) -> String? {
        let parts = rawValue.components(separatedBy: "-")
        for (from, to) in [(parts[1], parts[0]), (parts[0], parts[1])] {
            if isInitial {
                guard syllable.hasPrefix(from) else { continue }
                return to + syllable.dropFirst(from.count)
            } else if syllable.hasSuffix(from) {
                return syllable.dropLast(from.count) + to
            }
        }
        return nil
    }
}

enum FuzzyPinyin {
    /// Enumerated once from the explicit readings of the bundled pinyin_simp
    /// lexicon (see Pinyin-NOTICE). Exclude standalone nasal interjections:
    /// otherwise initial-only shortcuts like "n'l" could look like full pinyin.
    private static let syllables = """
    a ai an ang ao
    ba bai ban bang bao bei ben beng bi bian biao bie bin bing bo bu
    ca cai can cang cao ce cen ceng cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo
    da dai dan dang dao de dei den deng di dia dian diao die ding diu dong dou du duan dui dun duo
    e ei en eng er
    fa fan fang fei fen feng fiao fo fou fu
    ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo
    ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun huo
    ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun
    ka kai kan kang kao ke kei ken keng kong kou ku kua kuai kuan kuang kui kun kuo
    la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo long lou lu luan lue lun luo lv lve
    ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu
    na nai nan nang nao ne nei nen neng ni nian niang niao nie nin ning niu nong nou nu nuan nue nuo nv nve
    o ou
    pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu
    qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun
    ran rang rao re ren reng ri rong rou ru ruan rui run ruo
    sa sai san sang sao se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo si song sou su suan sui sun suo
    ta tai tan tang tao te tei teng ti tian tiao tie ting tong tou tu tuan tui tun tuo
    wa wai wan wang wei wen weng wo wu
    xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun
    ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun
    za zai zan zang zao ze zei zen zeng zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui zun zuo
    """.split(whereSeparator: { $0.isWhitespace }).map(String.init)

    private struct Choice {
        let code: String
        let rules: Set<FuzzyPair>
    }

    /// Index possible *typed* syllables back to real dictionary syllables.
    /// This also accepts fuzzy-only spellings such as fong for hong. Never
    /// chain initial rules (n/l plus l/r must not imply n/r).
    private static let table: [String: [Choice]] = {
        var result = [String: [Choice]]()
        for s in syllables {
            let initials = FuzzyPair.allCases.filter(\.isInitial).compactMap { p in p.swap(in: s).map { ($0, p) } }
            let bases: [(String, Set<FuzzyPair>)] = [(s, Set<FuzzyPair>())] + initials.map { ($0.0, Set([$0.1])) }
            for (base, rules) in bases {
                result[base, default: []].append(Choice(code: s, rules: rules))
                for p in FuzzyPair.allCases where !p.isInitial {
                    if let spelling = p.swap(in: base) {
                        result[spelling, default: []].append(Choice(code: s, rules: rules.union([p])))
                    }
                }
            }
        }
        return result
    }()

    static let variantLimit = 32

    /// Prefer the fewest whole syllables; break ties in favour of more exact
    /// syllables, then longest-leftmost. Apostrophes force hard boundaries.
    private static func split(_ part: Substring, rules: Set<FuzzyPair>) -> [[Choice]]? {
        let bytes = Array(part.utf8), n = bytes.count
        var cost = Array(repeating: Int.max, count: n + 1)
        var next = Array(repeating: 0, count: n)
        var options = Array(repeating: [Choice](), count: n)
        cost[n] = 0
        for i in (0..<n).reversed() {
            for j in stride(from: min(n, i + 6), through: i + 1, by: -1) where cost[j] != .max {
                let key = String(decoding: bytes[i..<j], as: UTF8.self)
                guard let all = table[key] else { continue }
                let choices = all.filter { $0.rules.isSubset(of: rules) }
                guard !choices.isEmpty else { continue }
                let score = cost[j] + 100 + (choices.contains { $0.rules.isEmpty } ? 0 : 1)
                if score < cost[i] { cost[i] = score; next[i] = j; options[i] = choices }
            }
        }
        guard cost[0] != .max else { return nil }
        var out = [[Choice]](), i = 0
        while i < n { out.append(options[i]); i = next[i] }
        return out
    }

    static func variants(for code: String, rules: Set<FuzzyPair>) -> [String] {
        guard !rules.isEmpty, !code.isEmpty, code.utf8.count <= 64 else { return [] }
        var choices = [[Choice]]()
        for part in code.split(separator: "'", omittingEmptySubsequences: false) {
            guard !part.isEmpty, let chunks = split(part, rules: rules) else { return [] }
            choices += chunks
        }
        guard choices.contains(where: { $0.contains { !$0.rules.isEmpty } }) else { return [] }
        var paths = [(code: "", cost: 0)]
        for chunk in choices {
            var best = [String: Int]()
            for path in paths {
                for edge in chunk {
                    let key = path.code + edge.code, cost = path.cost + edge.rules.count
                    if cost < best[key, default: .max] { best[key] = cost }
                }
            }
            paths = best.map { (code: $0.key, cost: $0.value) }.sorted {
                $0.cost != $1.cost ? $0.cost < $1.cost : $0.code < $1.code
            }.prefix(variantLimit + 1).map { $0 }
        }
        let original = code.replacingOccurrences(of: "'", with: "")
        return paths.lazy.map(\.code).filter { $0 != original }.prefix(variantLimit).map { $0 }
    }
}
