//
//  LiquidGlass.swift
//  MLXChatExample
//
//  Created by İbrahim Çetin on 20.04.2025.
//

import SwiftUI

extension View {
    /// Applies the platform's Liquid Glass material.
    ///
    /// Uses the native `glassEffect` material, which automatically picks up
    /// the Liquid Glass refinements shipped with iOS 27 (improved content
    /// diffusion, darkened edges and brighter specular highlights) at runtime.
    func liquidGlassBackground(in shape: some Shape = .rect(cornerRadius: 24)) -> some View {
        glassEffect(in: shape)
    }
}
