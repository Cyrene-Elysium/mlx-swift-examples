//
//  HubApi+default.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 21.04.2025.
//

import Foundation
@preconcurrency import Hub

/// Extension providing a default HubApi instance for downloading model files
extension HubApi {
    /// The base directory models are downloaded into, exposed so other types can
    /// locate a model's on-disk files (HubApi.downloadBase itself is internal).
    static let downloadBaseURL: URL = {
        #if os(macOS)
            URL.downloadsDirectory.appending(path: "huggingface")
        #else
            URL.cachesDirectory.appending(path: "huggingface")
        #endif
    }()

    /// Default HubApi instance configured to download models to the user's Downloads
    /// directory (macOS) or Caches directory (iOS) under a 'huggingface' subdirectory.
    static let `default` = HubApi(downloadBase: downloadBaseURL)
}
