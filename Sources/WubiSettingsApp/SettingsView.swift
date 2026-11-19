import SwiftUI
import WubiCore

/// Sidebar categories, mirroring a typical input method settings app.
enum SettingsSection: String, CaseIterable, Identifiable {
    case input = "输入"
    case candidates = "候选"
    case punctuation = "标点"
    case language = "中英文"
    case shortcuts = "快捷键"
    case about = "关于"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .input: return "keyboard"
        case .candidates: return "list.bullet.rectangle"
        case .punctuation: return "text.alignleft"
        case .language: return "globe"
        case .shortcuts: return "command"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: SettingsStore
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
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch section {
                    case .input: InputPane()
                    case .candidates: CandidatePane()
                    case .punctuation: PunctuationPane()
                    case .language: LanguagePane()
                    case .shortcuts: ShortcutPane()
                    case .about: AboutPane()
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(section.rawValue)
        }
        .frame(minWidth: 760, minHeight: 520)
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
                .font(.system(size: 12, weight: .semibold))
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
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
        Card(title: "输入") {
            SettingRow(title: "每页候选数量", subtitle: "范围 1–10，默认 5") {
                Stepper(value: $store.settings.pageSize, in: 1...10) {
                    Text("\(store.settings.pageSize)")
                        .monospacedDigit()
                        .frame(width: 22, alignment: .trailing)
                }
                .frame(width: 110)
            }
            SettingRow(title: "输入前列即出候选", subtitle: "输入 1–3 码时，同时列出编码以当前输入开头的词") {
                Toggle("", isOn: $store.settings.prefixCandidates).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "四码唯一自动上屏", subtitle: "四码只剩一个候选时直接上屏") {
                Toggle("", isOn: $store.settings.autoCommitUnique).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "按上屏概率排序", subtitle: "记录实际选择过的词，越常用越靠前") {
                Toggle("", isOn: $store.settings.userLearning).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "显示编码提示") {
                Toggle("", isOn: $store.settings.showCodeHint).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

struct CandidatePane: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Card(title: "候选窗口") {
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
            SettingRow(title: "当前每页", subtitle: "与「输入 → 每页候选数量」联动") {
                Text("\(store.settings.effectivePageSize) 个")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PunctuationPane: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Card(title: "标点") {
            SettingRow(title: "中文模式使用中文标点", subtitle: ". → 。  , → ，  ? → ？") {
                Toggle("", isOn: $store.settings.chinesePunctuation).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Shift + 标点输入英文标点", subtitle: "按住 Shift 打标点得到半角符号，不影响中英切换") {
                Toggle("", isOn: $store.settings.englishPunctuationWithShift).labelsHidden().toggleStyle(.switch)
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
                Toggle("", isOn: $store.settings.shiftTogglesEnglish).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "Shift + 空格 切换") {
                Toggle("", isOn: $store.settings.shiftSpaceTogglesEnglish).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(title: "切换时显示提示", subtitle: "在光标处显示「中」/「英」徽标") {
                Toggle("", isOn: $store.settings.showModeHUD).labelsHidden().toggleStyle(.switch)
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
        ("a–z", "输入五笔编码，最多四码"),
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
        Card(title: "按键") {
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
            SettingRow(title: "字典", subtitle: "五笔 86 · 约 13.7 万词条") { EmptyView() }
            SettingRow(title: "配置文件", subtitle: store.configPath) {
                Button("打开文件夹") {
                    NSWorkspace.shared.activateFileViewerSelecting([WubiSettings.fileURL])
                }
            }
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