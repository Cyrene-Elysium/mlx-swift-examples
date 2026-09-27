//
//  ChatToolbarView.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 21.04.2025.
//

import SwiftUI

/// Toolbar content for the chat interface: error indicator, download
/// progress for the selected model, summarize-context, and clear-conversation.
/// Model selection and the thinking toggle moved into the prompt bar's
/// control menu; generation-related defaults live in Settings.
///
/// `ToolbarContent` bodies are not main-actor isolated, so every conditional
/// lives inside a small subview (whose `body` is).
struct ChatToolbarView: ToolbarContent {
    @Bindable var vm: ChatViewModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ChatToolbarErrorItem(vm: vm)
        }

        ToolbarItem(placement: .primaryAction) {
            ChatToolbarDownloadItem(vm: vm)
        }

        ToolbarItem(placement: .primaryAction) {
            ChatToolbarSummarizeButton(vm: vm)
        }

        ToolbarItem(placement: .primaryAction) {
            ChatToolbarClearButton(vm: vm)
        }
    }
}

/// Error indicator for the current conversation, shown when present.
private struct ChatToolbarErrorItem: View {
    let vm: ChatViewModel

    var body: some View {
        if let errorMessage = vm.errorMessage {
            ErrorView(errorMessage: errorMessage)
        }
    }
}

/// Download progress for the selected model, shown while it is downloading.
private struct ChatToolbarDownloadItem: View {
    let vm: ChatViewModel

    var body: some View {
        if MLXService.shared.activeDownloads[vm.selectedModel.name] != nil {
            DownloadProgressView(modelName: vm.selectedModel.name)
        }
    }
}

/// Summarize (compress) the conversation context on demand.
private struct ChatToolbarSummarizeButton: View {
    @Bindable var vm: ChatViewModel

    var body: some View {
        Button {
            Task { await vm.summarizeConversation() }
        } label: {
            Image(systemName: "rectangle.compress.vertical")
                .foregroundStyle(.tint)
        }
        .disabled(vm.isSummarizing)
    }
}

/// Clear chat history (explicit, with confirmation), as its own toolbar item.
private struct ChatToolbarClearButton: View {
    @Bindable var vm: ChatViewModel

    @State private var showsClearConfirmation = false

    var body: some View {
        Button {
            showsClearConfirmation = true
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(.red)
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
    }
}
