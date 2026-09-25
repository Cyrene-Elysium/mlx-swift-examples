//
//  ChatViewModel.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 20.04.2025.
//

import Foundation
import MLXLMCommon
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
        self.kvCacheQuantized =
            UserDefaults.standard.object(forKey: "kvCacheQuantized") as? Bool ?? false
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
        }
    }

    /// Manages image and video attachments for the current message
    var mediaSelection = MediaSelection()

    /// Whether thinking mode is enabled for models supporting the soft switch
    /// (Qwen3 hybrid thinking). Persisted per app, not per session.
    var thinkingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(thinkingEnabled, forKey: "thinkingEnabled")
        }
    }

    /// Whether the KV cache is quantized to 8-bit. Halves long-context memory
    /// use at a negligible quality cost; off by default because not every
    /// model in the list has been validated with quantized KV cache.
    var kvCacheQuantized: Bool {
        didSet {
            UserDefaults.standard.set(kvCacheQuantized, forKey: "kvCacheQuantized")
        }
    }

    /// Indicates if text generation is in progress
    var isGenerating = false

    /// Current generation task, used for cancellation
    private var generateTask: Task<Void, any Error>?

    /// Stores performance metrics from the current generation
    private var generateCompletionInfo: GenerateCompletionInfo?

    /// Current generation speed in tokens per second
    var tokensPerSecond: Double {
        generateCompletionInfo?.tokensPerSecond ?? 0
    }

    /// Progress of the current model download, if any
    var modelDownloadProgress: Progress? {
        mlxService.modelDownloadProgress
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
            // Process generation chunks and update UI
            for await generation in try await mlxService.generate(
                messages: messages, model: selectedModel,
                thinkingEnabled: selectedModel.supportsThinking ? thinkingEnabled : nil,
                kvBits: kvCacheQuantized ? 8 : nil
            )
            {
                switch generation {
                case .chunk(let chunk):
                    // Append new text to the current assistant message
                    if let assistantMessage = session.messages.last {
                        assistantMessage.content += chunk
                    }
                case .info(let info):
                    // Update performance metrics
                    generateCompletionInfo = info
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
            session.messages = []
            generateTask?.cancel()
            store.save(session)
        }

        if options.contains(.meta) {
            generateCompletionInfo = nil
        }

        errorMessage = nil
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
