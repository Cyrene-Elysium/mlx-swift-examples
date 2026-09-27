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
            // Row above the bar: the plain context/memory readouts sit on the
            // leading side and the two glass chips (reasoning toggle, model
            // menu) trail the edge. Deliberately outside the capsule so the
            // bar itself stays a clean input strip.
            HStack(spacing: 8) {
                // Reasoning toggle as its own glass button — three stars.
                // Only meaningful for models that reason.
                //
                // On-state uses a *neutral, brighter* surface rather than a
                // tinted one: tinting the glass blue while the glyph was also
                // blue produced blue-on-blue, which read as a dim smudge
                // instead of a lit control. A brighter fill plus a white glyph
                // and a small dot indicator makes the state unmistakable
                // regardless of the accent colour.
                if vm.selectedModel.supportsThinking {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            vm.thinkingEnabled.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                            if vm.thinkingEnabled {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                            }
                        }
                        .foregroundStyle(vm.thinkingEnabled ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule())
                    .glassEffect(
                        vm.thinkingEnabled
                            ? .regular.tint(.white).interactive()
                            : .regular.interactive(),
                        in: .capsule)
                    .accessibilityLabel("推理模式")
                    .accessibilityValue(vm.thinkingEnabled ? "已开启" : "已关闭")
                }

                // Grey, chrome-free readouts. The context figure recomputes
                // only when a reply finishes (see
                // ChatViewModel.settledRemainingTokens); the memory figure
                // refreshes on its own two-second cadence.
                VStack(alignment: .trailing, spacing: 1) {
                    Text("剩余上下文 · 约 \(vm.settledRemainingTokens) token")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    MemoryReadout()
                }

                Spacer(minLength: 0)

                // Model-selection menu, on the trailing side next to the
                // readouts so the chips read right-to-left from the edge.
                Menu {
                    // No `Section` wrapper: a Section in a menu draws its own
                    // separator with an inset that does not line up with the
                    // item text, which made the divider look misaligned.
                    ModelPickerMenu(vm: vm)
                } label: {
                    // The glyph must stay legible on top of the frosted glass:
                    // a plain `.tint` fill lost all contrast against the dark
                    // background and the button read as an empty pill.
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityLabel("选择模型")
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

/// Live resident-memory readout, refreshed every two seconds. Shows the
/// kernel's physical footprint — the figure the system jetsams on — in a
/// compact, secondary style so it reads as instrumentation, not a control.
/// Lives beside the remaining-context figure above the prompt bar.
struct MemoryReadout: View {
    @State private var bytes: Int64 = 0

    /// Two-second cadence for the readout.
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatted)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .onAppear { refresh() }
            .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        bytes = MLXService.residentMemoryBytes()
    }

    private var formatted: String {
        guard bytes > 0 else { return "—" }
        return "内存 " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
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
