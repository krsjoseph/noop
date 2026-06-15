import SwiftUI
import StrandDesign

enum NavItem: String, CaseIterable, Identifiable, Hashable {
    case today = "Today"
    case intelligence = "Intelligence"
    case coach = "Coach"
    case live = "Live"
    case breathe = "Breathe"
    case intervals = "Intervals"
    case explore = "Explore"
    case compare = "Compare"
    case insights = "Insights"
    case sleep = "Sleep"
    case trends = "Trends"
    case workouts = "Workouts"
    case health = "Health"
    case stress = "Stress"
    case appleHealth = "Apple Health"
    case dataSources = "Data Sources"
    case devices = "Devices"
    case notifications = "Notifications"
    case automation = "Automations"
    case smartAlarm = "Smart Alarm"
    case settings = "Settings"
    case support = "Support"

    var id: String { rawValue }

    /// Localized sidebar label. Each case maps to a string literal so Xcode extracts
    /// it into the String Catalog as an English (US) base entry.
    var titleKey: LocalizedStringKey {
        switch self {
        case .today: return "Today"
        case .intelligence: return "Intelligence"
        case .coach: return "Coach"
        case .live: return "Live"
        case .breathe: return "Breathe"
        case .intervals: return "Intervals"
        case .explore: return "Explore"
        case .compare: return "Compare"
        case .insights: return "Insights"
        case .sleep: return "Sleep"
        case .trends: return "Trends"
        case .workouts: return "Workouts"
        case .health: return "Health"
        case .stress: return "Stress"
        case .appleHealth: return "Apple Health"
        case .dataSources: return "Data Sources"
        case .devices: return "Devices"
        case .notifications: return "Notifications"
        case .automation: return "Automations"
        case .smartAlarm: return "Smart Alarm"
        case .settings: return "Settings"
        case .support: return "Support"
        }
    }

    var icon: String {
        switch self {
        case .today: return "circle.hexagongrid.fill"
        case .intelligence: return "brain.head.profile"
        case .coach: return "sparkles"
        case .live: return "waveform.path.ecg"
        case .breathe: return "lungs.fill"
        case .intervals: return "timer"
        case .explore: return "square.grid.2x2.fill"
        case .compare: return "chart.line.uptrend.xyaxis"
        case .insights: return "lightbulb.fill"
        case .sleep: return "moon.stars.fill"
        case .trends: return "chart.xyaxis.line"
        case .workouts: return "figure.run"
        case .health: return "heart.text.square.fill"
        case .stress: return "gauge.with.dots.needle.50percent"
        case .appleHealth: return "heart.fill"
        case .dataSources: return "square.and.arrow.down.fill"
        case .devices: return "badge.plus.radiowaves.right"
        case .notifications: return "bell.badge.fill"
        case .automation: return "wand.and.stars"
        case .smartAlarm: return "alarm.fill"
        case .settings: return "gearshape.fill"
        case .support: return "heart.fill"
        }
    }
}

struct RootView: View {
    // Observe only Repository (changes on data refresh, not the ~1 Hz HR/frame stream). The live
    // status pill is isolated into SidebarStatus so HR/frame ticks don't re-render the whole
    // NavigationSplitView shell + sidebar list.
    @EnvironmentObject var repo: Repository
    @State private var selection: NavItem? = .today

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(NavItem.allCases, selection: $selection) { item in
                    Label(item.titleKey, systemImage: item.icon)
                        .font(StrandFont.rounded(13, weight: .medium))
                        .tag(item)
                }
                .listStyle(.sidebar)

                Divider().overlay(StrandPalette.hairline)
                SidebarStatus().padding(.horizontal, 14).padding(.vertical, 12)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
            .safeAreaInset(edge: .top) { brand }
        } detail: {
            detail
                // Tab/section crossfade — README §Motion: "switching tabs uses a crossfade ~240ms",
                // global calm easing cubic-bezier(0.22,1,0.36,1). Opacity swap between detail roots
                // keyed on the selected nav item; restrained (no slide) for the desktop sidebar shell.
                .id(selection ?? .today)
                .transition(.opacity)
                .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24), value: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
        }
        .task { await repo.refresh() }
    }

    private var brand: some View {
        HStack(spacing: 8) {
            // In-app logo: the open recovery-ring mark so the wordmark reads as a true lockup
            // (README logo system — mark + "NOOP"). Flat gold gradient, low glow per the v3 restraint.
            BrandMark(size: 22)
            Text("NOOP")
                .font(StrandFont.rounded(20, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
    }

    @ViewBuilder private var detail: some View {
        switch selection ?? .today {
        case .today: TodayView()
        case .intelligence: IntelligenceView()
        case .coach: CoachView()
        case .live: LiveView()
        case .breathe: BreathingView()
        case .intervals: IntervalTimerView()
        case .explore: MetricExplorerView()
        case .compare: CompareView()
        case .insights: InsightsView()
        case .sleep: SleepView()
        case .trends: TrendsView()
        case .workouts: WorkoutsView()
        case .health: HealthView()
        case .stress: StressView()
        case .appleHealth: AppleHealthView()
        case .dataSources: DataSourcesView()
        case .devices: DevicesView()
        case .notifications: NotificationSettingsView()
        case .automation: AutomationsView()
        case .smartAlarm: SmartAlarmView()
        case .settings: SettingsView()
        case .support: SupportView()
        }
    }
}

/// The NOOP logo mark — an **open recovery ring** (~80% arc, round caps, starting at 12 o'clock)
/// with a **solid centre core dot** ("on-device core"), per the README logo system. Rendered in the
/// gold gradient and kept deliberately flat / low-glow for the v3 Titanium & Gold restraint. Drawn
/// purely from design tokens so it tracks the palette. Sized to optically x-height-match the wordmark.
struct BrandMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            // Open ring: leave ~20% of the circumference as a gap (trim 0 → 0.8), then rotate so the
            // gap sits at the top — the gold gradient sweeps clockwise from 12 o'clock.
            Circle()
                .trim(from: 0, to: 0.8)
                .stroke(
                    AngularGradient(gradient: StrandPalette.goldGradient,
                                    center: .center,
                                    angle: .degrees(-90)),
                    style: StrokeStyle(lineWidth: size * 0.16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size * 0.84, height: size * 0.84)

            // Solid centre core dot — the "on-device core".
            Circle()
                .fill(LinearGradient(gradient: StrandPalette.goldGradient,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.26, height: size * 0.26)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Isolated live-status pill — owns the LiveState observation so the rest of RootView (sidebar
/// list + detail) does not re-render on the ~1 Hz HR / frame stream.
private struct SidebarStatus: View {
    @EnvironmentObject var live: LiveState
    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
                .shadow(color: statusColor.opacity(0.6), radius: live.connected ? 4 : 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(StrandFont.rounded(12, weight: .medium))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(live.batteryPct.map { "Battery \(Int($0))%" } ?? "Strap not connected")
                    .font(StrandFont.rounded(11))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer()
        }
        .padding(10)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
    }

    // Shares LiveState.connectionStatus* with the Settings strap card so the two never disagree (#266):
    // a connected-but-unbonded 5/MG now reads "Connected" here too, not a misleading "Connecting…".
    private var statusColor: Color {
        live.connectionStatusIsActive ? StrandPalette.statusPositive
            : live.connectionStatusIsIdle ? StrandPalette.statusWarning
            : StrandPalette.statusCritical
    }
    private var statusText: String {
        live.connectionStatusLabel
    }
}
