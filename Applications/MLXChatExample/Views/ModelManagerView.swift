//
//  ModelManagerView.swift
//  MLXChatExample
//

import SwiftUI

/// Lists all available models with their download status and on-disk size,
/// lets the user delete downloaded model files to reclaim space, and
/// selects the model used for new chats.
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

    var body: some View {
        List {
            ForEach(MLXService.availableModels) { model in
                modelRow(model)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if downloadedSizes[model.name] != nil {
                            Button(role: .destructive) {
                                modelPendingDeletion = model
                                showsDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
            }

            if !downloadedSizes.isEmpty {
                Section {
                    totalUsageRow
                }
            }
        }
        .navigationTitle("Models")
        .task {
            await refreshDownloadedSizes()
        }
        .refreshable {
            await refreshDownloadedSizes()
        }
        .confirmationDialog(
            "Delete downloaded model?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "Delete \(modelPendingDeletion?.name ?? "") downloads",
                role: .destructive
            ) {
                performDeletion()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes the model files from this device. "
                    + "The model will be downloaded again the next time it is used."
            )
        }
        .alert(
            "Delete Failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Rows

    private func modelRow(_ model: LMModel) -> some View {
        Button {
            store.defaultModelName = model.name
        } label: {
            HStack(spacing: 12) {
                Image(
                    systemName: model.isVisionModel
                        ? "eye" : "character.textbox"
                )
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(statusLine(for: model))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if store.defaultModelName == model.name {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
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
            Label("Downloads", systemImage: "internaldrive")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private func statusLine(for model: LMModel) -> String {
        if let size = downloadedSizes[model.name] {
            "Downloaded · "
                + ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else if model.isVisionModel {
            "Vision · not downloaded"
        } else {
            "Not downloaded"
        }
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
