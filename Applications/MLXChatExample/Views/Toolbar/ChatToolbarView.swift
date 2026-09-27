//
//  ChatToolbarView.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 21.04.2025.
//

import SwiftUI

/// Toolbar view for the chat interface that displays error messages, download progress,
/// generation statistics, and model selection controls. Generation-related toggles
/// (thinking mode, KV-cache quantization) live in Settings to keep this bar uncluttered.
struct ChatToolbarView: View {
    /// View model containing the chat state and controls
    @Bindable var vm: ChatViewModel

    /// Confirm dialog for clearing the conversation.
    @State private var showsClearConfirmation = false

    /// Names of models already downloaded, used to mark them in the picker.
    @State private var downloadedNames: Set<String> = []

    var body: some View {
        // Display error message if present
        if let errorMessage = vm.errorMessage {
            ErrorView(errorMessage: errorMessage)
        }

        // Show download progress for model loading
        if let progress = vm.modelDownloadProgress, !progress.isFinished,
            let name = MLXService.shared.downloadingModelName,
            let model = MLXService.availableModels.first(where: { $0.name == name })
        {
            DownloadProgressView(
                directory: MLXService.downloadDirectory(for: model),
                totalBytes: model.estimatedSizeBytes ?? progress.totalUnitCount)
        }

        // Clear chat history (explicit, with confirmation)
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

        // Model selection picker
        Picker("模型", selection: $vm.selectedModel) {
            ForEach(MLXService.availableModels) { model in
                Text(pickerLabel(for: model))
                    .tag(model)
            }
        }
        .task {
            await refreshDownloadedNames()
        }
        .onChange(of: MLXService.shared.downloadingModelName) { _, newValue in
            if newValue == nil {
                Task { await refreshDownloadedNames() }
            }
        }
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
