//
//  SettingsView.swift
//  MLXChatExample
//

import SwiftUI

/// 设置页：千束人设编辑（含恢复默认）与生成相关的全局开关。
struct SettingsView: View {
    /// Shared session store, used to sync persona changes into the Chisato
    /// conversation's system prompt.
    let store: ChatSessionStore

    /// Whether the KV cache is quantized to 8-bit.
    @State private var kvCacheQuantized =
        UserDefaults.standard.object(forKey: "kvCacheQuantized") as? Bool ?? true

    /// Model used to summarize conversations (default qwen3:4b).
    @State private var summaryModelName =
        UserDefaults.standard.string(forKey: "summaryModelName") ?? "qwen3:4b"

    /// Persona draft being edited.
    @State private var personaDraft = ""

    /// Names of models already downloaded, used to mark them in the picker.
    @State private var downloadedNames: Set<String> = []

    var body: some View {
        Form {
            Section("生成选项") {
                Toggle(isOn: $kvCacheQuantized) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("KV 缓存量化")
                        Text("开启后长对话内存占用约减半，质量几乎无损；个别模型未验证，如异常请关闭")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: kvCacheQuantized) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "kvCacheQuantized")
                }

                Picker("总结模型", selection: $summaryModelName) {
                    ForEach(sortedModels) { model in
                        Text(summaryLabel(for: model)).tag(model.name)
                    }
                }
                .onChange(of: summaryModelName) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "summaryModelName")
                }
            }

            Section("千束的人设与记忆") {
                TextEditor(text: $personaDraft)
                    .frame(height: 240)
            }

            Section {
                Button("保存人设") {
                    ChisatoProfile.shared.update(personaDraft)
                    syncChisatoSystemPrompt()
                }

                Button("恢复默认设定", role: .destructive) {
                    ChisatoProfile.shared.resetToDefault()
                    personaDraft = ChisatoProfile.defaultPersona
                    syncChisatoSystemPrompt()
                }
            } footer: {
                Text("「恢复默认设定」会把千束的人设与记忆重置为初始状态。")
            }
        }
        .navigationTitle("设置")
        .onAppear {
            personaDraft = ChisatoProfile.shared.persona
        }
        .task {
            await refreshDownloadedNames()
        }
        .onChange(of: MLXService.shared.activeDownloads) { old, new in
            if old.count > new.count {
                Task { await refreshDownloadedNames() }
            }
        }
    }

    /// 已下载在前（组内 名称 → 体积），未下载在后（同序）。
    private var sortedModels: [LMModel] {
        let downloaded = MLXService.availableModels
            .filter { downloadedNames.contains($0.name) }
            .sorted { LMModel.listSort($0, $1) }
        let rest = MLXService.availableModels
            .filter { !downloadedNames.contains($0.name) }
            .sorted { LMModel.listSort($0, $1) }
        return downloaded + rest
    }

    /// 查询已下载的模型名集合。
    private func refreshDownloadedNames() async {
        var names = Set<String>()
        for model in MLXService.availableModels where MLXService.shared.isDownloaded(model) {
            names.insert(model.name)
        }
        downloadedNames = names
    }

    /// 总结模型选择器的显示文字：类型标注 + 已下载打勾 + 默认标识。
    private func summaryLabel(for model: LMModel) -> String {
        let kind = model.isVisionModel ? "视觉" : "文本"
        let check = downloadedNames.contains(model.name) ? " ✓" : ""
        let isDefault = model.name == "qwen3:4b"
        return "\(model.displayName)（\(kind)）\(check)" + (isDefault ? "（默认）" : "")
    }

    /// Propagate persona changes to the dedicated Chisato conversation's
    /// system prompt, if it exists.
    private func syncChisatoSystemPrompt() {
        guard let session = store.sessions.first(where: { $0.isChisato }) else {
            return
        }

        let persona = ChisatoProfile.shared.persona
        if let index = session.messages.firstIndex(where: { $0.role == .system }) {
            session.messages[index].content = persona
        } else {
            session.messages.insert(.system(persona), at: 0)
        }
        store.save(session)
    }
}

#Preview {
    NavigationStack {
        SettingsView(store: ChatSessionStore())
    }
}
