import Foundation
import WubiCore

/// Headless harness: exercises exactly the same engine the input method uses,
/// which makes behaviour verifiable without installing anything.

func usage() {
    print("""
    wubi-cli -- 五笔86 引擎命令行

      wubi-cli lookup <code>                列出某编码的全部候选
      wubi-cli type <keys> [wubi|pinyin|mixed] 逐键模拟输入（如 nihao mixed）
      wubi-cli import <pinyin|wubi> <file>   增量导入本机词库
      wubi-cli bench [iterations]           吞吐量测试
      wubi-cli stats                        字典统计
      wubi-cli commit <code> <n>            模拟选中第 n 个候选（学习/排序）
    """)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    usage()
    exit(2)
}
arguments.removeFirst()

let dictionary = WubiDictionary.shared

func runLookup(_ code: String) {
    let candidates = dictionary.candidates(for: code, limit: 32)
    print("编码 \(code)  ->  \(candidates.count) 个候选")
    for (index, candidate) in candidates.enumerated() {
        let kind = candidate.isWord ? "词" : "字"
        print(String(format: "  %2d. %@  [%@ 权重 %5d]", index + 1, candidate.text, kind, candidate.weight))
    }
    if candidates.isEmpty { print("  (无)") }
}

func runType(_ keys: String, scheme: InputScheme) {
    var settings = WubiSettings.load()
    settings.inputScheme = scheme
    settings.userLearning = false
    let engine = InputEngine(settings: settings)
    print("输入: \(keys)")
    for character in keys {
        let committed = engine.append(character)
        let page = engine.pageCandidates.map { $0.text }.joined(separator: " ")
        print("  \(engine.buffer) -> [\(page)]  \(engine.codeHint)")
        if let committed { print("  自动上屏: \(committed)"); break }
    }
}

func runBench(_ iterations: Int) {
    let engine = InputEngine(settings: WubiSettings())
    let start = Date()
    var commits = 0
    for _ in 0..<iterations {
        for character in "wqiy" {
            if engine.append(character) != nil { commits += 1 }
        }
        engine.reset()
    }
    let elapsed = Date().timeIntervalSince(start)
    let keys = Double(iterations * 4)
    print(String(format: "%.0f 次按键 / %.3f 秒 = %.0f 键/秒 (上屏 %d)",
                 keys, elapsed, keys / elapsed, commits))
}

switch command {
case "lookup":
    guard let code = arguments.first else { usage(); exit(2) }
    runLookup(code)
case "type":
    guard let keys = arguments.first else { usage(); exit(2) }
    guard let scheme = InputScheme(rawValue: arguments.dropFirst().first ?? WubiSettings.load().inputScheme.rawValue) else { usage(); exit(2) }
    runType(keys, scheme: scheme)
case "import":
    guard arguments.count == 2, let scheme = InputScheme(rawValue: arguments[0]), scheme != .mixed else { usage(); exit(2) }
    do {
        let n = try DictionaryImporter.importFile(URL(fileURLWithPath: arguments[1]), scheme: scheme)
        DistributedNotificationCenter.default().postNotificationName(LexiconEvents.changed, object: nil, userInfo: nil, deliverImmediately: true)
        print("新增 \(n) 条；已有条目按较高权重保留。")
    } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
case "bench":
    runBench(Int(arguments.first ?? "2000") ?? 2000)
case "stats":
    print("编码数: \(dictionary.keyCount)")
    print("词条数: \(dictionary.entryCount)")
    print("文件:   \(dictionary.sourceURL.path)")
case "commit":
    guard arguments.count >= 2, let number = Int(arguments[1]), number > 0 else { usage(); exit(2) }
    let engine = InputEngine(settings: WubiSettings())
    for character in arguments[0] { engine.append(character) }
    if let text = engine.commit(index: number - 1) {
        print("上屏: \(text)")
        // The lexicon saves on a debounce timer, which a short lived CLI process
        // never reaches: flush synchronously so learning survives.
        engine.lexicon.flush()
        Thread.sleep(forTimeInterval: 0.3)
    } else {
        print("没有第 \(number) 个候选")
    }
default:
    usage()
    exit(2)
}