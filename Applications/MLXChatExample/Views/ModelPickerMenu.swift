//
//  ModelPickerMenu.swift
//  MLXChatExample
//
//  Created by 千束 on 27.09.2026.
//

import SwiftUI

/// The model-selection menu content used inside the prompt bar's control
/// menu: downloaded models first (marked ✓), then the rest, each group
/// sorted by name then size. Rendered as a submenu inside `Menu`.
struct ModelPickerMenu: View {
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

#Preview {
    Menu("控制") {
        ModelPickerMenu(
            vm: ChatViewModel(
                mlxService: MLXService(),
                session: ChatSession(
                    modelName: MLXService.availableModels.first!.name,
                    messages: [.system("hi")]),
                store: ChatSessionStore()))
    }
}
