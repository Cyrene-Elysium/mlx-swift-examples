//
//  ChatToolbarView.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 21.04.2025.
//

import SwiftUI

/// Toolbar view for the chat interface that displays error messages, download progress,
/// generation statistics, and model selection controls.
struct ChatToolbarView: View {
    /// View model containing the chat state and controls
    @Bindable var vm: ChatViewModel

    /// Confirm dialog for clearing the conversation.
    @State private var showsClearConfirmation = false

    /// Persona editor presentation.
    @State private var showsPersonaEditor = false

    var body: some View {
        // Display error message if present
        if let errorMessage = vm.errorMessage {
            ErrorView(errorMessage: errorMessage)
        }

        // Show download progress for model loading
        if let progress = vm.modelDownloadProgress, !progress.isFinished {
            DownloadProgressView(progress: progress)
        }

        // Generation statistics (read-only display)
        GenerationInfoView(tokensPerSecond: vm.tokensPerSecond)

        // Clear chat history (explicit, with confirmation)
        Button {
            showsClearConfirmation = true
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(Color.secondary)
        }
        .confirmationDialog(
            "清空当前对话？",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                vm.clear([.chat, .meta])
            }
            Button("取消", role: .cancel) {}
        }

        // Thinking mode toggle for models with the /think soft switch
        if vm.selectedModel.supportsThinking {
            Button {
                vm.thinkingEnabled.toggle()
            } label: {
                Image(systemName: vm.thinkingEnabled ? "lightbulb.fill" : "lightbulb")
                    .foregroundStyle(
                        vm.thinkingEnabled ? Color.accentColor : Color.secondary)
            }
        }

        // KV-cache quantization toggle (8-bit) to save memory on long chats
        Button {
            vm.kvCacheQuantized.toggle()
        } label: {
            Image(systemName: "memorychip")
                .foregroundStyle(
                    vm.kvCacheQuantized ? Color.accentColor : Color.secondary)
        }

        // Edit Chisato persona (only in the dedicated Chisato conversation)
        if vm.session.isChisato {
            Button {
                showsPersonaEditor = true
            } label: {
                Image(systemName: "person.text.rectangle")
                    .foregroundStyle(Color.accentColor)
            }
        }

        // Model selection picker
        Picker("模型", selection: $vm.selectedModel) {
            ForEach(MLXService.availableModels) { model in
                Text(model.displayName)
                    .tag(model)
            }
        }
        .sheet(isPresented: $showsPersonaEditor) {
            ChisatoPersonaEditor(vm: vm)
        }
    }
}

/// Editor for the Chisato persona and memories, with a reset-to-default action.
struct ChisatoPersonaEditor: View {
    @Bindable var vm: ChatViewModel

    @State private var draft: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("千束的人设与记忆") {
                    TextEditor(text: $draft)
                        .frame(minHeight: 200)
                }

                Section {
                    Button("恢复初始化状态", role: .destructive) {
                        vm.updateChisatoPersona("")
                        dismiss()
                    }
                } footer: {
                    Text("恢复后，千束会回到默认的人设与记忆。")
                }
            }
            .navigationTitle("编辑千束")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        vm.updateChisatoPersona(draft)
                        dismiss()
                    }
                }
            }
            .onAppear {
                draft = ChisatoProfile.shared.persona
            }
        }
    }
}
