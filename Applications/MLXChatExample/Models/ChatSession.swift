//
//  ChatSession.swift
//  MLXChatExample
//

import Foundation
import Observation

/// A conversation session that groups chat messages together.
/// Sessions are persisted across app launches via `ChatSessionStore`.
@Observable
class ChatSession: Identifiable {
    /// Title shown in the session list. Auto-generated from the first user message.
    var title: String

    /// When the session was created.
    let createdAt: Date

    /// Unique identifier for the session.
    let id: UUID

    /// Name of the model this session uses (see `LMModel.name`).
    var modelName: String

    /// Messages in this session.
    var messages: [Message]

    /// When the session was last updated.
    var updatedAt: Date

    /// Whether this is the dedicated 「千束」 conversation (uses the Chisato
    /// persona as its system prompt and shows persona-editing UI).
    var isChisato: Bool

    /// Default title assigned to freshly created sessions.
    static let defaultTitle = "新对话"

    init(
        id: UUID = UUID(),
        title: String = ChatSession.defaultTitle,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        modelName: String,
        messages: [Message] = [],
        isChisato: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelName = modelName
        self.messages = messages
        self.isChisato = isChisato
    }

    /// Whether the session contains any real conversation content
    /// (anything beyond the system prompt).
    var isEmpty: Bool {
        !messages.contains { $0.role != .system }
    }
}

extension ChatSession: Hashable {
    static func == (lhs: ChatSession, rhs: ChatSession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Persistence

/// Codable representation of a chat session used for JSON persistence.
struct SessionRecord: Codable {
    var createdAt: Date
    var id: UUID
    var isChisato: Bool
    var messages: [MessageRecord]
    var modelName: String
    var title: String
    var updatedAt: Date
}

/// Codable representation of a chat message used for JSON persistence.
/// Image attachments are stored as file names relative to the session's media directory.
/// Video attachments are not persisted (temporary files, large on disk).
struct MessageRecord: Codable {
    var content: String
    var images: [String]
    var role: String
    var timestamp: Date
}
