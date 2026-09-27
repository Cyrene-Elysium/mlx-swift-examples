//
//  ChatToolbarView.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 21.04.2025.
//

import SwiftUI

/// Toolbar content for the chat interface: error indicator, download
/// progress for the selected model, clear-conversation, and model selection —
/// each as its own item so they sit as separate buttons. Generation-related
/// toggles (thinking mode, KV-cache quantization) live in Settings to keep
/// this bar uncluttered.
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
            ChatToolbarClearButton(vm: vm)
        }

        ToolbarItem(placement: .primaryAction) {
            ChatToolbarModelPicker(vm: vm)
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

/// Model selection picker: downloaded models first (marked with ✓), then the
/// rest, each group sorted by name then size.
private struct ChatToolbarModelPicker: View {
    @Bindable var vm: ChatViewModel

    /// Names of models already downloaded, used to mark them in the picker.
    @State private var downloadedNames: Set<String> = []

    var body: some View {
        Picker("模型", selection: $vm.selectedModel) {
            ForEach(sortedModels) { model in
                Text(pickerLabel(for: model))
                    .tag(model)
            }
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

    /// 模型选择器的显示文字：类型标注 + 已下载打勾。
    private func pickerLabel(for model: LMModel) -> String {
        let kind = model.isVisionModel ? "视觉" : "文本"
        let check = downloadedNames.contains(model.name) ? " ✓" : ""
        return "\(model.displayName)（\(kind)）\(check)"
    }

    /// 查询已下载的模型名集合。
    private func refreshDownloadedNames() async {
        var names = Set<String>()
        for model in MLXService.availableModels where MLXService.shared.isDownloaded(model) {
            names.insert(model.name)
        }
        downloadedNames = names
    }
}
