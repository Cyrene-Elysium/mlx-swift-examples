//
//  LMModel.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 21.04.2025.
//

import MLXLMCommon

/// Represents a language model configuration with its associated properties and type.
/// Can represent either a large language model (LLM) or a vision-language model (VLM).
struct LMModel {
    /// Name of the model
    let name: String

    /// Configuration settings for model initialization
    let configuration: ModelConfiguration

    /// Type of the model (language or vision-language)
    let type: ModelType

    /// Defines the type of language model
    enum ModelType {
        /// Large language model (text-only)
        case llm
        /// Vision-language model (supports images and text)
        case vlm
    }
}

// MARK: - Helpers

extension LMModel {
    /// 组内统一排序：名称升序，名称相同再按体积从小到大。
    /// 「已下载 → 未下载」的分组优先级由各调用方处理。
    static func listSort(_ a: LMModel, _ b: LMModel) -> Bool {
        if a.name != b.name { return a.name < b.name }
        return (a.estimatedSizeBytes ?? 0) < (b.estimatedSizeBytes ?? 0)
    }

    /// Display name shown in the picker and model list, title-cased.
    var displayName: String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Estimated download size in bytes, shown for not-yet-downloaded models.
    /// Derived from the MLX-community repository file sizes.
    var estimatedSizeBytes: Int64? {
        switch name {
        case "qwen3:4b": 2_280_000_000
        case "qwen3.5:2b": 1_750_000_000
        case "glm4:9b": 5_310_000_000
        case "mimo:7b": 4_300_000_000
        case "lfm2:8b": 4_180_000_000
        case "gemma4:E4B": 5_180_000_000
        case "gemma4:E2B": 3_580_000_000
        default: nil
        }
    }

    /// Maximum context window in tokens (from the model's
    /// `max_position_embeddings`), used to display remaining context.
    var contextLength: Int {
        switch name {
        case "qwen3:4b": 40_960
        case "qwen3.5:2b": 262_144
        case "glm4:9b": 32_768
        case "mimo:7b": 32_768
        case "lfm2:8b": 128_000
        case "gemma4:E4B": 131_072
        case "gemma4:E2B": 131_072
        default: 32_768
        }
    }

    /// Whether the model is a large language model
    var isLanguageModel: Bool {
        type == .llm
    }

    /// Whether the model is a vision-language model
    var isVisionModel: Bool {
        type == .vlm
    }

    /// Whether the model supports the `/think` and `/no_think` soft switches
    /// appended to the user message (Qwen3 hybrid-thinking models do; the
    /// `enable_thinking` template parameter is not honored by their templates).
    var supportsThinking: Bool {
        name.hasPrefix("qwen3")
    }
}

extension LMModel: Identifiable, Hashable {
    var id: String {
        name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
