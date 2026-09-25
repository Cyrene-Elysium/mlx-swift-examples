//
//  ChatSessionStore.swift
//  MLXChatExample
//

import Foundation
import Observation

/// Persists chat sessions and their media attachments to disk.
///
/// - Sessions are stored as a single JSON document in Application Support.
/// - Image attachments are copied into per-session media directories so they
///   remain valid across launches (temporary directory files are purged by the OS).
@Observable
@MainActor
final class ChatSessionStore {
    /// UserDefaults key for the model selected for new sessions.
    private static let defaultModelKey = "defaultModelName"

    /// Directory holding per-session media attachments.
    let mediaDirectory: URL

    /// All known sessions, most recently updated first.
    private(set) var sessions: [ChatSession]

    /// Name of the model selected for new sessions and model management.
    var defaultModelName: String {
        didSet {
            UserDefaults.standard.set(defaultModelName, forKey: Self.defaultModelKey)
        }
    }

    /// URL of the JSON document backing the store.
    private let storageURL: URL

    init() {
        let support = URL.applicationSupportDirectory
        mediaDirectory = support.appending(path: "SessionMedia", isDirectory: true)
        storageURL = support.appending(path: "sessions.json")

        try? FileManager.default.createDirectory(
            at: mediaDirectory, withIntermediateDirectories: true)

        defaultModelName =
            UserDefaults.standard.string(forKey: Self.defaultModelKey)
            ?? MLXService.availableModels.first!.name

        sessions = Self.load(from: storageURL, mediaDirectory: mediaDirectory)

        // Drop empty sessions left over from previous runs.
        sessions.removeAll { $0.isEmpty }
        persist()
    }

    // MARK: - Session lifecycle

    /// Creates a new session using the default model and adds it to the list.
    func createSession() -> ChatSession {
        let model =
            MLXService.availableModels.first { $0.name == defaultModelName }
            ?? MLXService.availableModels.first!

        let session = ChatSession(
            modelName: model.name,
            messages: [.system("You are a helpful assistant!")]
        )
        sessions.insert(session, at: 0)
        persist()
        return session
    }

    /// Deletes a session along with its persisted media attachments.
    func delete(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        try? FileManager.default.removeItem(
            at: mediaDirectory.appending(path: session.id.uuidString))
        persist()
    }

    /// Deletes the sessions at the given offsets (used by swipe-to-delete).
    func delete(at offsets: IndexSet) {
        for index in offsets {
            delete(sessions[index])
        }
    }

    /// Persists a session's current state (called after message activity).
    func save(_ session: ChatSession) {
        session.updatedAt = .now

        if !sessions.contains(where: { $0.id == session.id }) {
            sessions.append(session)
        }

        // Keep the most recently updated session on top.
        sessions.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    // MARK: - Media persistence

    /// Media directory for a session, created on demand.
    func mediaDirectory(for session: ChatSession) -> URL {
        let dir = mediaDirectory.appending(path: session.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies a media file into the session's media directory so it survives
    /// across launches. Returns the new permanent URL, or nil on failure.
    func persistMedia(at source: URL, for session: ChatSession) -> URL? {
        let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension
        let destination = mediaDirectory(for: session)
            .appending(path: "\(UUID().uuidString).\(ext)")

        let didStartAccessing = source.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                source.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    // MARK: - Persistence internals

    private func persist() {
        let records = sessions.map { session in
            SessionRecord(
                createdAt: session.createdAt,
                id: session.id,
                messages: session.messages.map { message in
                    MessageRecord(
                        content: message.content,
                        images: message.images.map { $0.lastPathComponent },
                        role: {
                            switch message.role {
                            case .user: "user"
                            case .assistant: "assistant"
                            case .system: "system"
                            }
                        }(),
                        timestamp: message.timestamp
                    )
                },
                modelName: session.modelName,
                title: session.title,
                updatedAt: session.updatedAt
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(records) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private static func load(from url: URL, mediaDirectory: URL) -> [ChatSession] {
        guard let data = try? Data(contentsOf: url) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let records = try? decoder.decode([SessionRecord].self, from: data) else {
            return []
        }

        return
            records
            .map { record in
                let mediaDir = mediaDirectory.appending(path: record.id.uuidString)
                let messages = record.messages.map { message -> Message in
                    let role: Message.Role =
                        switch message.role {
                        case "user": .user
                        case "assistant": .assistant
                        default: .system
                        }

                    return Message(
                        role: role,
                        content: message.content,
                        images: message.images.map { mediaDir.appending(path: $0) }
                    )
                }

                return ChatSession(
                    id: record.id,
                    title: record.title,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt,
                    modelName: record.modelName,
                    messages: messages
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
