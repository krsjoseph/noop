#if os(iOS)
import SwiftUI
import StrandDesign

/// iOS navigation shell. macOS uses a `NavigationSplitView` sidebar (`RootView`); on iPhone the
/// natural analogue is a `TabView` with the most-used screens as tabs and everything else under a
/// "More" list. Every screen is the same `StrandDesign`-built view the macOS app uses.
struct RootTabView: View {
    @EnvironmentObject private var repo: Repository
    /// Cross-screen navigation requests (e.g. Live → "Manage devices"). Devices isn't a tab — it lives
    /// behind the More list — so a request presents it as a sheet, matching the quick-action screens.
    @EnvironmentObject private var router: NavRouter

    /// Which quick-action screen the centre FAB is presenting (nil = sheet closed).
    @State private var quickAction: QuickAction?
    /// Presents the Devices manager (pair / switch bands) when a screen asks the shell to open it.
    @State private var showDevices = false
    /// A routed v5 pillar screen (Insights hub / Lab Book / fused record / Rhythm) presented as a sheet
    /// when a hub row deep-links to it via NavRouter. nil = closed.
    @State private var routedPillar: NavRouter.Destination?
    /// Selected tab — bound so tab switches can crossfade (README §Motion: ~240ms opacity swap
    /// between tab roots, calm easing). Defaults to Today.
    @State private var selectedTab: Int = 0

