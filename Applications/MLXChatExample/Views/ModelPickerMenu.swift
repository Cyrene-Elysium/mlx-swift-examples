//
//  ModelPickerMenu.swift
//  MLXChatExample
//
//  Created by 千束 on 27.09.2026.
//

import SwiftUI

/// The model-selection menu content used inside the prompt bar's control
/// menu: downloaded models first, then the rest, each group sorted by name
/// then size.
///
/// The two markers are deliberately distinct so they can't be confused:
/// * a small filled dot *before* the name means "downloaded to this device";
/// * the system checkmark *after* the name means "currently selected"
///   (rendered by `Picker` for the selected row).
struct ModelPickerMenu: View {
    @Bindable var vm: ChatViewModel

    /// Names of models already downloaded, used to mark them in the picker.
    @State private var downloadedNames: Set<String> = []

    var body: some View {
        Picker("模型", selection: $vm.selectedModel) {
            ForEach(sortedModels) { model in
                downloadedNames.contains(model.name)
                    ? Text(
                        "● \(pickerLabel(for: model))"
                    ).tag(model)
                    : Text(pickerLabel(for: model)).tag(model)
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

    /// 模型选择器的显示文字：名称 + 类型标注。已下载标识由调用方在名称前
    /// 用圆点表达，选中标识由 Picker 在名称右侧画对勾——两者互不干扰。
    private func pickerLabel(for model: LMModel) -> String {
        let kind = model.isVisionModel ? "视觉" : "文本"
        return "\(model.displayName)（\(kind)）"
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
