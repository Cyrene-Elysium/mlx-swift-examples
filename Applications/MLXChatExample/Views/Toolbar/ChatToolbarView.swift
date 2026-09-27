//
//  ChatToolbarView.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 21.04.2025.
//

import SwiftUI

/// Toolbar content for the chat interface: error indicator, download
/// progress for the selected model, a "more" menu (compress / clear), and a
/// live memory readout. Model selection and the thinking toggle live in the
/// prompt bar's leading menu; generation-related defaults live in Settings.
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
            ChatToolbarMemoryReadout()
        }

        ToolbarItem(placement: .primaryAction) {
            ChatToolbarMoreMenu(vm: vm)
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

/// Live resident-memory readout, refreshed every two seconds. Shows the
/// kernel's physical footprint — the figure the system jetsams on — in a
/// compact, secondary style so it reads as instrumentation, not a control.
private struct ChatToolbarMemoryReadout: View {
    @State private var bytes: Int64 = 0

    /// Two-second cadence for the readout.
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatted)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .onAppear { refresh() }
            .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        bytes = MLXService.residentMemoryBytes()
    }

    private var formatted: String {
        guard bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}

/// Overflow menu holding the conversation-level actions (compress context,
/// clear history) that used to occupy their own toolbar buttons.
private struct ChatToolbarMoreMenu: View {
    @Bindable var vm: ChatViewModel

    @State private var showsClearConfirmation = false

    var body: some View {
        Menu {
            Button {
                Task { await vm.summarizeConversation() }
            } label: {
                Label("压缩上下文", systemImage: "rectangle.compress.vertical")
            }
            .disabled(vm.isSummarizing)

            Button(role: .destructive) {
                showsClearConfirmation = true
            } label: {
                Label("清空对话", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.tint)
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
