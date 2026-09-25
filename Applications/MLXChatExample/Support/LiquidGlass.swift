//
//  LiquidGlass.swift
//  MLXChatExample
//

import SwiftUI

extension View {
    /// Applies the platform's Liquid Glass material where available.
    ///
    /// On iOS 26+/macOS 26+ this uses the native `glassEffect` material, which
    /// automatically picks up the Liquid Glass refinements shipped with iOS 27
    /// (improved content diffusion, darkened edges and brighter specular highlights)
    /// at runtime. On older systems it falls back to a regular material background.
    @ViewBuilder
    func liquidGlassBackground(in shape: some Shape = .rect(cornerRadius: 24)) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}
