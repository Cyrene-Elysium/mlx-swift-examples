//
//  PromptField.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 20.04.2025.
//

import SwiftUI

/// Floating prompt input bar rendered with the Liquid Glass material.
/// The glass background lets conversation content refract through as it
/// scrolls beneath the bar.
struct PromptField: View {
    @Binding var prompt: String
    @State private var task: Task<Void, Never>?

    /// Focus binding for the text field, so the parent can dismiss the
    /// keyboard (on send, or when the conversation is tapped).
    var isInputFocused: FocusState<Bool>.Binding

    let sendButtonAction: () async -> Void
    let mediaButtonAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if let mediaButtonAction {
                Button(action: mediaButtonAction) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            TextField("输入消息", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused(isInputFocused)

            Button {
                if isRunning {
                    task?.cancel()
                    removeTask()
                } else {
                    isInputFocused.wrappedValue = false
                    task = Task {
                        await sendButtonAction()
                        removeTask()
                    }
                }
            } label: {
                Image(systemName: isRunning ? "stop.circle.fill" : "paperplane.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(isRunning ? .cancelAction : .defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlassBackground(in: .rect(cornerRadius: 24))
    }

    private var isRunning: Bool {
        task != nil && !(task!.isCancelled)
    }

    private func removeTask() {
        task = nil
    }
}

#Preview {
    PromptFieldPreview()
}

private struct PromptFieldPreview: View {
    @FocusState private var focused: Bool

    var body: some View {
        VStack {
            Spacer()
            PromptField(prompt: .constant(""), isInputFocused: $focused) {
            } mediaButtonAction: {
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color.gray.opacity(0.3))
    }
}
