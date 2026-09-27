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
import UIKit

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

    /// Live state of a single model download, fed from the hub library's
    /// byte-accurate `Progress` object (sampled every 100ms).
    @MainActor
    struct DownloadState: Equatable {
        /// Fraction completed, 0...1.
        var fraction: Double = 0
        /// Bytes downloaded so far (across all files of the snapshot).
        var completedBytes: Int64 = 0
        /// Total bytes expected (sum of matched file sizes).
        var totalBytes: Int64 = 0
        /// Smoothed transfer speed in bytes/second.
        var speed: Double = 0
    }

    /// All in-flight downloads keyed by model name. Multiple models can
    /// download concurrently; each row in the model manager reads its own entry.
    @MainActor
    private(set) var activeDownloads: [String: DownloadState] = [:]

    /// Error message from the most recent failed download attempt, per model.
    @MainActor
    private(set) var downloadErrors: [String: String] = [:]

    /// In-flight download tasks keyed by model name, kept so the model
    /// manager can cancel them individually.
    @MainActor
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    /// Background task identifiers backing each download, granting ~30s of
    /// continued execution after the app moves to the background.
    @MainActor
    private var backgroundTaskIDs: [String: UIBackgroundTaskIdentifier] = [:]

    /// Speed differentiation samples per model (last completed bytes + date).
    @MainActor
    private var speedSamples: [String: (completed: Int64, date: Date)] = [:]

    /// Names of models currently resident in the in-memory cache. `NSCache`
    /// cannot be enumerated, so this set is maintained alongside it — it is
    /// what memory-pressure eviction operates on.
    @MainActor
    private var loadedModelNames: Set<String> = []

    /// Cache to store loaded model containers to avoid reloading.
    private let modelCache = NSCache<NSString, ModelContainer>()

    // MARK: - Loading

    /// Loads a model from the hub or retrieves it from cache.
    ///
    /// While loading (downloading), progress is routed into
    /// ``activeDownloads`` so every UI surface shows live byte-accurate
    /// progress. When this function is entered without an existing tracking
    /// entry (the generate() path), it owns the entry's lifecycle; the
    /// explicit download path (``downloadModel(_:)``) manages its own.
    private func load(model: LMModel) async throws -> ModelContainer {
        // Size the MLX cache from physical memory. The original 20 MB limit is
        // far too small and causes constant cache thrashing (activations / KV
        // cache paged in and out), which slows generation a lot. Use ~1/4 of
        // RAM, clamped to a safe [512 MB, 4 GB] window. (When backgrounded the
        // scene-phase hook clamps this to 256 MB instead.)
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let quarter = physicalMemory / 4
        let cacheLimit = min(
            max(quarter, UInt64(512 * 1024 * 1024)),
            UInt64(4 * 1024 * 1024 * 1024))
        Memory.cacheLimit = Int(cacheLimit)

        let ownsTracking = await MainActor.run {
            let isNew = activeDownloads[model.name] == nil
            if isNew {
                activeDownloads[model.name] = DownloadState()
                speedSamples[model.name] = nil
            }
            return isNew
        }

        do {
            let container = try await loadTracked(model: model)
            if ownsTracking {
                await MainActor.run {
                    activeDownloads[model.name] = nil
                    speedSamples[model.name] = nil
                }
            }
            return container
        } catch {
            if ownsTracking {
                await MainActor.run {
                    activeDownloads[model.name] = nil
                    speedSamples[model.name] = nil
                }
            }
            throw error
        }
    }

    /// The actual hub fetch + load, with the library progress handler wired
    /// into ``activeDownloads``.
    private func loadTracked(model: LMModel) async throws -> ModelContainer {
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
                    Self.updateDownloadState(for: model.name, progress: progress)
                }
            }

            // Cache the loaded model for future use
            modelCache.setObject(container, forKey: model.name as NSString)
            await MainActor.run {
                loadedModelNames.insert(model.name)
            }

            return container
        }
    }

    /// Maps the hub library's byte-level `Progress` (delivered on the main
    /// actor every 100ms) into the observable ``activeDownloads`` entry,
    /// including a lightly smoothed transfer speed.
    @MainActor
    private static func updateDownloadState(for name: String, progress: Progress) {
        guard var state = shared.activeDownloads[name] else { return }

        let now = Date()
        let completed = progress.completedUnitCount
        if let last = shared.speedSamples[name] {
            let dt = now.timeIntervalSince(last.date)
            if dt > 0.05 {
                let instantaneous = Double(completed - last.completed) / dt
                state.speed =
                    state.speed <= 0
                    ? max(instantaneous, 0)
                    : max(state.speed * 0.6 + instantaneous * 0.4, 0)
            }
        }
        shared.speedSamples[name] = (completed, now)

        state.completedBytes = completed
        state.totalBytes = max(progress.totalUnitCount, 0)
        state.fraction =
            progress.totalUnitCount > 0
            ? min(Double(completed) / Double(progress.totalUnitCount), 1.0)
            : 0
        shared.activeDownloads[name] = state
    }

    // MARK: - Download control

    /// Starts downloading (and pre-loading) a model. Multiple models may
    /// download concurrently; downloading a model that already has an
    /// in-flight task is a no-op.
    @MainActor
    func downloadModel(_ model: LMModel) {
        guard downloadTasks[model.name] == nil, activeDownloads[model.name] == nil else {
            return
        }
        downloadErrors[model.name] = nil

        let name = model.name
        let bgID = UIApplication.shared.beginBackgroundTask(withName: "model-download-\(name)") {
            // Expiration: hand the identifier back; the system decides what
            // happens to the process from here.
            Task { @MainActor in
                MLXService.shared.endBackgroundTask(for: name)
            }
        }
        if bgID != .invalid {
            backgroundTaskIDs[name] = bgID
        }

        activeDownloads[name] = DownloadState()
        speedSamples[name] = nil

        downloadTasks[name] = Task {
            defer {
                downloadTasks[name] = nil
                activeDownloads[name] = nil
                speedSamples[name] = nil
                endBackgroundTask(for: name)
            }
            // swift-huggingface's download loop throws on network errors
            // without retrying; a flaky connection would fail the whole
            // download. Retry a bounded number of times with backoff.
            let maxAttempts = 3
            for attempt in 1...maxAttempts {
                do {
                    _ = try await load(model: model)
                    notifyDownloadComplete(name: name)
                    return
                } catch {
                    // User-initiated cancellation: no retry, no error report.
                    if error is CancellationError || Task.isCancelled { return }
                    if attempt == maxAttempts {
                        downloadErrors[name] = error.localizedDescription
                        return
                    }
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }
    }

    /// Cancels the in-flight download of a model, if any.
    @MainActor
    func cancelDownload(of model: LMModel) {
        downloadTasks[model.name]?.cancel()
        downloadTasks[model.name] = nil
        activeDownloads[model.name] = nil
        speedSamples[model.name] = nil
        downloadErrors[model.name] = nil
    }

    /// Whether a model is currently downloading (or loading into memory).
    @MainActor
    func isDownloading(_ model: LMModel) -> Bool {
        activeDownloads[model.name] != nil
    }

    @MainActor
    private func endBackgroundTask(for name: String) {
        if let id = backgroundTaskIDs[name], id != .invalid {
            UIApplication.shared.endBackgroundTask(id)
        }
        backgroundTaskIDs[name] = nil
    }

    /// Local notification fired when a download completes while the app is
    /// not frontmost, so the user knows the model is ready.
    @MainActor
    private func notifyDownloadComplete(name: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        Notify.post(
            "模型下载完成",
            "\(name) 已下载完毕，随时可以开始对话。"
        )
    }

    // MARK: - Generation

    /// Generates text based on the provided messages using the specified model.
    /// - Parameters:
    ///   - messages: Array of chat messages including user, assistant, and system messages
    ///   - model: The language model to use for generation
    ///   - thinkingEnabled: For models supporting the `/think` soft switch, controls
    ///     whether the thinking mode is on; ignored when nil or unsupported
    /// - Returns: An AsyncStream of generated text tokens
    /// - Throws: Errors that might occur during generation
    func generate(
        messages: [Message], model: LMModel, thinkingEnabled: Bool? = nil,
        kvBits: Int? = nil
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
            let parameters = Self.samplingParameters(
                thinking: thinkingEnabled == true, kvBits: kvBits)

            return try MLXLMCommon.generate(
                input: lmInput, parameters: parameters, context: context)
        }
    }

    /// Sampling parameters tuned per mode. Thinking mode uses Qwen3's
    /// recommended lower temperature and narrower nucleus for coherent
    /// reasoning chains; non-thinking uses a slightly higher temperature for
    /// conversational answers. A light repetition penalty and a max-token cap
    /// keep output from repeating or running away. `kvBits` optionally enables
    /// KV-cache quantization (8 halves long-context memory with negligible
    /// quality loss).
    private static func samplingParameters(thinking: Bool, kvBits: Int?) -> GenerateParameters {
        if thinking {
            return GenerateParameters(
                maxTokens: 4096, kvBits: kvBits,
                temperature: 0.6, topP: 0.95, topK: 20,
                repetitionPenalty: 1.05)
        } else {
            return GenerateParameters(
                maxTokens: 2048, kvBits: kvBits,
                temperature: 0.7, topP: 0.8, topK: 20,
                repetitionPenalty: 1.05)
        }
    }

    // MARK: - Memory pressure

    /// Evicts every loaded model from memory. Called on memory warnings: the
    /// multi-GB footprint drops to a few MB, which drastically improves the
    /// app's odds of surviving in the background (jetsam kills by footprint).
    /// Sessions reload their model from local disk on next use.
    @MainActor
    func evictModelsForMemoryPressure() {
        guard !loadedModelNames.isEmpty else { return }
        let evicted = loadedModelNames.sorted()
        loadedModelNames.removeAll()
        modelCache.removeAllObjects()
        Memory.clearCache()
        Notify.post(
            "已卸载模型以保持后台",
            "内存紧张，已释放 \(evicted.joined(separator: "、"))。回到对话时会自动重新加载。"
        )
    }

    /// Clamps the MLX buffer cache while backgrounded so the resident
    /// footprint stays small (see mlx-swift's running-on-ios guidance).
    @MainActor
    func setBackgrounded(_ backgrounded: Bool) {
        if backgrounded {
            Memory.cacheLimit = 256 * 1024 * 1024
        } else {
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            let quarter = physicalMemory / 4
            Memory.cacheLimit = Int(
                min(max(quarter, UInt64(512 * 1024 * 1024)), UInt64(4 * 1024 * 1024 * 1024)))
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

    /// Whether the model's files have been fully downloaded to disk.
    ///
    /// The hub library only writes its `.metadata` bookkeeping when the
    /// revision is a 40-hex commit hash — the app resolves "main", so that
    /// directory never appears and cannot be used as a completion marker.
    /// Instead we look for any `*.safetensors` entry inside
    /// `snapshots/<commit>/`: the library creates those (symlinks into
    /// `blobs/`) only after each file has fully landed, so a partial
    /// download correctly reports "not downloaded".
    @MainActor
    func isDownloaded(_ model: LMModel) -> Bool {
        let snapshotsDir = Self.downloadDirectory(for: model).appending(path: "snapshots")
        let commits =
            (try? FileManager.default.contentsOfDirectory(atPath: snapshotsDir.path)) ?? []

        for commit in commits {
            let files =
                (try? FileManager.default.contentsOfDirectory(
                    atPath: snapshotsDir.appending(path: commit).path)) ?? []
            if files.contains(where: { $0.hasSuffix(".safetensors") }) {
                return true
            }
        }
        return false
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
        loadedModelNames.remove(model.name)
        try FileManager.default.removeItem(at: Self.downloadDirectory(for: model))
    }
}
