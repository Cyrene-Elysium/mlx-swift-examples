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
                        Label("新对话", systemImage: "square.and.pencil")
                    }

                    NavigationLink {
                        ModelManagerView(store: store)
                    } label: {
                        Label("管理模型", systemImage: "shippingbox.fill")
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
            Label("暂无对话", systemImage: "text.bubble")
        } description: {
            Text("千束为你备好了本地模型，开始一段新对话吧")
        } actions: {
            Button("新对话") {
                path.append(store.createSession())
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// The list of previous conversations, rendered as tinted Liquid Glass cards.
    private var sessionList: some View {
        List {
            ForEach(store.sessions) { session in
                NavigationLink(value: session) {
                    SessionRowView(session: session)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(
                    EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
            .onDelete { offsets in
                store.delete(at: offsets)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

/// A single row in the session list, rendered as a Liquid Glass card.
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlassBackground(in: .rect(cornerRadius: 20))
    }
}

#Preview {
    SessionListView(store: ChatSessionStore())
}
