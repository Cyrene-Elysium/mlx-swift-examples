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

    /// Creates a message view
    /// - Parameter message: The message model to display
    init(
        _ message: Message, showsChisatoAvatar: Bool = false,
        onDelete: ((Message) -> Void)? = nil
    ) {
        self.message = message
        self.showsChisatoAvatar = showsChisatoAvatar
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
                // LocalizedStringKey used to trigger default handling of markdown content.
                Text(LocalizedStringKey(message.content))
                    .textSelection(.enabled)

                // Per-reply generation speed.
                if let speed = message.tokensPerSecond {
                    Text(String(format: "%.1f tokens/s", speed))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
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
