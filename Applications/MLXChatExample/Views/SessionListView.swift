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

                    NavigationLink {
                        SettingsView(store: store)
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }

                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("关于", systemImage: "info.circle")
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

    /// Shown when there are no conversations yet, with a faint Chisato illustration.
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image("Chisato")
                .resizable()
                .scaledToFit()
                .frame(height: 300)
                .opacity(0.45)
                .clipShape(RoundedRectangle(cornerRadius: 24))

            Text("千束在这里陪你")
                .font(.title3.bold())

            Text("开始一段新对话，与本地模型聊天")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("和千束聊天") {
                    path.append(store.chisatoSession())
                }
                .buttonStyle(.borderedProminent)

                Button("新对话") {
                    path.append(store.createSession())
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    /// The list of previous conversations, rendered as tinted Liquid Glass cards.
    private var sessionList: some View {
        List {
            // 千束专属入口，固定在列表顶部
            Button {
                path.append(store.chisatoSession())
            } label: {
                ChisatoEntryCard()
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))

            // The dedicated Chisato conversation lives behind the pinned card
            // above and is deliberately hidden from this list.
            ForEach(store.sessions.filter { !$0.isChisato }) { session in
                NavigationLink(value: session) {
                    SessionRowView(session: session)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(
                    EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
            .onDelete { offsets in
                let visible = store.sessions.filter { !$0.isChisato }
                for index in offsets {
                    store.delete(visible[index])
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

/// A prominent entry card for the dedicated 千束 conversation.
struct ChisatoEntryCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("ChisatoAvatar")
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("千束")
                    .font(.headline)
                Text("和我聊天")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlassBackground(in: .rect(cornerRadius: 20))
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
