//
//  SessionListView.swift
//  MLXChatExample
//

import SwiftUI

/// Root view listing previous conversations, with actions to start a new chat
/// and to manage downloaded models.
struct SessionListView: View {
    @Bindable var store: ChatSessionStore

    /// Navigation path of pushed sessions.
    @State private var path: [ChatSession] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("MLX Chat")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        path.append(store.createSession())
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }

                    NavigationLink {
                        ModelManagerView(store: store)
                    } label: {
                        Label("Manage Models", systemImage: "brain")
                    }
                }
            }
            .navigationDestination(for: ChatSession.self) { session in
                ChatView(
                    viewModel: ChatViewModel(
                        mlxService: .shared, session: session, store: store))
            }
        }
    }

    /// Shown when there are no conversations yet.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Conversations", systemImage: "text.bubble")
        } description: {
            Text("Start a new chat to talk with a local model.")
        } actions: {
            Button("New Chat") {
                path.append(store.createSession())
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// The list of previous conversations.
    private var sessionList: some View {
        List {
            ForEach(store.sessions) { session in
                NavigationLink(value: session) {
                    SessionRowView(session: session)
                }
            }
            .onDelete { offsets in
                store.delete(at: offsets)
            }
        }
    }
}

/// A single row in the session list.
struct SessionRowView: View {
    let session: ChatSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(
                    "\(session.modelName) · "
                        + session.updatedAt.formatted(
                            .relative(presentation: .named))
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SessionListView(store: ChatSessionStore())
}
