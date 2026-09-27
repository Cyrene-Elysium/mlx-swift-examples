//
//  ModelManagerView.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 21.04.2025.
//

import SwiftUI

/// 统一的模型类型图标：文本模型显示「文」，视觉模型显示眼睛图标。
/// 模型管理页用它表达类型，取代原来的「文本模型 / 视觉模型」文字注释。
struct ModelIcon: View {
    let model: LMModel

    var body: some View {
        if model.isVisionModel {
            Image(systemName: "eye")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
        } else {
            Text("文")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.tint.opacity(0.14))
                )
        }
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

    /// Download progress fraction for the in-flight download, sampled from the
    /// on-disk byte count (more reliable than the hub's Progress object).
    @State private var downloadFraction: Double = 0

    /// Transfer speed of the in-flight download, in bytes per second.
    @State private var downloadSpeed: Double = 0

    /// Whether to show the download-failure alert.
    @State private var showsDownloadError = false

    /// Models that have already been downloaded to this device, sorted by name.
    private var downloadedModels: [LMModel] {
        MLXService.availableModels
            .filter { downloadedSizes[$0.name] != nil }
            .sorted { Self.modelSort($0, $1) }
    }

    /// Models that are available to download but not yet on this device, sorted by name.
    private var notDownloadedModels: [LMModel] {
        MLXService.availableModels
            .filter { downloadedSizes[$0.name] == nil }
            .sorted { Self.modelSort($0, $1) }
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
            // Continuously sample download progress from on-disk bytes.
            // 1s interval keeps directory enumeration from competing with the
            // download for CPU/IO; speed comes from the byte delta between samples.
            var lastBytes: Int64 = 0
            var lastDate = Date()
            while !Task.isCancelled {
                if let name = MLXService.shared.downloadingModelName,
                    let model = MLXService.availableModels.first(where: {
                        $0.name == name
                    }),
                    let total = model.estimatedSizeBytes
                {
                    let dir = MLXService.downloadDirectory(for: model)
                    let bytes = await MLXService.directorySize(at: dir)
                    let now = Date()
                    let elapsed = now.timeIntervalSince(lastDate)
                    if elapsed > 0.5 {
                        downloadSpeed = Double(bytes - lastBytes) / elapsed
                        lastBytes = bytes
                        lastDate = now
                    }
                    downloadFraction = min(Double(bytes) / Double(total), 1.0)
                } else {
                    downloadFraction = 0
                    downloadSpeed = 0
                    lastBytes = 0
                    lastDate = Date()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .refreshable {
            await refreshDownloadedSizes()
        }
        .onChange(of: MLXService.shared.downloadingModelName) { _, newValue in
            // Refresh the downloaded list once a download finishes or is cancelled.
            if newValue == nil {
                Task { await refreshDownloadedSizes() }
            }
        }
        .onChange(of: MLXService.shared.downloadError) { _, newValue in
            showsDownloadError = newValue != nil
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
            isPresented: $showsDownloadError
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(MLXService.shared.downloadError ?? "")
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

            // Download control (App Store style), right-aligned near the edge
            if isDownloading(model) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(.quaternary, lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: max(downloadFraction, 0.03))
                            .stroke(
                                Color.accentColor,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.3), value: downloadFraction)
                    }
                    .frame(width: 24, height: 24)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(downloadFraction * 100))%")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if downloadSpeed > 1_024 {
                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount: Int64(downloadSpeed),
                                    countStyle: .file) + "/s"
                            )
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        MLXService.shared.cancelDownload()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    )
                )
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
            .spring(response: 0.3, dampingFraction: 0.8),
            value: isDownloading(model)
        )
        .padding(.vertical, 2)
    }

    private func isDownloading(_ model: LMModel) -> Bool {
        MLXService.shared.downloadingModelName == model.name
    }

    // MARK: - Helpers

    /// 模型排序：先按名称升序，名称相同再按体积从小到大。
    private static func modelSort(_ a: LMModel, _ b: LMModel) -> Bool {
        if a.name != b.name { return a.name < b.name }
        return (a.estimatedSizeBytes ?? 0) < (b.estimatedSizeBytes ?? 0)
    }

    private func statusLine(for model: LMModel) -> String {
        if isDownloading(model) {
            return "下载中…"
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
