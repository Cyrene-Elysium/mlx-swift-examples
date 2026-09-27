//
//  DownloadProgressView.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 21.04.2025.
//

import SwiftUI

/// Floating toolbar icon shown while the selected model downloads. Tapping
/// it presents a sheet with a live progress bar, downloaded/total bytes and
/// transfer speed.
///
/// All figures come from `MLXService.activeDownloads`, which mirrors the hub
/// library's byte-accurate `Progress` object (updated every 100ms) — no
/// on-disk sampling needed.
struct DownloadProgressView: View {
    let modelName: String

    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
        }
        .sheet(isPresented: $isShowing) {
            DownloadProgressSheet(modelName: modelName)
        }
    }
}

/// The sheet content, reading the live download state of the model.
private struct DownloadProgressSheet: View {
    let modelName: String

    @Environment(\.dismiss) private var dismiss

    private var state: MLXService.DownloadState {
        MLXService.shared.activeDownloads[modelName] ?? .init()
    }

    /// The entry disappears once the download finishes or is cancelled.
    private var isFinished: Bool {
        MLXService.shared.activeDownloads[modelName] == nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 12) {
                    if isFinished {
                        Text("下载已结束")
                            .font(.system(.title2, design: .rounded).bold())
                    } else if state.totalBytes > 0 {
                        ProgressView(value: state.fraction)
                        Text("\(Int(state.fraction * 100))%")
                            .font(.system(.title2, design: .rounded).bold())
                            .monospacedDigit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: 280)

                VStack(spacing: 6) {
                    Text(sizeText)
                        .font(.subheadline.monospacedDigit())

                    if !isFinished, state.speed > 1_024 {
                        Text(
                            "速度 "
                                + ByteCountFormatter.string(
                                    fromByteCount: Int64(state.speed),
                                    countStyle: .file
                                ) + "/秒"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }

                Text("模型正在下载，完成后即可开始对话")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("下载中")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var sizeText: String {
        let downloaded = ByteCountFormatter.string(
            fromByteCount: state.completedBytes, countStyle: .file)
        guard state.totalBytes > 0 else { return downloaded }

        let total = ByteCountFormatter.string(
            fromByteCount: state.totalBytes, countStyle: .file)
        return "\(downloaded) / \(total)"
    }
}

#Preview {
    DownloadProgressView(modelName: "qwen3:4b")
}
