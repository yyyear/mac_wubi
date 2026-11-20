public extension InputScheme {
    var displayName: String {
        switch self {
        case .wubi: return "只五笔"
        case .pinyin: return "只拼音"
        case .mixed: return "拼音五笔混合"
        }
    }
}
