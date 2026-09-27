//
//  ModelManagerView.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 21.04.2025.
//

import SwiftUI

/// 统一的模型类型图标：文本模型显示「文」，视觉模型显示眼睛图标。
/// 模型管理页用它表达类型，取代原来的「文本模型 / 视觉模型」文字注释。
/// SF Symbol 与汉字的光学尺寸不同（symbol 有内建留白，汉字满框），
/// 两者钉在不同的字号上让视觉高度一致。
struct ModelIcon: View {
    let model: LMModel

    var body: some View {
        ZStack {
            if model.isVisionModel {
                Image(systemName: "eye")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.tint)
            } else {
                Text("文")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 28, height: 28)
    }
}

/// Lists all available models grouped by download state, lets the user delete
/// downloaded model files to reclaim space, and selects the model used for new
/// chats. Uses the iOS 27 Liquid Glass system materials via `.insetGrouped`.
struct ModelManagerView: View {
    @Bindable var store: ChatSessionStore

    /// Downloaded size per model name, computed asynchronously.
    @State private var downloadedSizes: [String: Int64] = [:]

    /// Model pending delete confirmation.
    @State private var modelPendingDeletion: LMModel?

    /// Delete confirmation visibility.
    @State private var showsDeleteConfirmation = false

    /// Error message shown when deletion fails.
    @State private var errorMessage: String?

    /// Error message from a failed model download, presented as an alert.
    @State private var downloadErrorMessage: String?

    /// Models that have already been downloaded to this device, sorted by name.
    private var downloadedModels: [LMModel] {
        MLXService.availableModels
            .filter { downloadedSizes[$0.name] != nil }
            .sorted { LMModel.listSort($0, $1) }
    }

    /// Models that are available to download but not yet on this device, sorted by name.
    private var notDownloadedModels: [LMModel] {
        MLXService.availableModels
            .filter { downloadedSizes[$0.name] == nil }
            .sorted { LMModel.listSort($0, $1) }
    }

    var body: some View {
        List {
            if !downloadedModels.isEmpty {
                Section("已下载") {
                    ForEach(downloadedModels) { model in
                        modelRow(model)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    modelPendingDeletion = model
                                    showsDeleteConfirmation = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            Section(downloadedModels.isEmpty ? "可用模型" : "更多模型") {
                ForEach(notDownloadedModels) { model in
                    modelRow(model)
                }
            }

            if !downloadedSizes.isEmpty {
                Section("存储") {
                    totalUsageRow
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("模型")
        .task {
            await refreshDownloadedSizes()
        }
        .refreshable {
            await refreshDownloadedSizes()
        }
        .onChange(of: MLXService.shared.activeDownloads) { old, new in
            // A download finished (or was cancelled) when an entry disappears:
            // re-scan which models are now on disk.
            if old.count > new.count {
                Task { await refreshDownloadedSizes() }
            }
        }
        .onChange(of: MLXService.shared.downloadErrors) { old, new in
            for (name, message) in new where old[name] == nil {
                downloadErrorMessage = "\(name)：\(message)"
            }
        }
        .confirmationDialog(
            "删除已下载的模型？",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "删除 \(modelPendingDeletion?.name ?? "") 的模型文件",
                role: .destructive
            ) {
                performDeletion()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                "将从本机删除该模型的文件，"
                    + "下次使用时会重新下载。"
            )
        }
        .alert(
            "下载失败",
            isPresented: Binding(
                get: { downloadErrorMessage != nil },
                set: { if !$0 { downloadErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(downloadErrorMessage ?? "")
        }
        .alert(
            "删除失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var totalUsageRow: some View {
        LabeledContent {
            Text(
                ByteCountFormatter.string(
                    fromByteCount: downloadedSizes.values.reduce(0, +),
                    countStyle: .file
                )
            )
        } label: {
            Label("已用空间", systemImage: "internaldrive")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // MARK: - Rows

    private func modelRow(_ model: LMModel) -> some View {
        HStack(spacing: 12) {
            ModelIcon(model: model)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.headline)

                Text(statusLine(for: model))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Download control (App Store style): the ring stays pinned where
            // the download button was; the cancel button pops out to its left.
            if let dl = MLXService.shared.activeDownloads[model.name] {
                HStack(spacing: 10) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(dl.fraction * 100))%")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if dl.speed > 1_024 {
                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount: Int64(dl.speed),
                                    countStyle: .file) + "/s"
                            )
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 64, alignment: .trailing)

                    Button {
                        MLXService.shared.cancelDownload(of: model)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))

                    ZStack {
                        Circle()
                            .stroke(.quaternary, lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: max(dl.fraction, 0.03))
                            .stroke(
                                Color.accentColor,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.2), value: dl.fraction)
                    }
                    .frame(width: 24, height: 24)
                }
                .transition(.opacity)
            } else if downloadedSizes[model.name] == nil {
                Button {
                    MLXService.shared.downloadModel(model)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(
            .spring(response: 0.35, dampingFraction: 0.75),
            value: MLXService.shared.activeDownloads[model.name] != nil
        )
        .padding(.vertical, 2)
        // Align every row's separator with the text column so the dividers
        // form one straight line instead of following each row's content.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 40 }
    }

    // MARK: - Helpers

    private func statusLine(for model: LMModel) -> String {
        if let dl = MLXService.shared.activeDownloads[model.name] {
            let done = ByteCountFormatter.string(
                fromByteCount: dl.completedBytes, countStyle: .file)
            let total = ByteCountFormatter.string(
                fromByteCount: dl.totalBytes, countStyle: .file)
            return dl.totalBytes > 0 ? "下载中 · \(done) / \(total)" : "下载中…"
        }
        if let size = downloadedSizes[model.name] {
            return "已下载 · "
                + ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }

        if let estimate = model.estimatedSizeBytes {
            let size = ByteCountFormatter.string(
                fromByteCount: estimate, countStyle: .file)
            return "未下载 · 约 \(size)"
        }
        return "未下载"
    }

    private func refreshDownloadedSizes() async {
        var sizes: [String: Int64] = [:]
        let service = MLXService.shared

        for model in MLXService.availableModels where service.isDownloaded(model) {
            let size = await MLXService.directorySize(
                at: MLXService.downloadDirectory(for: model))
            sizes[model.name] = size
        }

        downloadedSizes = sizes
    }

    private func performDeletion() {
        guard let model = modelPendingDeletion else { return }

        do {
            try MLXService.shared.deleteDownloaded(model)
            downloadedSizes[model.name] = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        modelPendingDeletion = nil
    }
}

#Preview {
    NavigationStack {
        ModelManagerView(store: ChatSessionStore())
    }
}
