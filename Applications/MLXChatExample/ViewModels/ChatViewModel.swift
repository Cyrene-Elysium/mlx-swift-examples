//
//  ChatViewModel.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 20.04.2025.
//

import Foundation
import MLXLMCommon
import UIKit
import UniformTypeIdentifiers

/// ViewModel that manages the chat interface and coordinates with MLXService for text generation.
/// Handles user input, message history, media attachments, and generation state.
/// The conversation lives inside a persisted `ChatSession`.
@Observable
@MainActor
class ChatViewModel {
    /// Service responsible for ML model operations
    private let mlxService: MLXService

    /// Store persisting sessions across launches
    private let store: ChatSessionStore

    /// The conversation this view model operates on
    let session: ChatSession

    init(mlxService: MLXService, session: ChatSession, store: ChatSessionStore) {
        self.mlxService = mlxService
        self.store = store
        self.session = session
        self.selectedModel =
            MLXService.availableModels.first { $0.name == session.modelName }
            ?? MLXService.availableModels.first!
        self.thinkingEnabled =
            UserDefaults.standard.object(forKey: "thinkingEnabled") as? Bool ?? true
        self.expandThinkingLive =
            UserDefaults.standard.object(forKey: "expandThinkingLive") as? Bool ?? true
        self.settledRemainingTokens = remainingTokens
    }

    /// Current user input text
    var prompt: String = ""

    /// Chat history, backed by the session
    var messages: [Message] {
        session.messages
    }

    /// Currently selected language model for generation
    var selectedModel: LMModel {
        didSet {
            session.modelName = selectedModel.name
            store.defaultModelName = selectedModel.name
            // Context budget changed with the model — restate it at once so
            // the readout does not show a number for the previous model.
            settleRemainingTokens()
        }
    }

    /// Manages image and video attachments for the current message
    var mediaSelection = MediaSelection()

