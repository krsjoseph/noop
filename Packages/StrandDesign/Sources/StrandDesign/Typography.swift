import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Strand Typography (§9.2)
//
// SF Rounded everywhere (the house face): Apple's rounded system design, the same
// friendly numerals the Fitness/Activity rings use. Tabular/monospaced digits on every
// numeric role so live values don't reflow. SF Mono stays for raw/log views. Overline =
// sparing ALL-CAPS w/ wide tracking.
//
// Custom point sizes are preserved AND keep Dynamic Type scaling: a fixed-size rounded
// UIFont can't scale on its own, so the scaled roles run it through `UIFontMetrics` for
// their text style (the iOS 16 / macOS 13 floor). macOS has no UIFontMetrics — it uses
// SwiftUI's `.system(design: .rounded)` directly (fixed size, which Mac windows expect).
//
// All numeric styles use `.monospacedDigit()` so live values don't reflow.

public enum StrandFont {

    // MARK: Family — SF Rounded

    /// SF Rounded at a FIXED size/weight — used by the big gauge/tile numerals (`display`,
    /// `rounded`, `number`) that live in fixed-geometry rings/tiles where unbounded growth would
    /// overflow. Prose and inline-number roles use `roundedScaled` instead.
    private static func roundedFixed(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Like `roundedFixed`, but the size SCALES with the user's Dynamic Type / Larger Text setting,
    /// anchored to a matching text style. SwiftUI has no `.system(size:relativeTo:)`, so on iOS we build
    /// a rounded UIFont at `size` and scale it via `UIFontMetrics` for the role's text style; macOS falls
    /// back to a fixed-size rounded system font (Mac doesn't drive Dynamic Type the same way).
    private static func roundedScaled(_ size: CGFloat, weight: Font.Weight,
                                      relativeTo style: Font.TextStyle) -> Font {
        #if canImport(UIKit)
        let base = UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
        let rounded = base.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: size) } ?? base
        let scaled = UIFontMetrics(forTextStyle: uiTextStyle(style)).scaledFont(for: rounded)
        return Font(scaled)
        #else
        return .system(size: size, weight: weight, design: .rounded)
        #endif
    }

    #if canImport(UIKit)
    /// Map a SwiftUI `Font.Weight` to the `UIFont.Weight` used to build the scalable rounded UIFont.
    /// `Font.Weight` is an opaque struct (not a switchable enum), so this compares the known members.
    private static func uiWeight(_ w: Font.Weight) -> UIFont.Weight {
        switch w {
        case .black:      return .black
        case .heavy:      return .heavy
        case .bold:       return .bold
        case .semibold:   return .semibold
        case .medium:     return .medium
        case .light:      return .light
        case .thin:       return .thin
        case .ultraLight: return .ultraLight
        default:          return .regular
        }
    }

    /// Map a SwiftUI `Font.TextStyle` to the `UIFont.TextStyle` that anchors `UIFontMetrics` scaling.
    private static func uiTextStyle(_ s: Font.TextStyle) -> UIFont.TextStyle {
        switch s {
        case .largeTitle:  return .largeTitle
        case .title:       return .title1
        case .title2:      return .title2
        case .title3:      return .title3
        case .headline:    return .headline
        case .subheadline: return .subheadline
        case .body:        return .body
        case .callout:     return .callout
        case .footnote:    return .footnote
        case .caption:     return .caption1
        case .caption2:    return .caption2
        @unknown default:  return .body
        }
    }
    #endif

    // MARK: Scale (§9.2)

    /// Display 64–80 / Bold — the gauge score number. SF Rounded 700 with tight
    /// tracking (≈ -0.04em), tabular digits so a changing value never reflows.
    public static func display(_ size: CGFloat = 72) -> Font {
        roundedFixed(size, weight: .bold).monospacedDigit()
    }

    /// The tight tracking for big display numbers (≈ -0.04em). Apply alongside
    /// `display(_:)` at the use site, e.g. `.tracking(StrandFont.displayTracking(72))`.
    public static func displayTracking(_ size: CGFloat = 72) -> CGFloat {
        -size * 0.04
    }

    /// An SF Rounded numeric style at an arbitrary size/weight — the house
    /// numeral. Tabular so live values align. Use anywhere a score/number is shown.
    public static func rounded(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        roundedFixed(size, weight: weight).monospacedDigit()
    }

    /// Title1 28 / Bold. Scales with Dynamic Type.
    public static let title1 = roundedScaled(28, weight: .bold, relativeTo: .title)

    /// Title2 22 / Semibold. Scales with Dynamic Type.
    public static let title2 = roundedScaled(22, weight: .semibold, relativeTo: .title2)

    /// Headline 17 / Semibold. Scales with Dynamic Type.
    public static let headline = roundedScaled(17, weight: .semibold, relativeTo: .headline)

    /// Body 15 / Regular. Scales with Dynamic Type.
    public static let body = roundedScaled(15, weight: .regular, relativeTo: .body)

    /// Subhead 13. Scales with Dynamic Type.
    public static let subhead = roundedScaled(13, weight: .regular, relativeTo: .subheadline)

    /// Caption 12. Scales with Dynamic Type.
    public static let caption = roundedScaled(12, weight: .regular, relativeTo: .caption)

    /// Footnote 11. Scales with Dynamic Type.
    public static let footnote = roundedScaled(11, weight: .regular, relativeTo: .footnote)

    /// Overline 11 / Bold, +1.4 tracking (apply `.tracking(1.4)` at use site;
    /// `overlineText(_:)` does it for you). Sparing ALL-CAPS labels. Scales with Dynamic Type.
    public static let overline = roundedScaled(11, weight: .bold, relativeTo: .caption2)

    /// `overline` at a custom point size — same SF Rounded face, weight and Dynamic-Type scaling
    /// (relativeTo `.caption2`), just smaller. Passing 11 returns exactly `.overline`. Lets a caller
    /// shrink an ALL-CAPS label to fit a small container without losing accessibility text-scaling.
    public static func overlineScaled(_ size: CGFloat) -> Font {
        roundedScaled(size, weight: .bold, relativeTo: .caption2)
    }

    /// Mono 13 (SF Mono) — raw / log views. Tabular by nature.
    public static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)

    // MARK: Numeric variants (tabular digits)

    /// A numeric style at an arbitrary size/weight, for live values — SF Rounded,
    /// tabular digits. This is the tile/value numeral.
    public static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        roundedFixed(size, weight: weight).monospacedDigit()
    }

    /// SF Rounded body number — for inline live values that should align. Scales with Dynamic
    /// Type alongside its sibling `body`/`caption` labels so a value and its label stay matched.
    public static let bodyNumber = roundedScaled(15, weight: .medium, relativeTo: .body).monospacedDigit()

    /// SF Rounded caption number — for small live values (sparklines, chips). Scales with Dynamic Type.
    public static let captionNumber = roundedScaled(12, weight: .medium, relativeTo: .caption).monospacedDigit()

    /// Mono at an arbitrary size.
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// The recommended tracking for overline text (wide ALL-CAPS labels, ≈ 0.13em).
    public static let overlineTracking: CGFloat = 1.4
}

