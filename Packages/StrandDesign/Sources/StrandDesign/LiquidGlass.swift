import SwiftUI

// MARK: - Liquid Glass surface (iOS 26+)
//
// The Today dashboard floats its cards over the scenic day-cycle backdrop as real iOS 26
// Liquid Glass — translucent, light-refracting material that samples the scene behind it —
// instead of the opaque `FrostedCardSurface` fill. This file holds the one place that look
// lives so every card on Today (NoopCard / StatTile / ChartCard / InsightCard all route
// through NoopCard) picks it up via a scoped environment flag, with NO change to other screens.
//
// Availability: `.glassEffect` / `GlassEffectContainer` are iOS 26 only; the app deploys to
// iOS 17 (project.yml) and also ships on macOS. So every glass path is gated
// `if #available(iOS 26.0, *)` and falls back to the existing `FrostedCardSurface` everywhere
// else — call sites stay identical and the screen is byte-identical on iOS 17–25 / macOS.
//
// Contrast: glass only reads well over something to refract. Today turns the flag ON only when
// the scenic backdrop is showing; with the scene OFF (flat canvas) the flag is left false so
// cards fall back to the opaque frosted plate and legibility is never sacrificed.

// MARK: Environment flag

private struct NoopGlassSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// When true, `NoopCard` (and everything built on it) renders as iOS 26 Liquid Glass instead
    /// of the opaque frosted surface. Scoped per subtree — set it on the Today content only.
    /// No-op below iOS 26 / on macOS (the glass modifier falls back to the frosted surface).
    var noopGlassSurface: Bool {
        get { self[NoopGlassSurfaceKey.self] }
        set { self[NoopGlassSurfaceKey.self] = newValue }
    }
}

// MARK: Glass card surface

public extension View {
    /// Render the receiver as a Liquid Glass card on iOS 26+, falling back to `FrostedCardSurface`
    /// as a background everywhere else. `tint` lightly colours the glass (per-domain wash) the same
    /// way it tints the frosted surface, so a metric tile still reads in its colour world.
    @ViewBuilder
    func liquidGlassCard(tint: Color? = nil, cornerRadius: CGFloat = NoopMetrics.cardRadius) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            // `.regular` is the legible, heavily-frosting variant — it keeps dark text crisp even over
            // the bright sunrise scene. A faint tint carries domain identity without washing the glass out.
            let glass: Glass = {
                if let tint { return .regular.tint(tint.opacity(0.18)) }
                return .regular
            }()
            self.glassEffect(glass, in: shape)
        } else {
            self.background { FrostedCardSurface(tint: tint, cornerRadius: cornerRadius) }
        }
        #else
        self.background { FrostedCardSurface(tint: tint, cornerRadius: cornerRadius) }
        #endif
    }
}

// MARK: Glass cluster container

/// Groups adjacent glass cards so their effects blend/morph correctly and composite efficiently
/// (Apple's `GlassEffectContainer`). On iOS 26 it wraps the content in a container with the house
/// card gap as the blend spacing; everywhere else it's a transparent passthrough, so call sites are
/// identical across platforms and OS versions. Use sparingly — one container around a visual unit
/// (e.g. the hero), NOT around the whole scrolling list, so a long lazy column still materialises lazily.
public struct GlassClusterContainer<Content: View>: View {
    private let spacing: CGFloat
    @ViewBuilder private let content: () -> Content

    public init(spacing: CGFloat = NoopMetrics.gap, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}
