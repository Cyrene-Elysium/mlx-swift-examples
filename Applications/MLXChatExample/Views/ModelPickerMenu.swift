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
/// Built from plain `Button`s rather than a `Picker`. A `Picker` in a menu
/// always draws its selection checkmark at the *leading* edge of the row, so
/// pairing it with a "downloaded" bullet produced a cluttered
/// `✓ ● Name` prefix on the selected row while every other row was `● Name` —
/// the two markers collided and nothing lined up. Drawing both markers by
/// hand keeps them on opposite sides:
/// * a small filled dot *before* the name means "downloaded to this device";
/// * a checkmark *after* the name means "currently selected".
struct ModelPickerMenu: View {
    @Bindable var vm: ChatViewModel

    /// Names of models already downloaded, used to mark them in the list.
    @State private var downloadedNames: Set<String> = []

    var body: some View {
        ForEach(sortedModels) { model in
            Button {
                vm.selectedModel = model
            } label: {
                HStack(spacing: 6) {
                    if downloadedNames.contains(model.name) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                    }

                    Text(label(for: model))

                    if model.id == vm.selectedModel.id {
                        Spacer(minLength: 8)
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.semibold))
                    }
                }
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

    /// 模型显示文字：名称 + 类型标注。两个标记分别由圆点（前）和对勾（后）
    /// 表达，互不干扰。
    private func label(for model: LMModel) -> String {
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
