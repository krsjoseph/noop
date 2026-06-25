import SwiftUI

// MARK: - Metric status card (Bevel "Sleep Trends" pattern)
//
// A glanceable metric row: a tinted leading icon + label, a big tabular value with its unit,
// a status line (glyph + word, colour-coded), and a trailing mini sparkline. Severity is
// carried by GLYPH AND COLOUR — never colour alone (DESIGN §1.6). Built on `NoopCard`, so it
// shares the glass surface. Used by Sleep's "Night detail" grid and Trends' "Daily signals".
//
// Sizes to its content (no fixed height) and fills its grid cell, so a single column on
// iPhone reads as full-width rows and a wide iPad column packs two-up — uniformly.

public struct MetricStatusCard: View {
    let icon: String
    let iconTint: Color
    let label: LocalizedStringKey
    let value: String
    var unit: String? = nil
    /// Status word (e.g. "Trending up", "Low", "Typical"). Paired with `statusGlyph`.
    var statusText: String? = nil
    /// SF Symbol carrying the same meaning as `statusColor` (so severity isn't colour-only).
    var statusGlyph: String? = nil
    var statusColor: Color = StrandPalette.textTertiary
    var sparkline: [Double]? = nil
    var sparkColor: Color = StrandPalette.accent
    /// Optional explicit sparkline range so flat-ish series don't auto-fit to a noisy band.
    var sparkRange: ClosedRange<Double>? = nil
    var onTap: (() -> Void)? = nil

    public init(icon: String, iconTint: Color = StrandPalette.accent,
                label: LocalizedStringKey, value: String, unit: String? = nil,
                statusText: String? = nil, statusGlyph: String? = nil,
                statusColor: Color = StrandPalette.textTertiary,
                sparkline: [Double]? = nil, sparkColor: Color = StrandPalette.accent,
                sparkRange: ClosedRange<Double>? = nil, onTap: (() -> Void)? = nil) {
        self.icon = icon; self.iconTint = iconTint; self.label = label; self.value = value
        self.unit = unit; self.statusText = statusText; self.statusGlyph = statusGlyph
        self.statusColor = statusColor; self.sparkline = sparkline; self.sparkColor = sparkColor
        self.sparkRange = sparkRange; self.onTap = onTap
    }

    public var body: some View {
        let card = NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                HStack(spacing: NoopMetrics.space2) {
                    iconSquare
                    Text(label).strandOverline()
                    Spacer(minLength: NoopMetrics.space2)
                    #if !os(watchOS)
                    // `Sparkline` is excluded on watchOS (its hover/Charts chrome doesn't apply on the
                    // tiny watch surface), so the inline trend mini-chart is iOS/macOS only.
                    if let sparkline, sparkline.count > 1 {
                        Sparkline(values: sparkline,
                                  gradient: Gradient(colors: [sparkColor.opacity(0.5), sparkColor]),
                                  range: sparkRange, showsHover: false)
                            .frame(width: 64, height: 26)
                            .accessibilityHidden(true)
                    }
                    #endif
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(StrandFont.number(28, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let unit {
                        Text(unit)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                if let statusText {
                    HStack(spacing: 5) {
                        if let statusGlyph {
                            Image(systemName: statusGlyph)
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(statusText)
                            .font(StrandFont.subhead.weight(.semibold))
                    }
                    .foregroundStyle(statusColor)
                }
            }
        }
        .accessibilityElement(children: .combine)

        if let onTap {
            Button { StrandHaptic.selection.play(); onTap() } label: { card }
                .buttonStyle(StrandPressableButtonStyle())
        } else {
            card
        }
    }

    private var iconSquare: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(iconTint.opacity(0.16))
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconTint)
            )
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("MetricStatusCard") {
    let cols = [GridItem(.adaptive(minimum: 320), spacing: 12)]
    return LazyVGrid(columns: cols, spacing: 12) {
        MetricStatusCard(icon: "waveform.path.ecg", iconTint: StrandPalette.metricPurple,
                         label: "Heart rate variability", value: "58", unit: "ms",
                         statusText: "Trending up", statusGlyph: "arrow.up.right",
                         statusColor: StrandPalette.statusPositive,
                         sparkline: (0..<30).map { 50 + 10 * sin(Double($0) / 4) },
                         sparkColor: StrandPalette.metricPurple)
        MetricStatusCard(icon: "heart.fill", iconTint: StrandPalette.metricRose,
                         label: "Resting heart rate", value: "52", unit: "bpm",
                         statusText: "Steady", statusGlyph: "equal",
                         statusColor: StrandPalette.textTertiary,
                         sparkline: (0..<30).map { 52 + 2 * sin(Double($0) / 6) },
                         sparkColor: StrandPalette.metricRose)
    }
    .padding(20)
    .frame(width: 420)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
