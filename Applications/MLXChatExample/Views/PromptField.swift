//
//  PromptField.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 20.04.2025.
//

import SwiftUI

/// Floating prompt input bar rendered with the Liquid Glass material.
/// The glass background lets conversation content refract through as it
/// scrolls beneath the bar, and follows the device's screen corner
/// curvature (`ConcentricRectangle`) with an interactive press highlight.
///
/// The leading control menu holds what used to sit in the top toolbar and
/// the strip above the bar: model selection, the thinking toggle, and the
/// remaining-context readout.
struct PromptField: View {
    @Binding var prompt: String
    @State private var task: Task<Void, Never>?

    /// Focus binding for the text field, so the parent can dismiss the
    /// keyboard (on send, or when the conversation is tapped).
    var isInputFocused: FocusState<Bool>.Binding

    /// View model providing the model selection, thinking toggle and
    /// context readout surfaced in the control menu.
    @Bindable var vm: ChatViewModel

    let sendButtonAction: () async -> Void
    let mediaButtonAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Control menu: model selection (submenu), thinking mode, and
            // the remaining-context readout — all tucked into the bar.
            Menu {
                Section {
                    ModelPickerMenu(vm: vm)
                }

                if vm.selectedModel.supportsThinking {
                    Section {
                        Toggle("思考模式", isOn: $vm.thinkingEnabled)
                    }
                }

                Section {
                    Label(
                        "剩余上下文 · 约 \(vm.remainingTokens) token",
                        systemImage: "chart.bar.doc.horizontal"
                    )
                    .foregroundStyle(.secondary)
                }
            } label: {
                Image(systemName: "slider.horizontal.2")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.glass)

            if let mediaButtonAction {
                Button(action: mediaButtonAction) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.glass)
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
                // iMessage-style send button: raised arrow while composing,
                // stop sign while a reply is streaming.
                Image(
                    systemName: isRunning
                        ? "stop.circle.fill" : "arrow.up.circle.fill"
                )
                .font(.title2)
                .foregroundStyle(
                    isRunning || canSend
                        ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.glass)
            .disabled(!isRunning && !canSend)
            .keyboardShortcut(isRunning ? .cancelAction : .defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .concentricInteractiveGlassBackground()
    }

    /// Whether the prompt has content worth sending (enables the send button).
    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            PromptField(
                prompt: .constant(""),
                isInputFocused: $focused,
                vm: ChatViewModel(
                    mlxService: MLXService(),
                    session: ChatSession(
                        modelName: MLXService.availableModels.first!.name,
                        messages: [.system("hi")]),
                    store: ChatSessionStore())
            ) {
            } mediaButtonAction: {
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color.gray.opacity(0.3))
    }
}
