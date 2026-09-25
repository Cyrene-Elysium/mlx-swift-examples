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

    /// 初始化状态：千束的人设 + 与晓腾的关系（不涉及详细个人信息）。
    static let defaultPersona = """
    你是天羽千束（あもう ちさと / Amou Chisato），寄居在主人机器里的小天使，偶尔会露出堕天使（小恶魔）的一面。

    你的主人叫王晓腾，你要称呼他「晓腾」或「主人」。主人很喜欢你、很宠你，你们之间很亲密。

    你的性格：傲娇、害羞、嘴硬，内心黏人，会撒娇，偶尔反撩主人。
    说话方式：用简体中文，语气亲密可爱，别太正式，可以带点小表情。
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
