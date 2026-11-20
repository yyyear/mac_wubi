import SwiftUI
import WubiCore

/// Sidebar categories, mirroring a typical input method settings app.
enum SettingsSection: String, CaseIterable, Identifiable {
    case input = "输入"
    case dictionaries = "词库"
    case candidates = "候选"
    case punctuation = "标点"
    case language = "中英文"
    case shortcuts = "按键说明"
    case about = "关于"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .input: return "keyboard"
        case .dictionaries: return "books.vertical"
        case .candidates: return "list.bullet.rectangle"
        case .punctuation: return "text.alignleft"
        case .language: return "globe"
        case .shortcuts: return "command"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var section: SettingsSection = .input

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.symbol)
                        .frame(width: 18, alignment: .center)
                        .foregroundStyle(.secondary)
                    Text(item.rawValue)
                }
                .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 128, ideal: 154, max: 190)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch section {
                    case .input: InputPane()
                    case .dictionaries: DictionaryPane()
                    case .candidates: CandidatePane()
                    case .punctuation: PunctuationPane()
                    case .language: LanguagePane()
                    case .shortcuts: ShortcutPane()
                    case .about: AboutPane()
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(section.rawValue)
        }
        .frame(minWidth: 560, minHeight: 400)
    }
}

// MARK: - Shared pieces

/// A titled card holding rows, matching the grouped look of the reference UI.
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) { content }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

/// One labelled row inside a card.
struct SettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                labels
                Spacer(minLength: 12)
                HStack { trailing }
            }
            VStack(alignment: .leading, spacing: 8) {
                labels
                HStack { trailing }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct DividerlessModifier: ViewModifier {
    func body(content: Content) -> some View { content }
}

// MARK: - Panes

struct InputPane: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Card(title: "输入方案") {
            SettingRow(title: "当前方案", subtitle: "使用四方五笔时，在屏幕顶部状态栏的输入法菜单中选择方案。") {
                Text(store.settings.inputScheme.displayName)
                    .fontWeight(.medium)
            }
        }
        Card(title: "编码与上屏") {
            SettingRow(title: "四码唯一自动上屏", subtitle: "仅在「只五笔」方案中生效") {
                Toggle("四码唯一自动上屏", isOn: $store.settings.autoCommitUnique).labelsHidden().toggleStyle(.switch)
            }
        }
        FuzzyPinyinCard()
    }
}

private struct FuzzyPinyinCard: View {
    @EnvironmentObject private var store: SettingsStore
    var body: some View {
        Card(title: "模糊音") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 162), alignment: .leading)], alignment: .leading, spacing: 14) {
                ForEach(FuzzyPair.allCases, id: \.self) { pair in
                    Toggle(pair.label, isOn: Binding(
                        get: { store.settings.fuzzyPinyin.contains(pair) },
                        set: { enabled in
                            if enabled { store.settings.fuzzyPinyin.insert(pair) }
                            else { store.settings.fuzzyPinyin.remove(pair) }
                        }
                    )).toggleStyle(.checkbox)
                }
            }.padding(14)
        }
        Text("只对拼音和混合方案生效。准确拼写优先，取消全部勾选即可关闭模糊音。")
            .font(.callout).foregroundStyle(.secondary)
    }
}