    /// Thinking mode for models supporting the /think soft switch.
    /// Toggled from the input bar; persisted via UserDefaults.
    var thinkingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(thinkingEnabled, forKey: "thinkingEnabled")
        }
    }

    /// 剩余上下文的粗略估算（token 数）。用字符数折半近似，仅供提示，
    /// 标注「约」使用。每次访问都重算——用于「是否接近上限」这类需要即时
    /// 判断的场合。
    var remainingTokens: Int {
        let used = session.messages.reduce(0) { $0 + $1.content.count / 2 }
        return max(selectedModel.contextLength - used, 0)
    }

    /// 展示用的剩余上下文，**仅在每次回复结束后结算**。
    ///
    /// Streaming 期间逐 chunk 重算会让这个数字不停跳动，读起来像噪声；
    /// 用户在整段输出完成后才关心它。所以这里读的是 `settledRemainingTokens`
    /// 缓存值，由 `generate()` 在收尾时（以及切换模型、清空对话时）刷新。
    private(set) var settledRemainingTokens: Int = 0

    /// 重新结算展示用的剩余上下文。
    func settleRemainingTokens() {
        settledRemainingTokens = remainingTokens
    }

    /// 是否接近上下文上限（剩余 < 20%），用于触发总结提示。
    var isContextNearLimit: Bool {
        remainingTokens < selectedModel.contextLength / 5
    }

    /// 总结用的模型（可在设置页切换，默认 qwen3:4b）。
    var summaryModel: LMModel {
        let name =
            UserDefaults.standard.string(forKey: "summaryModelName") ?? "qwen3:4b"
        return MLXService.availableModels.first { $0.name == name }
            ?? MLXService.availableModels.first!
    }

    /// Whether this conversation is currently being summarized. Backed by the
    /// global store so the state survives leaving and re-entering the chat
    /// (each entry creates a new view model).
    var isSummarizing: Bool {
        store.summarizingSessionIDs.contains(session.id)
    }

    /// Indicates if text generation is in progress
    var isGenerating = false

    /// True while the model is emitting its reasoning trace (inside the
    /// `…` block) and has not yet started the answer. Drives the live
    /// "正在思考" state of the thinking box.
    var isThinking = false

    /// Whether the thinking box expands while reasoning streams in. When
    /// false it stays collapsed and shows only a status line. Persisted via
    /// UserDefaults; toggled from Settings.
    var expandThinkingLive: Bool {
        didSet {
            UserDefaults.standard.set(expandThinkingLive, forKey: "expandThinkingLive")
        }
    }

    /// Current generation task, used for cancellation
    private var generateTask: Task<Void, any Error>?

    /// Stores performance metrics from the current generation
    private var generateCompletionInfo: GenerateCompletionInfo?

    /// Current generation speed in tokens per second
    var tokensPerSecond: Double {
        generateCompletionInfo?.tokensPerSecond ?? 0
    }

    /// Most recent error message, if any
    var errorMessage: String?

    /// Generates response for the current prompt and media attachments
    func generate() async {
        // Cancel any existing generation task
        if let existingTask = generateTask {
            existingTask.cancel()
            generateTask = nil
        }

        isGenerating = true
        isThinking = false

        // Auto-title the session from the first real user message
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if session.title == ChatSession.defaultTitle, !trimmedPrompt.isEmpty {
            session.title = String(trimmedPrompt.prefix(32))
        }

        // Add user message with any media attachments
        session.messages.append(
            .user(prompt, images: mediaSelection.images, videos: mediaSelection.videos))
        // Add empty assistant message that will be filled during generation
        session.messages.append(.assistant(""))

        // Clear the input after sending
        clear(.prompt)

        store.save(session)

        generateTask = Task {
            // Ask for ~30s of background execution so an in-flight reply keeps
            // streaming briefly after the app is backgrounded.
            let bgID = UIApplication.shared.beginBackgroundTask(withName: "generation")
            defer {
                if bgID != .invalid { UIApplication.shared.endBackgroundTask(bgID) }
            }

            // Process generation chunks and update UI
            for await generation in try await mlxService.generate(
                messages: messages, model: selectedModel,
                thinkingEnabled: selectedModel.supportsThinking ? thinkingEnabled : nil,
                kvBits: (UserDefaults.standard.object(
                    forKey: "kvCacheQuantized") as? Bool ?? true) ? 8 : nil
            )
            {
                switch generation {
                case .chunk(let chunk):
                    // Route incoming text into the assistant message, splitting
                    // the Qwen3 reasoning block (`…`) away from the
                    // answer so each gets its own surface. The split is done
                    // incrementally on the raw accumulated text: everything
                    // before the closing marker is reasoning, everything after
                    // is the answer.
                    if let assistantMessage = session.messages.last {
                        self.route(chunk: chunk, into: assistantMessage)
                    }
                case .info(let info):
                    // Update performance metrics and stamp this reply's speed
                    // onto the assistant message itself.
                    generateCompletionInfo = info
                    if let assistantMessage = session.messages.last {
                        assistantMessage.tokensPerSecond = info.tokensPerSecond
                    }
                case .toolCall:
                    break
                }
            }
        }

        do {
            // Handle task completion and cancellation
            try await withTaskCancellationHandler {
                try await generateTask?.value
            } onCancel: {
                Task { @MainActor in
                    generateTask?.cancel()

                    // Mark message as cancelled
                    if let assistantMessage = session.messages.last {
                        assistantMessage.content += "\n[Cancelled]"
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
        generateTask = nil

        // Settle the context readout once, after the whole reply has landed —
        // not on every streamed chunk, which would make it flicker.
        settleRemainingTokens()

        store.save(session)
    }

    /// Processes and adds media attachments to the current message.
    /// Images are copied into permanent storage so they survive across launches;
    /// videos reference the temporary file for the current session only.
    func addMedia(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()

            // Determine media type and add to appropriate collection
            if let mediaType = UTType(filenameExtension: url.pathExtension) {
                if mediaType.conforms(to: .image) {
                    if let persisted = store.persistMedia(at: url, for: session) {
                        mediaSelection.images = [persisted]
                    } else {
                        errorMessage = "保存所选图片失败。"
                    }
                } else if mediaType.conforms(to: .movie) {
                    mediaSelection.videos = [url]
                }
            }
        } catch {
            errorMessage = "Failed to load media item.\n\nError: \(error)"
        }
    }

    /// Clears various aspects of the chat state based on provided options
    func clear(_ options: ClearOption) {
        if options.contains(.prompt) {
            prompt = ""
            mediaSelection = .init()
        }

        if options.contains(.chat) {
            if session.isChisato {
                // 千束会话清空时保留人设 system 提示词
                session.messages = session.messages.filter { $0.role == .system }
            } else {
                session.messages = []
            }
            generateTask?.cancel()
            store.save(session)
        }

        if options.contains(.meta) {
            generateCompletionInfo = nil
        }

        // Anything that rewrites the history changes the context budget —
        // restate it now so the readout never lags the conversation.
        settleRemainingTokens()

        errorMessage = nil
    }

    /// 更新千束人设并同步到当前千束会话的 system 提示词。
    func updateChisatoPersona(_ text: String) {
        ChisatoProfile.shared.update(text)
        let persona = ChisatoProfile.shared.persona
        if let index = session.messages.firstIndex(where: { $0.role == .system }) {
            session.messages[index].content = persona
        } else {
            session.messages.insert(.system(persona), at: 0)
        }
        store.save(session)
    }

    /// 删除单条消息并持久化。删掉的消息会自动从后续请求的上下文中消失，
    /// 因为每次生成都以 `session.messages` 为准重新发给模型。
    func deleteMessage(_ message: Message) {
        session.messages.removeAll { $0.id == message.id }
        store.save(session)
    }

    /// 将历史对话浓缩为摘要，替换为「人设 + 摘要 + 最近 2 条」，
    /// 最大限度保留记忆的同时压缩上下文占用。
    ///
    /// The in-flight flag lives on the shared store, so navigating away (or
    /// the app being backgrounded — a background task keeps it running for
    /// ~30s) does not lose the state; re-entering the conversation still
    /// shows the progress indicator until the summary lands.
    func summarizeConversation() async {
        store.summarizingSessionIDs.insert(session.id)
        let bgID = UIApplication.shared.beginBackgroundTask(withName: "summarize")
        defer {
            store.summarizingSessionIDs.remove(session.id)
            if bgID != .invalid { UIApplication.shared.endBackgroundTask(bgID) }
        }

        // Free the resident conversation model + MLX buffers *before* loading
        // the summary model. Otherwise the two multi-GB models coexist in
        // memory and the system jetsams the app (observed as a crash after a
        // few seconds of the summarize spinner). The next chat re-loads on demand.
        //
        // Order matters: drop the containers and drain the MLX buffer cache
        // first, then clamp the cache limit so the summary model's transient
        // activations cannot balloon while the conversation model's weights
        // are still being reclaimed by the system. The limit is restored in
        // the defer below once the summary lands.
        MLXService.shared.unloadAllModelsSilently()
        MLXService.shared.setSummarizing(true)
        defer { MLXService.shared.setSummarizing(false) }

        let nonSystem = session.messages.filter { $0.role != .system }
        guard !nonSystem.isEmpty else { return }

        // 摘要模型未下载时直接提示，避免压缩时静默触发数 GB 下载。
        if !MLXService.shared.isDownloaded(summaryModel) {
            errorMessage = "摘要模型（\(summaryModel.name)）尚未下载，无法压缩上下文。请先在「模型」管理中下载它。"
            return
        }

        do {
            let summary = try await generateSummary(history: nonSystem)

            let systemMessages = session.messages.filter { $0.role == .system }
            let recent = Array(nonSystem.suffix(2))
            session.messages =
                systemMessages + [.system("对话摘要：\(summary)")] + recent
            store.save(session)
        } catch {
            errorMessage = "总结失败：\(error.localizedDescription)"
        }
    }

    /// 把流式 chunk 追加到助手消息，同时把 Qwen3 的思考块
    /// （`…`）从正文中剥离出来。
    ///
    /// 标记取自 Qwen3 的 chat template（实测其 tokenizer_config 用的是
    /// 普通尖括号 `<think>` / `</think>`，不是带特殊 Unicode 的形式）。
    /// 协议没有独立的 reasoning 通道（`Generation` 只有 `.chunk`），所以只能
    /// 对累积文本做切分：
    /// - 缓冲文本仍是 `<think>` 的合法前缀（含空白）→ 暂不判定，等更多文本；
    /// - 缓冲文本偏离 `<think>` → 无思考块（非思考模型，或 /no_think 直接作答），
    ///   全部进 `content`；
    /// - 缓冲文本凑满 `<think>` → 进入思考阶段，累积进 `thinking`；
    /// - 见到 `</think>` → 思考结束，标记定型，其后进 `content`。
    ///
    /// 之所以要先缓冲再判定：流式 chunk 的边界是任意的，首个 chunk 可能只有
    /// `<` 或 `<thi`，若直接判定会把真正的思考块误判成正文。
    private func route(chunk: String, into message: Message) {
        // Past the reasoning phase — everything left is answer text.
        if message.thinkingFinished {
            message.content += chunk
            return
        }

        // Undecided phase: buffer into `thinking`, then classify as soon as
        // the buffer can be judged. A streaming chunk boundary is arbitrary,
        // so the first chunk may be only `<` or `<thi` — judging on that
        // partial prefix would misfile a real reasoning block as an answer.
        if !message.thinkingDecided {
            message.thinking += chunk
            let probe = message.thinking.trimmingCharacters(in: .whitespacesAndNewlines)

            // Diverges from the opener → no reasoning block at all; the whole
            // buffer is answer text (non-thinking model, or /no_think).
            if !Self.opener.hasPrefix(probe) {
                message.thinkingDecided = true
                message.thinkingFinished = true
                message.content = message.thinking
                message.thinking = ""
                isThinking = false
                return
            }

            // Still a viable prefix (an empty/whitespace-only buffer is one
            // too) — withhold judgement and wait for more text.
            guard probe.count >= Self.opener.count else { return }

            // Full opener matched: reasoning block confirmed. Drop the opener
            // itself; the remainder (if any) stays buffered as reasoning.
            message.thinkingDecided = true
            if let openerRange = message.thinking.range(of: Self.opener) {
                message.thinking.removeSubrange(openerRange)
            }
            isThinking = true
        }

        // Reasoning phase: look for the closing marker in the buffer.
        guard let closeRange = message.thinking.range(of: Self.closer) else {
            isThinking = true
            return
        }

        // Split at the marker: before → reasoning, after → answer.
        let reasoning = String(message.thinking[..<closeRange.lowerBound])
        let answer = String(message.thinking[closeRange.upperBound...])
        message.thinking = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        message.content = answer
        message.thinkingFinished = true
        isThinking = false
    }

    /// Reasoning opener/closer emitted by Qwen3's chat template. Measured from
    /// `tokenizer_config.json`: plain angle brackets, not a special-Unicode
    /// variant, and no separate reasoning channel in the generation protocol.
    private static let opener = "<think>"
    private static let closer = "</think>"

    /// 从最旧的非 system 消息开始丢弃，直到回到 80% 以内。
    /// 千束人设等 system 消息始终保留。
    func truncateHistory() {
        let systemMessages = session.messages.filter { $0.role == .system }
        var nonSystem = session.messages.filter { $0.role != .system }

        let systemChars = systemMessages.reduce(0) { $0 + $1.content.count }
        // 80% 上限对应的字符数（token ≈ 字符 / 2）
        let targetChars = selectedModel.contextLength * 8 / 5

        while !nonSystem.isEmpty {
            let total =
                systemChars + nonSystem.reduce(0) { $0 + $1.content.count }
            if total <= targetChars { break }
            nonSystem.removeFirst()
        }

        session.messages = systemMessages + nonSystem
        store.save(session)
    }

    /// 用总结模型把历史对话压缩成一段摘要。
    private func generateSummary(history: [Message]) async throws -> String {
        let historyText = history.map { message in
            let speaker = message.role == .user ? "用户" : "千束"
            return "\(speaker)：\(message.content)"
        }.joined(separator: "\n")

        let prompt = """
        请把以下对话历史总结成一段简洁的摘要，用于后续对话延续上下文。
        要求：
        1. 保留：人物关系、重要约定、未完成的事项、用户明确表达过的偏好；
        2. 省略：寒暄、客套、已经解决且不再相关的内容；
        3. 控制在 150 字以内；
        4. 只输出摘要正文，不要任何前缀或解释。

        对话历史：
        \(historyText)
        """

        let model = summaryModel
        var result = ""
        let stream = try await mlxService.generate(
            messages: [.user(prompt)], model: model,
            thinkingEnabled: nil,
            kvBits: (UserDefaults.standard.object(forKey: "kvCacheQuantized") as? Bool
                ?? true) ? 8 : nil
        )
        for await generation in stream {
            if case .chunk(let chunk) = generation {
                result += chunk
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Manages the state of media attachments in the chat
@Observable
class MediaSelection {
    /// Controls visibility of media selection UI
    var isShowing = false

    /// Currently selected image URLs
    var images: [URL] = [] {
        didSet {
            didSetURLs(oldValue, images)
        }
    }

    /// Currently selected video URLs
    var videos: [URL] = [] {
        didSet {
            didSetURLs(oldValue, videos)
        }
    }

    /// Whether any media is currently selected
    var isEmpty: Bool {
        images.isEmpty && videos.isEmpty
    }

    private func didSetURLs(_ old: [URL], _ new: [URL]) {
        // the urls we get from fileImporter require SSB calls to access
        new.filter { !old.contains($0) }.forEach { _ = $0.startAccessingSecurityScopedResource() }
        old.filter { !new.contains($0) }.forEach { $0.stopAccessingSecurityScopedResource() }
    }
}

/// Options for clearing different aspects of the chat state
struct ClearOption: RawRepresentable, OptionSet {
    let rawValue: Int

    /// Clears current prompt and media selection
    static let prompt = ClearOption(rawValue: 1 << 0)
    /// Clears chat history and cancels generation
    static let chat = ClearOption(rawValue: 1 << 1)
    /// Clears generation metadata
    static let meta = ClearOption(rawValue: 1 << 2)
}
