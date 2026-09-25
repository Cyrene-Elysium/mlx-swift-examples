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

        // Model selection picker
        Picker("模型", selection: $vm.selectedModel) {
            ForEach(MLXService.availableModels) { model in
                Text(model.displayName)
                    .tag(model)
            }
        }
    }
}
