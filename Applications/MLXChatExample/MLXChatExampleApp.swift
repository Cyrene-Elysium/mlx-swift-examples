//
//  MLXChatExampleApp.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 20.04.2025.
//

import SwiftUI
import UIKit
import UserNotifications

@main
struct MLXChatExampleApp: App {
    @State private var store = ChatSessionStore()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SessionListView(store: store)
                .task {
                    // Ask for the one permission the app actually needs up
                    // front, at first launch: notifications (download
                    // completion, memory-pressure eviction notices).
                    Notify.requestAuthorization()
                    migrateChisatoPersonaIfNeeded()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didReceiveMemoryWarningNotification)
                ) { _ in
                    // Memory pressure: drop every resident model so the
                    // footprint shrinks from gigabytes to megabytes — that is
                    // what keeps the app alive in the background.
                    MLXService.shared.evictModelsForMemoryPressure()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Tighten the MLX buffer cache while backgrounded so the
                    // resident footprint stays small (jetsam kills by size).
                    MLXService.shared.setBackgrounded(newPhase != .active)
                }
        }
    }

    /// One-time migration: Chisato conversations still carrying the previous
    /// default persona verbatim are upgraded to the current default. Sessions
    /// with a hand-edited persona are left untouched.
    private func migrateChisatoPersonaIfNeeded() {
        let legacy = ChisatoProfile.legacyPersonaV1
        let current = ChisatoProfile.defaultPersona
        guard legacy != current else { return }

        var updated = false
        for session in store.sessions where session.isChisato {
            if let index = session.messages.firstIndex(where: {
                $0.role == .system && $0.content == legacy
            }) {
                session.messages[index].content = current
                updated = true
            }
        }
        if updated {
            if let chisato = store.sessions.first(where: { $0.isChisato }) {
                store.save(chisato)
            }
        }
    }
}

/// Thin wrapper around local notifications for the app's user-facing events.
enum Notify {
    /// Requests notification authorization (alert + sound). Called once at
    /// first launch; system remembers the user's answer afterwards.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
            _, _ in
        }
    }

    /// Posts a local notification immediately. The system decides whether to
    /// surface it (e.g. not while the app is frontmost without banner
    /// permission).
    static func post(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
