//
//  DownloadProgressView.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 21.04.2025.
//

import SwiftUI

/// Floating toolbar icon shown while a model downloads. Tapping it presents a
/// popover with a live progress bar, downloaded/total bytes and transfer speed.
struct DownloadProgressView: View {
    let progress: Progress

    @State private var isShowingDownload = false

    var body: some View {
        Button {
            isShowingDownload = true
        } label: {
            Image(systemName: "arrow.down.square")
                .foregroundStyle(.tint)
        }
        .popover(isPresented: $isShowingDownload, arrowEdge: .bottom) {
            DownloadProgressPopover(progress: progress)
        }
    }
}

/// The popover content. It owns the sampling `@State` and the timer task, so it
/// refreshes itself as the `Progress` advances. Keeping the timer inside the
/// presented view (rather than on the outer toolbar button) matters because a
/// SwiftUI popover is an independent presentation that does not reliably
/// re-render when only the presenting view's state changes.
private struct DownloadProgressPopover: View {
    let progress: Progress

    @State private var sampledBytes: Int64 = 0
    @State private var bytesPerSecond: Double = 0

    private let sampleInterval: UInt64 = 500_000_000  // 0.5 s

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if progress.totalUnitCount > 0 {
                    ProgressView(value: progress.fractionCompleted)
                } else {
                    // Total size unknown yet - show an indeterminate bar.
                    ProgressView()
                }
            }
            .frame(width: 240)

            VStack(spacing: 4) {
                Text(sizeText)
                    .font(.subheadline.monospacedDigit())

                if bytesPerSecond > 1_024 {
                    Text(
                        "速度 "
                            + ByteCountFormatter.string(
                                fromByteCount: Int64(bytesPerSecond),
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
                .padding(.horizontal, 16)
        }
        .padding()
        .task {
            var lastBytes = Int64(0)
            var lastDate = Date()

            while !Task.isCancelled {
                let now = Date()
                let bytes = progress.completedUnitCount
                let elapsed = now.timeIntervalSince(lastDate)

                if elapsed > 0.2 {
                    bytesPerSecond = Double(bytes - lastBytes) / elapsed
                    lastBytes = bytes
                    lastDate = now
                }

                sampledBytes = bytes
                try? await Task.sleep(nanoseconds: sampleInterval)
            }
        }
    }

    /// "123 MB / 4.6 GB", or just the downloaded size when the total is unknown.
    private var sizeText: String {
        let downloaded = ByteCountFormatter.string(
            fromByteCount: sampledBytes, countStyle: .file)
        guard progress.totalUnitCount > 0 else { return downloaded }

        let total = ByteCountFormatter.string(
            fromByteCount: progress.totalUnitCount, countStyle: .file)
        return "\(downloaded) / \(total)"
    }
}

#Preview {
    DownloadProgressView(progress: Progress(totalUnitCount: 6))
}
