//
//  MessageView.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 20.04.2025.
//

import AVKit
import SwiftUI

/// A view that displays a single message in the chat interface.
/// Supports different message roles (user, assistant, system) and media attachments.
struct MessageView: View {
    /// The message to be displayed
    let message: Message

    /// Whether to show the Chisato avatar next to assistant messages
    /// (only in the dedicated Chisato conversation).
    let showsChisatoAvatar: Bool

    /// Called when the user chooses to delete this message. nil disables the
    /// delete action.
    let onDelete: ((Message) -> Void)?

    /// Whether the thinking box expands while reasoning streams in. Mirrors
    /// the Settings toggle so already-rendered messages react to it too.
    var liveThinkingExpansion: Bool = true

    /// Creates a message view
    /// - Parameter message: The message model to display
    init(
        _ message: Message, showsChisatoAvatar: Bool = false,
        liveThinkingExpansion: Bool = true,
        onDelete: ((Message) -> Void)? = nil
    ) {
        self.message = message
        self.showsChisatoAvatar = showsChisatoAvatar
        self.liveThinkingExpansion = liveThinkingExpansion
        self.onDelete = onDelete
    }

    var body: some View {
        Group {
            switch message.role {
            case .user:
                userMessage
            case .assistant:
                assistantMessage
            case .system:
                systemMessage
            }
        }
        .contextMenu {
            if let onDelete {
                Button(role: .destructive) {
                    onDelete(message)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private var userMessage: some View {
        // User messages are right-aligned with blue background
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                // Display first image if present
                if let firstImage = message.images.first {
                    AsyncImage(url: firstImage) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxWidth: 250, maxHeight: 200)
                    .clipShape(.rect(cornerRadius: 12))
                }

                // Display first video if present
                if let firstVideo = message.videos.first {
                    VideoPlayer(player: AVPlayer(url: firstVideo))
                        .frame(width: 250, height: 340)
                        .clipShape(.rect(cornerRadius: 12))
                }

                // Message content with tinted background.
                // LocalizedStringKey used to trigger default handling of markdown content.
                Text(LocalizedStringKey(message.content))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .foregroundStyle(.white)
                    .background(.tint, in: .rect(cornerRadius: 16))
                    .textSelection(.enabled)
            }
        }
    }

    private var assistantMessage: some View {
        // Assistant messages are left-aligned; the Chisato avatar appears
        // only in the dedicated Chisato conversation.
        HStack(alignment: .top, spacing: 8) {
            if showsChisatoAvatar {
                Image("ChisatoAvatar")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 6) {
                // Reasoning trace gets its own collapsible box so the answer
                // below reads clean. Auto-expands while it streams, auto-
                // collapses once the answer starts (unless the user disabled
                // live expansion in Settings). Only rendered when there is
                // real reasoning to show — a model that answers straight away
                // must not get an empty "推理完成" bar.
                if message.hasThinkingTrace {
                    ThinkingBox(message: message, liveExpansion: liveThinkingExpansion)
                }

                // LocalizedStringKey used to trigger default handling of markdown content.
                Text(LocalizedStringKey(message.content))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                // Per-reply generation speed.
                if let speed = message.tokensPerSecond {
                    Text(String(format: "%.1f tokens/s", speed))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.trailing, 8)
    }

    private var systemMessage: some View {
        // System messages are centered with computer icon
        Label(message.content, systemImage: "desktopcomputer")
            .font(.headline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    VStack(spacing: 20) {
        MessageView(.system("You are a helpful assistant."))

        MessageView(
            .user(
                "Here's a photo",
                images: [URL(string: "https://picsum.photos/200")!]
            )
        )

        MessageView(.assistant("I see your photo!"))
    }
    .padding()
}

/// Collapsible box holding a reply's reasoning trace.
///
/// While the model is still thinking the box can auto-expand so the user can
/// watch it work; as soon as the answer starts it collapses to a one-line
/// summary. When live expansion is disabled in Settings, it stays collapsed
/// and shows only the status line ("正在思考" / "思考完成").
struct ThinkingBox: View {
    let message: Message

    /// Settings toggle: expand while reasoning is streaming.
    let liveExpansion: Bool

    /// User's manual override, applied on top of the automatic behaviour.
    @State private var manualExpanded: Bool?

    private var isStreaming: Bool {
        !message.thinkingFinished && message.hasThinkingTrace
    }

    /// Auto state: expanded while thinking (if allowed), collapsed after.
    private var autoExpanded: Bool {
        isStreaming && liveExpansion
    }

    private var isExpanded: Bool {
        manualExpanded ?? autoExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    manualExpanded = !isExpanded
                }
            } label: {
                HStack(spacing: 6) {
                    // Three-star glyph, shared with the prompt bar's reasoning
                    // toggle so the two read as the same control.
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(isStreaming ? Color.accentColor : .secondary)
                        .symbolEffect(.variableColor.iterative, isActive: isStreaming)
                    Text(statusText)
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && message.hasThinkingTrace {
                Divider().padding(.vertical, 6)
                Text(message.thinking)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: message.thinkingFinished)
    }

    private var statusText: String {
        if isStreaming { return "正在推理" }
        return "推理完成"
    }
}
