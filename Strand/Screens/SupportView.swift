import SwiftUI
import StrandDesign

/// Support — attribution + optional crypto donations. Never a paywall; the whole app works without it.
struct SupportView: View {
    @State private var copied: String?
    @State private var selected = "BTC"

    // Day-cycle scene + Liquid Glass, shared with Today/Trends/Settings so Support reads as the same
    // surface. Gated on the existing `showDayCycleBackground` toggle; glass falls back to frosted below
    // iOS 26 / on macOS (where the SupportModalOverlay panel keeps its own frosted chrome).
    @AppStorage(SceneBackgroundPrefs.enabledKey) private var showDayCycleBackground = true
    private var useGlassSurface: Bool {
        #if os(iOS)
        return showDayCycleBackground
        #else
        return false
        #endif
    }

    var body: some View {
        ScreenScaffold(title: "Support",
                       subtitle: "\(ProjectInfo.appName) is free and always will be. If it's useful to you, you can chip in to help with development and testing costs. Totally optional.",
                       // Shared day-cycle scene behind the header (flattened to one GPU layer), as on Today.
                       topBackground: showDayCycleBackground
                           ? AnyView(SceneScreenBackground().drawingGroup()) : nil) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                    SectionHeader("Support the build", overline: "Optional")
                    donateCard
                }
                .staggeredAppear(index: 0)
                VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    contactGroup
                    builtOnGroup
                }
                .staggeredAppear(index: 1)
                disclaimerCard
                    .staggeredAppear(index: 2)
            }
        }
        // Liquid Glass for the donate card + Settings groups (NoopCard / SettingsGroup, glass-aware).
        // Cascades via the environment; neutral glass when on, frosted fallback otherwise.
        .environment(\.noopGlassSurface, useGlassSurface)
    }

    /// Help & contact — the native grouped-list idiom: one disclosure row that opens the user's mail
    /// client, with the explanatory sentence relocated to the grey group footer.
    private var contactGroup: some View {
        SettingsGroup(
            header: "Help & contact",
            footer: "Questions, feedback, bugs — \(ProjectInfo.contactEmail)."
        ) {
            SettingsRow(icon: "envelope.fill", title: "Get in touch",
                        action: {
                            if let url = URL(string: "mailto:\(ProjectInfo.contactEmail)") { PlatformOpen.url(url) }
                        })
                .accessibilityLabel("Email \(ProjectInfo.contactEmail)")
                .help("Email \(ProjectInfo.contactEmail)")
        }
    }

    /// Built on — the community reverse-engineering this stands on. A free-form inset block inside a
    /// grouped card: repo names in SF Rounded (subhead), the per-line note in a muted footnote.
    private var builtOnGroup: some View {
        SettingsGroup(header: "Built on") {
            VStack(alignment: .leading, spacing: 12) {
                Text("This stands on community reverse-engineering. Huge thanks:")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(ProjectInfo.attributions.enumerated()), id: \.element.repo) { index, a in
                    if index > 0 { Divider().overlay(StrandPalette.hairline) }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(StrandPalette.accent).accessibilityHidden(true)
                            Text(a.repo).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        Text(a.note).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .settingsRowInsets()
        }
    }

    private var donateCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StrandPalette.metricRose)
                        .frame(width: 28, height: 28)
                        .background(StrandPalette.metricRose.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Support the build").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                }
                Text("Kineva is free and always will be, nothing is locked. It cost real money and a lot of unpaid hours to build, and there's a Windows app, an Android app and an iOS app I want to ship next. If it's useful to you and you want to help with the development and testing costs, even a few quid in crypto genuinely keeps it moving, and honestly it keeps me motivated to keep building.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Privacy note — a plain inset row, not a card-in-card fill (it would fight the glass).
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(StrandPalette.accent)
                        .font(.system(size: 13)).accessibilityHidden(true)
                    Text("I keep this project anonymous, so crypto is the only way to chip in — no Patreon, no PayPal, no name attached. Quick, global, and private for both of us.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Pick a coin → scan the QR or copy the address.
                HStack(spacing: 0) {
                    SegmentedPillControl(ProjectInfo.donations.map(\.symbol), selection: $selected) { $0 }
                    Spacer(minLength: 0)
                }

                if let coin = ProjectInfo.donations.first(where: { $0.symbol == selected }) {
                    HStack(alignment: .top, spacing: 16) {
                        qrView(coin.address)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Scan with any \(coin.name) wallet")
                                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                            Text(coin.address)
                                .font(StrandFont.mono(11)).foregroundStyle(StrandPalette.textSecondary)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Button {
                                PlatformPasteboard.copy(coin.address)
                                withAnimation { copied = coin.symbol }
                            } label: {
                                Label(copied == coin.symbol ? "Copied!" : "Copy address",
                                      systemImage: copied == coin.symbol ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(NoopButtonStyle(.secondary))
                            .accessibilityLabel("Copy \(coin.name) address")
                        }
                        Spacer(minLength: 0)
                    }
                }

                Text("Any amount helps. Thank you — genuinely.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    /// Black-on-white QR so wallet cameras read it cleanly against the dark UI.
    private func qrView(_ address: String) -> some View {
        Group {
            if let img = QRCode.image(for: address) {
                Image(platformImage: img).resizable().interpolation(.none)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(StrandPalette.surfaceInset)
            }
        }
        .frame(width: 150, height: 150)
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("Donation QR code")
    }

    private var disclaimerCard: some View {
        NoopCard(padding: 18) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundStyle(StrandPalette.textTertiary)
                    .font(.system(size: 13)).accessibilityHidden(true)
                Text("Not affiliated with, endorsed by, or connected to WHOOP. Interoperability software for hardware you own and your own data. Use it only with a device you own, and not in breach of any agreement that applies to you. Not a medical device.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Hosts ``SupportView`` as a centred panel over a dimmed backdrop. Clicking anywhere
/// outside the panel — or pressing Esc, or the ✕ — closes it. Taps on the panel itself
/// are absorbed (the panel is opaque) so its controls keep working.
struct SupportModalOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.45))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }

            SupportView()
                .frame(width: 560, height: 680)
                .background(StrandPalette.surfaceBase,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                    .accessibilityLabel("Close Support")
                }
                .shadow(color: Color.black.opacity(0.5), radius: 30, x: 0, y: 14)
        }
        #if os(macOS)
        .onExitCommand { isPresented = false }   // Esc-to-close is a macOS-only command
        #endif
        .transition(.opacity)
    }
}
