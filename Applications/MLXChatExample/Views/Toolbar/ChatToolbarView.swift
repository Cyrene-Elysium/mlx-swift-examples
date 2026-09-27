//
//  ChatToolbarView.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 21.04.2025.
//

import SwiftUI

/// Toolbar content for the chat interface: error indicator, download
/// progress for the selected model, and the two conversation-level actions —
/// compressing the context and clearing the history — kept as separate
/// buttons. The live memory readout lives beside the remaining-context figure
/// above the prompt bar (see `MemoryReadout`).
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

/// Compresses the conversation into a summary, freeing context. Disabled
/// while a summarisation is already running.
private struct ChatToolbarSummarizeButton: View {
    @Bindable var vm: ChatViewModel

    var body: some View {
        Button {
            Task { await vm.summarizeConversation() }
        } label: {
            Label("压缩上下文", systemImage: "rectangle.compress.vertical")
        }
        .disabled(vm.isSummarizing)
    }
}

/// Clears the current conversation, after a confirmation.
private struct ChatToolbarClearButton: View {
    @Bindable var vm: ChatViewModel

    @State private var showsClearConfirmation = false

    var body: some View {
        Button(role: .destructive) {
            showsClearConfirmation = true
        } label: {
            Label("删除对话", systemImage: "trash")
        }
        .confirmationDialog(
            "删除当前对话？",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                vm.clear([.chat, .meta])
            }
            Button("取消", role: .cancel) {}
        }
    }
}
