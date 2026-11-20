import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WubiCore

struct DictionaryPane: View {
    @State private var target: InputScheme = .pinyin
    @State private var importing = false
    @State private var result = ""
    @State private var confirmQingg = false
    private static let qingg = URL(fileURLWithPath: "/Library/Input Methods/Qingg.app/Contents/Resources/py_table.txt")

    var body: some View {
        Card(title: "导入本地词库") {
            SettingRow(title: "词库编码", subtitle: "混合模式会同时使用两类词库") {
                Picker("词库编码", selection: $target) {
                    Text("拼音").tag(InputScheme.pinyin)
                    Text("五笔").tag(InputScheme.wubi)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 140)
            }
            SettingRow(title: "从文件添加词条", subtitle: "保留内置词库，重复词条不会反复添加") {
                if importing { ProgressView().controlSize(.small) }
                Button("选择文件…", action: chooseFile)
            }
        }.disabled(importing)
        Text("支持带编码的 Rime 词典（.dict.yaml）、UTF-8 文本词表（.tsv / .txt），以及搜狗拼音细胞词库（.scel，仅拼音）。文件只在本机读取。")
            .font(.callout).foregroundStyle(.secondary)
        if FileManager.default.isReadableFile(atPath: Self.qingg.path) {
            Button("导入本机清歌拼音词库…") { confirmQingg = true }
                .disabled(importing)
                .alert("导入清歌的公共拼音词表？", isPresented: $confirmQingg) {
                    Button("取消", role: .cancel) {}
                    Button("导入") { target = .pinyin; runImport(Self.qingg, scheme: .pinyin) }
                } message: { Text("仅读取清歌 App 自带的 py_table.txt；不读取个人记录，也不会改动清歌。") }
        }
        if !result.isEmpty { Text(result).textSelection(.enabled) }
    }

    @MainActor private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["yaml", "txt", "tsv", "scel"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "导入"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runImport(url, scheme: target)
    }

    @MainActor private func runImport(_ url: URL, scheme: InputScheme) {
        importing = true
        result = "正在导入「\(url.lastPathComponent)」…"
        Task { @MainActor in
            defer { importing = false }
            do {
                let added = try await Task.detached(priority: .userInitiated) {
                    try DictionaryImporter.importFile(url, scheme: scheme)
                }.value
                DistributedNotificationCenter.default().postNotificationName(LexiconEvents.changed, object: nil, userInfo: nil, deliverImmediately: true)
                result = "已导入「\(url.lastPathComponent)」，新增 \(added) 条。下次输入时生效。"
            } catch {
                result = "导入失败：\(error.localizedDescription)"
            }
        }
    }
}
