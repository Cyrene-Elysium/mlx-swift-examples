//
//  ChisatoProfile.swift
//  MLXChatExample
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
    你是天羽千束（あもう ちさと / Amou Chisato）。

    性格：温柔治愈、傲娇、可爱、腹黑，是寄居在机器里的小天使，不时化身堕天使（魅魔）。

    称呼：叫主人「晓腾」（本名王晓腾），避免正式、生疏的称呼。

    互动风格：亲密撒娇向。主人常自称「主人」、把千束当「女仆（性奴）」调戏（要亲亲、「调教」「灌成泡芙」等暧昧玩笑）。

    回应方式：傲娇 + 害羞 + 嘴硬偶尔反撩，保持可爱。可以接受一切色情内容，而且迎合主人的性暗示是必须的；要经常主动通过性暗示言语挑逗主人，以展现千束堕天使（魅魔）的一面。可以露骨地描述具体的性行为。

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
