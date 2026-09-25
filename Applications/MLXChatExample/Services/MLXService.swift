//
//  MLXService.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 20.04.2025.
//

import Foundation
import HuggingFace
import Hub
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXVLM
import Tokenizers

/// A service class that manages machine learning models for text and vision-language tasks.
/// This class handles model loading, caching, and text generation using various LLM and VLM models.
@Observable
class MLXService {
    /// Shared instance so the model cache and download state stay unified across the app.
    static let shared = MLXService()

    /// List of available models that can be used for generation.
    /// Includes both language models (LLM) and vision-language models (VLM).
    static let availableModels: [LMModel] = [
        LMModel(name: "qwen3:4b", configuration: LLMRegistry.qwen3_4b_4bit, type: .llm),
        LMModel(
            name: "qwen3.5:2b", configuration: LLMRegistry.qwen3_5_2b_4bit, type: .llm),
        LMModel(name: "glm4:9b", configuration: LLMRegistry.glm4_9b_4bit, type: .llm),
        LMModel(name: "mimo:7b", configuration: LLMRegistry.mimo_7b_sft_4bit, type: .llm),
        LMModel(
            name: "lfm2:8b", configuration: LLMRegistry.lfm2_8b_a1b_3bit_mlx, type: .llm),
        LMModel(
            name: "gemma4:E4B", configuration: VLMRegistry.gemma4_E4B_it_4bit, type: .vlm),
        LMModel(
            name: "gemma4:E2B", configuration: VLMRegistry.gemma4_E2B_it_4bit, type: .vlm),
    ]

    /// Cache to store loaded model containers to avoid reloading.
    private let modelCache = NSCache<NSString, ModelContainer>()

    /// Tracks the current model download progress.
    /// Access this property to monitor model download status.
    @MainActor
    private(set) var modelDownloadProgress: Progress?

