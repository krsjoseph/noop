import SwiftUI

// MARK: - Grouped-list settings kit (native iOS idiom)
//
// The locked Settings surface. Replaces the old heavy "titled card + paragraph blurb per
// section" with the standard iOS grouped-list: a light overline header, one rounded glass
// group of simple rows (icon + label + trailing value/chevron/toggle/control), and an
// optional grey footnote caption (where the old per-section blurbs now live, de-noised to a
// line). Dividers are inserted automatically between rows, inset past the icon.
//
// Built on `NoopCard`, so the group is glass-aware (refracts the day-cycle scene on iOS 26)
// and falls back to the frosted surface below iOS 26 / on macOS — same as every other card.

// MARK: Group

public struct SettingsGroup<Content: View>: View {
    let header: String?
    let footer: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    public init(header: String? = nil, footer: LocalizedStringKey? = nil,
                @ViewBuilder content: @escaping () -> Content) {
        self.header = header; self.footer = footer; self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            if let header {
                Text(header).strandOverline()
                    .padding(.horizontal, NoopMetrics.space1)
            }
            // padding: 0 — the rows own their interior insets so the dividers and the icon
            // column line up to one grid across the group.
            NoopCard(padding: 0) {
                _VariadicView.Tree(SettingsRowLayout()) { content() }
            }
            if let footer {
                Text(footer)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NoopMetrics.space1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Stacks the group's rows with an inset hairline between each (none after the last). Uses
/// `_VariadicView` so call sites just list `SettingsRow`s — no manual divider bookkeeping.
private struct SettingsRowLayout: _VariadicView.MultiViewRoot {
    /// Leading inset so the divider starts past the icon column (row pad + icon + gap).
    static let dividerInset: CGFloat = NoopMetrics.space4 + SettingsRowMetrics.icon + NoopMetrics.space3

    @ViewBuilder func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != last {
                    Divider().overlay(StrandPalette.hairline)
                        .padding(.leading, Self.dividerInset)
                }
            }
        }
    }
}

enum SettingsRowMetrics {
    static let icon: CGFloat = 28
}

public extension View {
    /// Standard grouped-row insets, for free-form content placed inside a `SettingsGroup`
    /// alongside `SettingsRow`s (e.g. a status block, a button row, a paragraph) so it aligns
    /// to the same grid and the auto-inserted dividers line up.
    func settingsRowInsets() -> some View {
        self.padding(.horizontal, NoopMetrics.space4)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Row

public struct SettingsRow<Trailing: View>: View {
    let icon: String?
    let iconTint: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let value: String?
    let showsChevron: Bool
    let action: (() -> Void)?
    @ViewBuilder let trailing: () -> Trailing

    /// Control row: an arbitrary interactive trailing view (segmented `Picker`, `Menu`,
    /// `Toggle`). `showsChevron` defaults to false; pass an `action` only if the whole row
    /// should also be tappable (rare when there's a control).
    public init(icon: String? = nil, iconTint: Color = StrandPalette.accent,
                title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil,
                value: String? = nil, showsChevron: Bool = false,
                action: (() -> Void)? = nil,
                @ViewBuilder trailing: @escaping () -> Trailing) {
        self.icon = icon; self.iconTint = iconTint; self.title = title; self.subtitle = subtitle
        self.value = value; self.showsChevron = showsChevron; self.action = action; self.trailing = trailing
    }

    public var body: some View {
        // Top-align when a (possibly multi-line) subtitle is present so a trailing toggle / value
        // sits beside the title, not floating against the centre of a tall paragraph.
        let row = HStack(alignment: subtitle == nil ? .center : .top, spacing: NoopMetrics.space3) {
            if let icon { iconSquare(icon) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: NoopMetrics.space2)
            if let value {
                Text(value)
                    .font(StrandFont.body)
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
            }
            trailing()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, NoopMetrics.space4)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .contentShape(Rectangle())

        if let action {
            Button { StrandHaptic.selection.play(); action() } label: { row }
                .buttonStyle(StrandPressableButtonStyle(cornerRadius: 0))
        } else {
            row
        }
    }

    private func iconSquare(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(iconTint.opacity(0.16))
            .frame(width: SettingsRowMetrics.icon, height: SettingsRowMetrics.icon)
            .overlay(
                Image(systemName: name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconTint)
            )
            .accessibilityHidden(true)
    }
}

// Navigation / disclosure row (value + chevron, whole row tappable). The common case, so it
// gets a no-trailing convenience that defaults `Trailing` to `EmptyView` and the chevron on.
public extension SettingsRow where Trailing == EmptyView {
    init(icon: String? = nil, iconTint: Color = StrandPalette.accent,
         title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil,
         value: String? = nil, showsChevron: Bool = true,
         action: (() -> Void)? = nil) {
        self.init(icon: icon, iconTint: iconTint, title: title, subtitle: subtitle,
                  value: value, showsChevron: showsChevron, action: action, trailing: { EmptyView() })
    }
}