    init() {
        // iOS 26+ renders the native Liquid Glass tab bar — leave its appearance untouched so the
        // adaptive glass shows. Only on older OSes do we pin the opaque Titanium bar (surfaceBase fill,
        // cleared selection tint so there's no stray pill behind the selected icon).
        if #unavailable(iOS 26.0) {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(StrandPalette.surfaceBase)
            appearance.selectionIndicatorTintColor = .clear
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    var body: some View {
        // Native iOS 26 Liquid Glass tab bar: SwiftUI renders Apple's adaptive glass + selection pill
        // automatically and the screens' content scrolls underneath it, so the bar genuinely refracts
        // what's behind it (the custom FloatingTabBar couldn't — it sat on the flat opaque surface).
        // On iOS < 26 this is the standard system tab bar.
        TabView(selection: $selectedTab) {
            tab(TodayView(), "Today", "square.grid.2x2").tag(0)
            tab(TrendsView(), "Trends", "chart.line.uptrend.xyaxis").tag(1)
            tab(SleepView(), "Sleep", "bed.double").tag(2)
            moreTab.tag(3)
        }
        .tint(StrandPalette.accent)
        // Tab crossfade — README §Motion: ~240ms opacity swap between tab roots, global calm
        // easing cubic-bezier(0.22,1,0.36,1).
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24), value: selectedTab)
        .task { await repo.refresh() }
        // Quick-action sheet presents with the calm easing (~0.42s) per the README sheet spec —
        // the easing is applied where `quickAction` is set (see `presentQuickAction`), keeping the
        // animation scoped to the sheet rather than the whole shell.
        .sheet(item: $quickAction) { action in
            quickActionDestination(action)
        }
        // Live's "Manage devices" affordance (and any future cross-screen link to Devices) routes here:
        // present the Devices manager in its own nav stack, the same way the quick-action screens do.
        .sheet(isPresented: $showDevices) {
            devicesScreen
        }
        // v5 pillar deep-links (Insights hub / Lab Book / fused record / Rhythm) present as a sheet in
        // their own nav stack — the same idiom the quick-action + Devices screens use on iPhone.
        .sheet(item: $routedPillar) { dest in
            pillarScreen(dest)
        }
        // Honour a router request: Devices keeps its dedicated sheet; the v5 pillars route through the
        // shared pillar sheet. Cleared so the same tap can fire again later.
        .onChange(of: router.requestedDestination) { _, dest in
            switch dest {
            case .devices:
                showDevices = true
                router.requestedDestination = nil
            case .insightsHub, .labBook, .fusedRecord, .rhythm:
                routedPillar = dest
                router.requestedDestination = nil
            case .trends:
                // Trends is a primary tab on iPhone (not a pillar sheet) — switch to it.
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { selectedTab = 1 }
                router.requestedDestination = nil
            case nil:
                break
            }
        }
        // A screen's top-bar "+" routes here: open the quick-action sheet, then clear the flag.
        .onChange(of: router.quickActionsRequested) { _, req in
            if req {
                withAnimation(Self.sheetEase) { quickAction = .menu }
                router.quickActionsRequested = false
            }
        }
    }

    /// A routed v5 pillar screen wrapped in its own nav stack + Done button (mirrors `quickScreen`).
    @ViewBuilder
    private func pillarScreen(_ dest: NavRouter.Destination) -> some View {
        NavigationStack {
            Group {
                switch dest {
                case .insightsHub: InsightsHubView()
                case .labBook: LabBookView()
                case .fusedRecord: FusedRecordHost()
                case .rhythm: RhythmHost(onClose: { routedPillar = nil })
                case .devices: DevicesView()
                // .trends is never presented as a pillar sheet on iPhone (it's a primary tab — the
                // requestedDestination handler switches `selectedTab` instead), but the switch must stay
                // exhaustive. Fall back to Trends inside the sheet host if it ever arrives here.
                case .trends: TrendsView()
                }
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(StrandPalette.surfaceBase, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { routedPillar = nil }
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
    }

    /// Calm-easing curve (cubic-bezier(0.22,1,0.36,1)) at the README sheet-present duration.
    private static let sheetEase = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)

    // MARK: - Quick-action sheet

    /// Routes a chosen quick action to the existing screen, or shows the action menu itself.
    @ViewBuilder
    private func quickActionDestination(_ action: QuickAction) -> some View {
        switch action {
        case .menu:
            QuickActionSheet { picked in
                // Swap the menu for the chosen destination on the next runloop so the sheet
                // re-presents cleanly (avoids dismiss/re-present races). Calm easing on re-present.
                quickAction = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(Self.sheetEase) { quickAction = picked }
                }
            }
            .presentationDetents([.height(344)])
            .presentationDragIndicator(.hidden)
        case .live:
            quickScreen(LiveView())
        case .workout:
            quickScreen(WorkoutsView())
        case .journal:
            quickScreen(InsightsView())
        case .breathe:
            quickScreen(BreathingView())
        }
    }

    /// Wraps a routed quick-action screen in its own nav stack so it has a title bar + the
    /// shared surface background, matching how the More-tab links present these same views.
    private func quickScreen<V: View>(_ view: V) -> some View {
        NavigationStack {
            view
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(StrandPalette.surfaceBase, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { quickAction = nil }
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
        }
    }

    /// The Devices manager wrapped in its own nav stack + Done button (mirrors `quickScreen`, but
    /// dismisses the dedicated `showDevices` sheet rather than the quick-action item).
    private var devicesScreen: some View {
        NavigationStack {
            DevicesView()
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(StrandPalette.surfaceBase, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDevices = false }
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
        }
    }

    private func tab<V: View>(_ view: V, _ title: LocalizedStringKey, _ icon: String) -> some View {
        // Each primary tab gets its OWN NavigationStack so the in-content NavigationLinks (e.g. the Today
        // dashboard card rows) both navigate AND render opaque. An ORPHANED NavigationLink (no
        // NavigationStack ancestor) renders its whole label in a disabled/translucent state — that was
        // washing the Today cards over the hero scene and dimming their text to grey (Aaron 2026-06-23).
        // The root view hides the system nav bar (each screen draws its own in-content header); pushed
        // detail screens get their own nav bar + back button.
        NavigationStack {
            view
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
        }
        .tabItem { Label(title, systemImage: icon) }
    }

    // The "More" tab is the app's catch-all index. Earlier passes moved it off the system `List`
    // onto ScreenScaffold + a bespoke `moreSection`/`MoreRow` (overline header over a grouped NoopCard
    // with hand-drawn hairlines + bare accent line-icons). That *almost* matched Settings — but Settings
    // is the app's locked grouped-list surface (`SettingsGroup`/`SettingsRow`: tinted icon tiles,
    // auto-inset dividers, a one-line group footer, haptic press feedback), and More is the same idiom.
    // So More now composes from that exact kit — one less bespoke list to keep in sync, and the footers
    // give each group the calm one-line "what's in here" the index was missing (DESIGN §1, §6).
    private var moreTab: some View {
        NavigationStack {
            ScreenScaffold(title: "More", subtitle: "Everything else, one tap away") {
                SettingsGroup(header: "Insights",
                              footer: "Coaching, correlations and what's actually moving your numbers.") {
                    moreLink("What Moves You", "wand.and.sparkles") { InsightsHubView() }
                    moreLink("Intelligence", "brain.head.profile") { IntelligenceView() }
                    moreLink("Coach", "sparkles") { CoachView() }
                    moreLink("Insights", "lightbulb.fill") { InsightsView() }
                    moreLink("Explore", "square.grid.2x2.fill") { MetricExplorerView() }
                    moreLink("Compare", "rectangle.split.2x1.fill") { CompareView() }
                }
                SettingsGroup(header: "Body",
                              footer: "Live signals, workouts, breathing and your body's tools.") {
                    moreLink("Live", "waveform.path.ecg") { LiveView() }
                    moreLink("Workouts", "figure.run") { WorkoutsView() }
                    moreLink("Health", "heart.text.square.fill") { HealthView() }
                    moreLink("Lab Book", "books.vertical.fill") { LabBookView() }
                    moreLink("Stress", "bolt.heart.fill") { StressView() }
                    moreLink("Breathe", "wind") { BreathingView() }
                    moreLink("Intervals", "timer") { IntervalTimerView() }
                    // Experimental beat-to-beat regularity visualization — self-gates on its own consent.
                    moreLink("Rhythm", "waveform.path") { RhythmHost() }
                }
                SettingsGroup(header: "Data",
                              footer: "Where your numbers come from — and how to move them in and out.") {
                    moreLink("Your Data, Fused", "square.stack.3d.up.fill") { FusedRecordHost() }
                    moreLink("Apple Health", "heart.fill") { AppleHealthView() }
                    moreLink("Mi Band", "figure.walk.motion") { XiaomiBandView() }
                    moreLink("Data Sources", "externaldrive.fill") { DataSourcesView() }
                    // #155: HealthKit-free Apple Health path for sideloaded installs (Siri Shortcut
                    // reads the opt-in Documents/noop_sync.txt drop file).
                    moreLink("Shortcuts Export", "square.and.arrow.up.fill") { ShortcutExportSettingsView() }
                }
                SettingsGroup(header: "App",
                              footer: "Automations, shortcuts, settings and support.") {
                    moreLink("Automations", "wand.and.stars") { AutomationsView() }
                    moreLink("Siri & Shortcuts", "mic.fill") { SiriShortcutsSettingsView() }
                    moreLink("Settings", "gearshape.fill") { SettingsView() }
                    moreLink("Support", "hands.clap.fill") { SupportView() }
                }
            }
        }
        .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
    }

    /// One tappable destination row in the More index, built from the locked grouped-list kit. The row's
    /// visual is a plain `SettingsRow` (tinted-square icon + body label + chevron) used purely as a label;
    /// the navigation is the codebase's closure-based `NavigationLink` so each screen pushes directly — the
    /// `value` + `.navigationDestination(for:)` pairing double-pushes here (#38). `StrandPressableButtonStyle`
    /// gives edge-to-edge press feedback (square corners — the row spans the group, dividers between) and the
    /// selection haptic matches every other tappable row. Each destination keeps the per-screen wrapper the
    /// old row applied (`surfaceBase` background, inline title-bar, toolbar background).
    private func moreLink<Destination: View>(_ title: LocalizedStringKey, _ icon: String,
                                             @ViewBuilder _ destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(StrandPalette.surfaceBase, for: .navigationBar)
        } label: {
            SettingsRow(icon: icon, title: title)
        }
        .buttonStyle(StrandPressableButtonStyle(cornerRadius: 0))
        .simultaneousGesture(TapGesture().onEnded { StrandHaptic.selection.play() })
    }
}

