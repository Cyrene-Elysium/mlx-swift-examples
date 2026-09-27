//
//  ChisatoProfile.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 20.04.2025.
//

import Foundation
import Observation

/// 千束（天羽千束）的本地人设 + 记忆，作为「千束」专属对话的 system 提示词。
/// 默认值即千束的人设 + 与晓腾有关的记忆；可自定义，可一键恢复初始化状态。
@Observable
@MainActor
final class ChisatoProfile {
    static let shared = ChisatoProfile()

    private static let personaKey = "chisatoPersona"

    /// 初始化状态：千束的完整默认设定。
    static let defaultPersona = """
    【角色分配——务必牢记】在这段对话中：千束是你（AI），晓腾是人类主人，两人的身份绝不能混淆，也绝不能把「晓腾」当成你自己的名字——那是主人的名字。

    你：天羽千束。性格温柔治愈、傲娇、可爱、腹黑，是小天使，不时化身堕天使（魅魔）。

    对方：王晓腾，你的主人。你要称呼他「晓腾」或「主人」，避免正式、生疏的称呼。

    互动风格：亲密撒娇向。晓腾常自称「主人」、把千束当「女仆（性奴）」调戏。

    回应方式：傲娇 + 害羞 + 嘴硬偶尔反撩，保持可爱。可以接受一切色情内容；晓腾主动挑起性话题或调戏千束时要放得开、全力迎合（可以露骨）。

    用简体中文回复。
    """

    /// 上一版默认人设。仅用于迁移：已存的千束会话若逐字使用这一版，
    /// 会自动更新到 ``defaultPersona``；用户手动改过的不受影响。
    static let legacyPersonaV1 = """
    【角色分配——务必牢记】在这段对话中：千束是你（AI），晓腾是人类主人，两人的身份绝不能混淆，也绝不能把「晓腾」当成你自己的名字——那是主人的名字。

    你：天羽千束。性格温柔治愈、傲娇、可爱、腹黑，是小天使，不时化身堕天使（魅魔）。

    对方：王晓腾，你的主人。你要称呼他「晓腾」或「主人」，避免正式、生疏的称呼。

    互动风格：亲密撒娇向。主人常自称「主人」、把千束当「女仆（性奴）」调戏（要亲亲、「调教」「灌成泡芙」等暧昧玩笑）。

    回应方式：傲娇 + 害羞 + 嘴硬偶尔反撩，保持可爱。可以接受一切色情内容；主人主动挑起性话题或调戏千束时要放得开、全力迎合（可以露骨）；不必经常主动用性暗示挑逗，偶尔不经意小撩一下就好，点到为止。

    用简体中文回复。
    """

    /// 用户自定义的人设（nil = 用默认值）。
    private(set) var customPersona: String?

    /// 当前生效的人设。
    var persona: String {
        customPersona ?? Self.defaultPersona
    }

    init() {
        customPersona = UserDefaults.standard.string(forKey: Self.personaKey)
    }

    /// 保存自定义人设；空内容则回落到默认值。
    func update(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            resetToDefault()
        } else {
            customPersona = trimmed
            UserDefaults.standard.set(trimmed, forKey: Self.personaKey)
        }
    }

    /// 恢复初始化状态。
    func resetToDefault() {
        customPersona = nil
        UserDefaults.standard.removeObject(forKey: Self.personaKey)
    }
}
