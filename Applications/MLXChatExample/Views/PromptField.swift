//
//  PromptField.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 20.04.2025.
//

import SwiftUI

/// Floating prompt input bar rendered with the Liquid Glass material.
/// The glass background lets conversation content refract through as it
/// scrolls beneath the bar. The bar keeps a capsule silhouette — the shape
/// it has always had — rather than a rounded rectangle, so the ends stay
/// fully semicircular.
///
/// Above the bar sit two separate elements, as requested: the leading glass
/// control button (model selection + thinking toggle) on the left, and a
/// plain grey remaining-context readout on the right.
struct PromptField: View {
    @Binding var prompt: String
    @State private var task: Task<Void, Never>?

    /// Focus binding for the text field, so the parent can dismiss the
    /// keyboard (on send, or when the conversation is tapped).
    var isInputFocused: FocusState<Bool>.Binding

    /// View model providing the model selection and thinking toggle surfaced
    /// in the leading control menu.
    @Bindable var vm: ChatViewModel

    let sendButtonAction: () async -> Void
    let mediaButtonAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            // Row above the bar: leading glass control menu, trailing plain
            // context readout. Deliberately outside the capsule so the bar
            // itself stays a clean input strip.
            HStack(spacing: 8) {
                Menu {
                    Section {
                        ModelPickerMenu(vm: vm)
                    }

                    if vm.selectedModel.supportsThinking {
                        Section {
                            Toggle("推理模式", isOn: $vm.thinkingEnabled)
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.2")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .glassEffect(.regular.interactive(), in: .capsule)

                Spacer(minLength: 0)

                // Grey, chrome-free readout. Recomputed only when a reply
                // finishes (see ChatViewModel.settledRemainingTokens), not on
                // every streamed chunk.
                Text("剩余上下文 · 约 \(vm.settledRemainingTokens) token")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 12) {
                if let mediaButtonAction {
                    Button(action: mediaButtonAction) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title3)
                            .foregroundStyle(.tint)
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
                    // iMessage-style send button: raised arrow while composing,
                    // stop sign while a reply is streaming. No glass here —
                    // the tinted glyph is the whole control.
                    Image(
                        systemName: isRunning
                            ? "stop.circle.fill" : "arrow.up.circle.fill"
                    )
                    .font(.title2)
                    .foregroundStyle(
                        isRunning || canSend
                            ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!isRunning && !canSend)
                .keyboardShortcut(isRunning ? .cancelAction : .defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // Capsule silhouette: both ends fully semicircular, exactly as the
            // bar looked before the concentric-rounded-rectangle experiment.
            .interactiveCapsuleGlassBackground()
        }
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
