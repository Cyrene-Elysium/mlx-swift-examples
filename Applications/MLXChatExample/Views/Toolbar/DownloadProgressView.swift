//
//  DownloadProgressView.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 21.04.2025.
//

import SwiftUI

/// Floating toolbar icon shown while a model downloads. Tapping it presents a
/// sheet with a live progress bar, downloaded/total bytes and transfer speed.
///
/// The `Progress` object advances continuously but is not `Observable`, so the
/// sheet samples it on a timer and renders the sampled values via its own
/// `@State` (which reliably re-renders the sheet). A popover was tried before
/// and did not refresh reliably.
struct DownloadProgressView: View {
    let progress: Progress

    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
        }
        .sheet(isPresented: $isShowing) {
            DownloadProgressSheet(progress: progress)
        }
    }
}

/// The sheet content, sampling `progress` on a timer.
private struct DownloadProgressSheet: View {
    let progress: Progress

    @State private var sampledBytes: Int64 = 0
    @State private var bytesPerSecond: Double = 0
    @Environment(\.dismiss) private var dismiss

    private let sampleInterval: UInt64 = 500_000_000  // 0.5 s

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 12) {
                    if progress.totalUnitCount > 0 {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }

                    if progress.totalUnitCount > 0 {
                        Text("\(Int(fraction * 100))%")
                            .font(.system(.title2, design: .rounded).bold())
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: 280)

                VStack(spacing: 6) {
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

    private var fraction: Double {
        guard progress.totalUnitCount > 0 else { return 0 }
        return Double(sampledBytes) / Double(progress.totalUnitCount)
    }

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
