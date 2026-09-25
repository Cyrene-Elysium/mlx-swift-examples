//
//  MLXChatExampleApp.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 20.04.2025.
//

import SwiftUI

@main
struct MLXChatExampleApp: App {
    @State private var store = ChatSessionStore()

    var body: some Scene {
        WindowGroup {
            SessionListView(store: store)
        }
    }
}
