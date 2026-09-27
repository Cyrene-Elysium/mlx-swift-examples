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

    /// Interactive Liquid Glass in a capsule silhouette. Used by the prompt
    /// bar, whose ends are fully semicircular regardless of bar height.
    func interactiveCapsuleGlassBackground() -> some View {
        glassEffect(.regular.interactive(), in: .capsule)
    }

    /// Glass card that visibly reacts to a press.
    ///
    /// `glassEffect(.regular.interactive())` alone only tracks the *system*
    /// press state of a real `Button` styled with `.glass`; a plain tappable
    /// card rendered with `.buttonStyle(.plain)` never tells the glass it is
    /// being pressed, so no highlight blooms. `GlassPressButtonStyle` adds the
    /// missing ingredient — an explicit press-driven scale + brightness lift
    /// on top of the interactive glass — so cards feel alive under the finger.
}

/// Button style that renders a glass capsule/rounded surface and animates a
/// bright press highlight scaled from the touch point. Used where a real
/// button needs an unmistakable HDR-style bloom.
///
/// Note: this style deliberately does **not** install a `contentShape`. Doing
/// so makes the whole surface claim every touch, which swallows the horizontal
/// drag that `List` uses for `swipeActions` — cards rendered with this style
/// became impossible to swipe-delete. Callers that need a precise hit area add
/// their own `contentShape` inside the label instead.
struct GlassPressButtonStyle: ButtonStyle {
    var shape: AnyShape = AnyShape(.capsule)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(
                .regular.interactive(),
                in: shape
            )
            .brightness(configuration.isPressed ? 0.12 : 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}
