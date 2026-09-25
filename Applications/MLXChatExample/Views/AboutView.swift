//
//  AboutView.swift
//  MLXChatExample
//

import SwiftUI

/// 关于千束的页面：立绘 + 设定介绍 + 应用信息。
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("Chisato")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                VStack(spacing: 8) {
                    Text("天羽千束")
                        .font(.title.bold())
                    Text("あもう ちさと / Amou Chisato")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("寄居在主人机器里的小天使，偶尔会客串堕天使（小恶魔）的一面。")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Divider()

                VStack(spacing: 6) {
                    Label("MLX Chat", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.headline)
                    Text("在本地运行的开源大模型聊天应用")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("关于千束")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
