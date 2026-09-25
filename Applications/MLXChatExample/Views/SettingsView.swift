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
    /// Whether thinking mode is enabled for models supporting the soft switch.
    @State private var thinkingEnabled =
        UserDefaults.standard.object(forKey: "thinkingEnabled") as? Bool ?? true

    /// Whether the KV cache is quantized to 8-bit.
    @State private var kvCacheQuantized =
        UserDefaults.standard.object(forKey: "kvCacheQuantized") as? Bool ?? false

    /// Persona draft being edited.
    @State private var personaDraft = ""

    var body: some View {
        Form {
            Section("生成选项") {
                Toggle(isOn: $thinkingEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("思考模式")
                        Text("对 Qwen3 系列生效：关闭后在消息末尾附加 /no_think，让模型直接回答")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: thinkingEnabled) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "thinkingEnabled")
                }

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
            }

            Section("千束的人设与记忆") {
                TextEditor(text: $personaDraft)
                    .frame(minHeight: 240)
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
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            personaDraft = ChisatoProfile.shared.persona
        }
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
