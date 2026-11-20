import Foundation

/// ASCII -> Chinese punctuation, applied for single-character input while the
/// method is in Chinese mode. Quote characters toggle between the opening and
/// closing form, which is what people expect while typing prose.
public struct PunctuationMapper {
    public static let table: [Character: String] = [
        ",": "，", ".": "。", "?": "？", "!": "！", ";": "；", ":": "：",
        "(": "（", ")": "）", "[": "【", "]": "】", "{": "「", "}": "」",
        "<": "《", ">": "》", "\\": "、", "/": "・", "@": "＠", "#": "＃",
        "$": "￥", "%": "％", "^": "……", "&": "＆", "*": "＊", "-": "－",
        "_": "＿", "+": "＋", "=": "＝", "~": "～", "|": "｜",
    ]

    private var doubleQuoteOpen = true
    private var singleQuoteOpen = true

    public init() {}

    public mutating func reset() {
        doubleQuoteOpen = true
        singleQuoteOpen = true
    }

    public mutating func map(_ character: Character) -> String? {
        switch character {
        case "\"":
            defer { doubleQuoteOpen.toggle() }
            return doubleQuoteOpen ? "\u{201C}" : "\u{201D}"
        case "'":
            defer { singleQuoteOpen.toggle() }
            return singleQuoteOpen ? "\u{2018}" : "\u{2019}"
        default:
            return PunctuationMapper.table[character]
        }
    }
}