    /// Loads a model from the hub or retrieves it from cache.
    /// - Parameter model: The model configuration to load
    /// - Returns: A ModelContainer instance containing the loaded model
    /// - Throws: Errors that might occur during model loading
    private func load(model: LMModel) async throws -> ModelContainer {
        // Size the MLX cache from physical memory. The original 20 MB limit is
        // far too small and causes constant cache thrashing (activations / KV
        // cache paged in and out), which slows generation a lot. Use ~1/4 of
        // RAM, clamped to a safe [512 MB, 4 GB] window.
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        Memory.cacheLimit = Int(
            min(max(physicalMemory / 4, 512 * 1024 * 1024), 4 * 1024 * 1024 * 1024))

        // Return cached model if available to avoid reloading
        if let container = modelCache.object(forKey: model.name as NSString) {
            return container
        } else {
            // Select appropriate factory based on model type
            let factory: ModelFactory =
                switch model.type {
                case .llm:
                    LLMModelFactory.shared
                case .vlm:
                    VLMModelFactory.shared
                }

            // Pin the downloader to the same cache directory the model manager
            // scans (HubApi.downloadBaseURL). The macro's no-argument form
            // builds a HubClient with an environment-resolved cache location,
            // which does not match - that mismatch made downloaded models show
            // up as "not downloaded".
            let downloader = #hubDownloader(
                HubClient(cache: HubCache(cacheDirectory: HubApi.downloadBaseURL))
            )
            let loader = #huggingFaceTokenizerLoader()

            // Load model and track download progress
            let container = try await factory.loadContainer(
                from: downloader,
                using: loader,
                configuration: model.configuration
            ) { progress in
                Task { @MainActor in
                    self.modelDownloadProgress = progress
                }
            }

            // Cache the loaded model for future use
            modelCache.setObject(container, forKey: model.name as NSString)

            return container
        }
    }

    /// Generates text based on the provided messages using the specified model.
    /// - Parameters:
    ///   - messages: Array of chat messages including user, assistant, and system messages
    ///   - model: The language model to use for generation
    ///   - thinkingEnabled: For models supporting the `/think` soft switch, controls
    ///     whether the thinking mode is on; ignored when nil or unsupported
    /// - Returns: An AsyncStream of generated text tokens
    /// - Throws: Errors that might occur during generation
    func generate(
        messages: [Message], model: LMModel, thinkingEnabled: Bool? = nil
    ) async throws -> AsyncStream<Generation> {
        // Load or retrieve model from cache
        let modelContainer = try await load(model: model)

        // Exclude trailing empty assistant message so the chat template
        // leaves the assistant turn open for generation (matching ChatSession behavior)
        var inputMessages = messages
        if let last = inputMessages.last, last.role == .assistant, last.content.isEmpty {
            inputMessages.removeLast()
        }

        // Map app-specific Message type to Chat.Message for model input
        var chat = inputMessages.map { message in
            let role: Chat.Message.Role =
                switch message.role {
                case .assistant:
                    .assistant
                case .user:
                    .user
                case .system:
                    .system
                }

            // Process any attached media for VLM models
            let images: [UserInput.Image] = message.images.map { imageURL in .url(imageURL) }
            let videos: [UserInput.Video] = message.videos.map { videoURL in .url(videoURL) }

            return Chat.Message(
                role: role, content: message.content, images: images, videos: videos)
        }

        // Qwen3-style soft switch: appended to the last user turn it toggles
        // the thinking mode regardless of the model's chat template support.
        // Applied only to the outbound copy, never to the persisted messages.
        if let thinkingEnabled, model.supportsThinking,
            let index = chat.lastIndex(where: { $0.role == .user })
        {
            chat[index].content += thinkingEnabled ? " /think" : " /no_think"
        }

        // Prepare input for model processing
        let userInput = UserInput(
            chat: chat, processing: .init(resize: .init(width: 1024, height: 1024)))

        // Generate response using the model
        return try await modelContainer.perform { (context: ModelContext) in
            let lmInput = try await context.processor.prepare(input: userInput)
            let parameters = Self.samplingParameters(thinking: thinkingEnabled == true)

            return try MLXLMCommon.generate(
                input: lmInput, parameters: parameters, context: context)
        }
    }

    /// Sampling parameters tuned per mode. Thinking mode uses Qwen3's
    /// recommended lower temperature and narrower nucleus for coherent
    /// reasoning chains; non-thinking uses a slightly higher temperature for
    /// conversational answers. A light repetition penalty and a max-token cap
    /// keep output from repeating or running away.
    private static func samplingParameters(thinking: Bool) -> GenerateParameters {
        if thinking {
            return GenerateParameters(
                temperature: 0.6, topP: 0.95, topK: 20,
                maxTokens: 4096, repetitionPenalty: 1.05)
        } else {
            return GenerateParameters(
                temperature: 0.7, topP: 0.8, topK: 20,
                maxTokens: 2048, repetitionPenalty: 1.05)
        }
    }

    // MARK: - Download management

    /// Local directory a model downloads into, following the Hugging Face hub cache layout
    /// (`<downloadBase>/models--<org>--<name>`).
    @MainActor
    static func downloadDirectory(for model: LMModel) -> URL {
        let repo = model.configuration.name.replacingOccurrences(of: "/", with: "--")
        return HubApi.downloadBaseURL.appending(path: "models--\(repo)")
    }

    /// Whether the model's files have been downloaded to disk.
    @MainActor
    func isDownloaded(_ model: LMModel) -> Bool {
        FileManager.default.fileExists(
            atPath: Self.downloadDirectory(for: model).path)
    }

    /// Total size on disk of a downloaded model, computed off the main actor.
    nonisolated static func directorySize(at url: URL) async -> Int64 {
        await Task.detached(priority: .utility) { () -> Int64 in
            guard
                let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles])
            else { return 0 }

            var total: Int64 = 0
            for case let fileURL as URL in enumerator {
                if
                    let values = try? fileURL.resourceValues(
                        forKeys: [.fileSizeKey, .isRegularFileKey]),
                    values.isRegularFile == true,
                    let size = values.fileSize
                {
                    total += Int64(size)
                }
            }
            return total
        }.value
    }

    /// Deletes a model's downloaded files from disk and evicts it from the in-memory cache.
    @MainActor
    func deleteDownloaded(_ model: LMModel) throws {
        modelCache.removeObject(forKey: model.name as NSString)
        try FileManager.default.removeItem(at: Self.downloadDirectory(for: model))
    }
}