// MARK: - Text helpers

public extension Text {
    /// Style as an overline label: ALL-CAPS, bold, +1.4 tracking, tertiary text.
    func strandOverline() -> some View {
        self.font(StrandFont.overline)
            .tracking(StrandFont.overlineTracking)
            .textCase(.uppercase)
            .foregroundStyle(StrandPalette.textSecondary)
    }
}

public extension View {
    /// Convenience: an overline-styled label string.
    static func strandOverline(_ string: String) -> some View {
        Text(string).strandOverline()
    }
}

#if DEBUG
#Preview("Typography") {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text("88").font(StrandFont.display(72)).tracking(StrandFont.displayTracking(72)).foregroundStyle(StrandPalette.textPrimary)
            Text("Title 1 / Bold 28").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
            Text("Title 2 / Semibold 22").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            Text("Headline / Semibold 17").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
            Text("Body / Regular 15 — the thread of you, read in full.")
                .font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
            Text("Subhead 13").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            Text("Caption 12").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text("Footnote 11").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Text("Overline").strandOverline()
            Text("0xAA 41 00 1c crc32=f3a1  mono 13").font(StrandFont.mono).foregroundStyle(StrandPalette.textSecondary)
            HStack(spacing: 4) {
                Text("HRV").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text("62").font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textPrimary)
                Text("ms").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 520, height: 620)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