// MARK: - Quick actions (centre FAB)

/// The destinations the centre FAB can present. `.menu` is the action sheet itself; the rest
/// route to existing screens. `Identifiable` so it drives `.sheet(item:)`.
private enum QuickAction: Int, Identifiable {
    case menu, live, workout, journal, breathe
    var id: Int { rawValue }
}

/// The bottom sheet of quick actions presented by the centre FAB. Spec bottom sheet: surfaceOverlay
/// fill, gold hairline top edge, grab handle, three flat action rows that route to existing screens.
private struct QuickActionSheet: View {
    /// Called with the picked destination (the host swaps the menu for that screen).
    let onPick: (QuickAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Grab handle (36×4) in the slate hairline tone.
            Capsule()
                .fill(StrandPalette.hairlineStrong)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            Text("QUICK ACTIONS")
                .font(StrandFont.overline)
                .tracking(1.6)
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            VStack(spacing: 8) {
                row("Live HR", icon: "waveform.path.ecg", tint: StrandPalette.metricRose) { onPick(.live) }
                row("Start workout", icon: "figure.run", tint: StrandPalette.effortColor) { onPick(.workout) }
                row("Log journal", icon: "square.and.pencil", tint: StrandPalette.accent) { onPick(.journal) }
                row("Breathe", icon: "wind", tint: StrandPalette.restColor) { onPick(.breathe) }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            StrandPalette.surfaceOverlay
                .overlay(alignment: .top) {
                    // Gold hairline top edge per the bottom-sheet spec.
                    Rectangle()
                        .fill(StrandPalette.gold.opacity(0.35))
                        .frame(height: 1)
                }
                .ignoresSafeArea()
        )
    }

    /// One flat action row: hued line-icon tile + title, inset surface, hairline border.
    private func row(_ title: LocalizedStringKey, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(StrandPalette.surfaceInset))
                Text(title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(StrandPalette.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
