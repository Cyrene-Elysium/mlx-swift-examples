//
//  ConversationView.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 20.04.2025.
//

import SwiftUI

/// Displays the chat conversation as a scrollable list of messages.
struct ConversationView: View {
    /// Array of messages to display in the conversation
    let messages: [Message]

    /// Whether this is the dedicated Chisato conversation (shows her avatar).
    let isChisato: Bool

    /// Settings toggle: expand the thinking box while reasoning streams.
    var liveThinkingExpansion: Bool = true

    /// Called when the user deletes a single message.
    var onDelete: ((Message) -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                // System prompts (persona / assistant instructions) are internal
                // and must never be rendered in the conversation.
                ForEach(messages.filter { $0.role != .system }) { message in
                    MessageView(
                        message, showsChisatoAvatar: isChisato,
                        liveThinkingExpansion: liveThinkingExpansion,
                        onDelete: onDelete)
                    .padding(.horizontal, 12)
                }
            }
            // Padding lives inside the scroll content so the first and last
            // messages keep breathing room instead of being clipped against
            // the navigation bar and the prompt bar.
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
    }
}

#Preview {
    // Display sample conversation in preview
    ConversationView(messages: SampleData.conversation, isChisato: false)
}