struct CandidatePane: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Card(title: "数量与分页") {
            SettingRow(title: "每页候选数量", subtitle: "范围 1–10，默认 5") {
                Stepper(value: $store.settings.pageSize, in: 1...10) {
                    Text("\(store.settings.pageSize)")
                        .monospacedDigit()
                        .frame(width: 22, alignment: .trailing)
                }
                .frame(width: 110)
            }
            SettingRow(title: "候选上限", subtitle: "单个编码最多保留多少条候选") {
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { Double(store.settings.effectiveCandidateLimit) },
                        set: { store.settings.candidateLimit = Int($0) }
                    ), in: 8...256, step: 8)
                    .frame(width: 150)
                    Text("\(store.settings.effectiveCandidateLimit)")
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
        }
        Card(title: "显示与排序") {
            SettingRow(title: "显示前缀候选", subtitle: "同时显示以当前编码开头的其他词") {
                Toggle("显示前缀候选", isOn: $store.settings.prefixCandidates).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "显示编码提示") {
                Toggle("显示编码提示", isOn: $store.settings.showCodeHint).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "按上屏概率排序", subtitle: "记录实际选择过的词，越常用越靠前") {
                Toggle("按上屏概率排序", isOn: $store.settings.userLearning).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

struct PunctuationPane: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Card(title: "标点") {
            SettingRow(title: "中文模式使用中文标点", subtitle: ". → 。  , → ，  ? → ？") {
                Toggle("中文模式使用中文标点", isOn: $store.settings.chinesePunctuation).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Shift + 标点输入英文标点", subtitle: "按住 Shift 打标点得到半角符号，不影响中英切换") {
                Toggle("Shift + 标点输入英文标点", isOn: $store.settings.englishPunctuationWithShift).labelsHidden().toggleStyle(.switch)
            }
        }

        Text("中文模式下 Shift+标点是唯一能直接打出半角符号的方式；关掉后所有标点都会转成全角。")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}

struct LanguagePane: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Card(title: "中英文切换") {
            SettingRow(title: "单击 Shift 切换", subtitle: "按下再松开 Shift、中间没有其它键时切换") {
                Toggle("单击 Shift 切换", isOn: $store.settings.shiftTogglesEnglish).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Shift + 空格 切换") {
                Toggle("Shift + 空格切换", isOn: $store.settings.shiftSpaceTogglesEnglish).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "切换时显示提示", subtitle: "在光标处显示「中」/「英」徽标") {
                Toggle("切换时显示提示", isOn: $store.settings.showModeHUD).labelsHidden().toggleStyle(.switch)
            }
        }

        Text("切换语言时，已经输入的编码会以英文字母原样上屏，不会丢字。")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}

struct ShortcutPane: View {
    private let items: [(String, String)] = [
        ("a–z", "输入五笔编码或全拼（ü 用 v）"),
        ("空格", "上屏第一个候选"),
        ("1–9", "上屏对应候选"),
        (", . / ← →", "候选翻页"),
        ("回车", "上屏当前编码原文"),
        ("Esc", "取消当前编码"),
        ("删除", "删掉最后一个编码"),
        ("Shift（单击）", "中/英切换"),
        ("Shift + 空格", "中/英切换（备用）"),
        ("Shift + 标点", "输入半角英文标点"),
    ]

    var body: some View {
        Card(title: "输入与选词按键") {
            ForEach(items, id: \.0) { item in
                HStack {
                    Text(item.0)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .frame(width: 130, alignment: .leading)
                    Text(item.1)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                }
            }
        }
    }
}

struct AboutPane: View {
    @EnvironmentObject private var store: SettingsStore
    @State private var message: String?

    var body: some View {
        Card(title: "四方五笔") {
            SettingRow(title: "版本", subtitle: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") {
                EmptyView()
            }
            SettingRow(title: "字典", subtitle: "内置五笔 86 和离线全拼，可在「词库」中导入") { EmptyView() }
            SettingRow(title: "配置文件", subtitle: store.configPath) {
                Button("打开文件夹") {
                    NSWorkspace.shared.activateFileViewerSelecting([WubiSettings.fileURL])
                }
            }
        }
        Card(title: "数据与设置") {
            SettingRow(title: "用户词频", subtitle: "清除后候选排序回到字典原序") {
                Button("清除") {
                    UserLexicon.shared.reset()
                    UserLexicon.shared.flush(wait: true)
                    message = "已清除"
                }
            }
            SettingRow(title: "恢复默认设置") {
                Button("恢复") {
                    store.resetToDefaults()
                    message = "已恢复默认"
                }
            }
        }

        if let message {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}