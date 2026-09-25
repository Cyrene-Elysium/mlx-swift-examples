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

    var body: some View {
        // Display error message if present
        if let errorMessage = vm.errorMessage {
            ErrorView(errorMessage: errorMessage)
        }

        // Show download progress for model loading
        if let progress = vm.modelDownloadProgress, !progress.isFinished {
            DownloadProgressView(progress: progress)
        }

        // Button to clear chat history, displays generation statistics
        Button {
            vm.clear([.chat, .meta])
        } label: {
            GenerationInfoView(
                tokensPerSecond: vm.tokensPerSecond
            )
        }

        // Thinking mode toggle for models with the /think soft switch
        if vm.selectedModel.supportsThinking {
            Button {
                vm.thinkingEnabled.toggle()
            } label: {
                Image(systemName: vm.thinkingEnabled ? "lightbulb.fill" : "lightbulb")
                    .foregroundStyle(vm.thinkingEnabled ? .tint : .secondary)
            }
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
