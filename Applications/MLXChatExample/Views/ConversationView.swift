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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(messages) { message in
                    MessageView(message)
                        .padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 8)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .background {
            // Faint Chisato watermark so the illustration stays present but
            // never competes with the conversation text.
            Image("Chisato")
                .resizable()
                .scaledToFit()
                .opacity(0.07)
                .padding(.top, 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
        }
    }
}

#Preview {
    // Display sample conversation in preview
    ConversationView(messages: SampleData.conversation)
}
