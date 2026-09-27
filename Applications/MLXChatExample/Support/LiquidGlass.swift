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

    /// Interactive Liquid Glass: same material, but with the system's
    /// press highlight that blooms outward from the touch point — the
    /// effect used by Apple's own apps for tappable glass cards.
    func interactiveGlassBackground(in shape: some Shape = .rect(cornerRadius: 24)) -> some View {
        glassEffect(.regular.interactive(), in: shape)
    }

    /// Interactive Liquid Glass whose corner curvature follows the device's
    /// container (screen) corner radius via `ConcentricRectangle`, so the
    /// capsule visually parallels the physical screen edge. Used by the
    /// prompt bar, which spans the width of the screen.
    func concentricInteractiveGlassBackground() -> some View {
        glassEffect(
            .regular.interactive(),
            in: ConcentricRectangle(corners: .containerConcentric, isUniform: true))
    }
}
