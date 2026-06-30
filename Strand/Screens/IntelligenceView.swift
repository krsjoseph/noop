import SwiftUI
import StrandDesign
import StrandAnalytics

/// Intelligence — Kineva's own recovery/strain/sleep scores, computed on-device from raw strap data
/// using the WHOOP model shape. Makes the app independent of WHOOP's cloud for live-collected days.
struct IntelligenceView: View {
    @EnvironmentObject var intelligence: IntelligenceEngine
    // NOTE: IntelligenceView deliberately does NOT observe `LiveState`. A connected strap publishes at
    // ~1 Hz, which would re-evaluate this body (and its lazy By-Day list) on every tick. The only live
    // dependency — the "Syncing strap history…" note shown over the empty state — owns its OWN
    // `@EnvironmentObject var live` in the `IntelSyncingNote` leaf below (mirrors the Today/Sleep
    // leaf-scoping pattern), so a tick refreshes only that note.

    @State private var range: IntelRange = .month

    // Day-cycle scene backdrop + Liquid Glass, shared with Today/Trends/Sleep/Settings so every tab
    // reads as one surface. The scene sits behind the header band and fades above the cards; glass cards
    // refract it. Gated on the same Settings toggle; the glass surface falls back to frosted below iOS 26 / macOS.
    @AppStorage(SceneBackgroundPrefs.enabledKey) private var showDayCycleBackground = true
    private var useGlassSurface: Bool {
        #if os(iOS)
        return showDayCycleBackground
        #else
        return false
        #endif
    }

    // Effort display scale (#268) — routes every Effort value/label on this screen. Display-only.
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        // `lazy` so the trailing By-Day `ForEach` renders day cards on demand. With an 800+ day
        // imported history, an eager VStack built every card up-front on the main thread and froze
        // the app when ALL was tapped (#345); LazyVStack only materialises what's on screen.
        ScreenScaffold(title: "Intelligence",
                       subtitle: "Kineva scores your charge, effort and rest itself — on-device, no cloud.",
                       // Pull-to-refresh mirrors the toolbar Recompute (the button stays for discoverability).
                       onRefresh: { await intelligence.analyzeRecent() },
                       lazy: true,
                       // Shared day-cycle scene behind the header (flattened to one GPU layer), as on Today/Trends.
                       topBackground: showDayCycleBackground
                           ? AnyView(SceneScreenBackground().drawingGroup()) : nil) {
            // One section rhythm (22–24pt) for the upper, fixed-count sections — matching
            // Today/Trends/Sleep/Settings. The By-Day `ForEach` is deliberately kept as a DIRECT child
            // of the scaffold's `LazyVStack` (NOT inside this eager VStack) so day cards still
            // materialise on demand — wrapping it would rebuild the eager-VStack #345 freeze on ALL.
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                if let f = forecast {
                    forecastCard(f)
                        .staggeredAppear(index: 0)
                }
                explainerCard
                    .staggeredAppear(index: 1)
                if intelligence.computing {
                    NoopCard(padding: 20) {
                        HStack(spacing: NoopMetrics.rowSpacing) {
                            ProgressView().controlSize(.small)
                            Text("Crunching your raw streams…").font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                    .staggeredAppear(index: 2)
                } else if let note = intelligence.note {
                    NoopCard(padding: 20) {
                        HStack(alignment: .top, spacing: NoopMetrics.rowSpacing) {
                            Image(systemName: "moon.zzz.fill").foregroundStyle(StrandPalette.chargeColor)
                                .accessibilityHidden(true)
                            Text(note).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .staggeredAppear(index: 2)
                } else if intelligence.results.isEmpty {
                    // While the strap is mid-offload, say so — "no days" reads as final otherwise (#77). The
                    // note owns the `LiveState` observation in its own leaf so the chunk count ticks without
                    // re-rendering Intelligence (identical output to the prior inline check).
                    IntelSyncingNote()
                        .staggeredAppear(index: 2)
                    DataPendingNote(
                        title: "Building from your strap",
                        message: "This builds from the strap as it syncs. Effort and rest appear after you have worn it and slept a night. Charge needs about four nights of sleep to learn your baseline (you'll see \"Calibrating\" until then), and keeps sharpening over your first couple of weeks. On a WHOOP 5 or MG the strap banks little history, so the night count can climb slowly or sit at 0 of 4 until you have worn it across a few nights. That's its sync limit, not a fault. Import your WHOOP export to skip the wait.",
                        symbol: "brain.head.profile"
                    )
                    .staggeredAppear(index: 3)
                } else {
                    // Header: section label + range control. Narrows the per-day list to a recent
                    // window (lexicographic yyyy-MM-dd compare == chronological). The day count folds
                    // into the SectionHeader trailing; the 6-segment pill wraps below the title on a
                    // narrow iPhone via the ViewThatFits horizontal→vertical fallback.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space3) {
                            SectionHeader("By Day", overline: "Recent",
                                          trailing: "\(filtered.count) \(filtered.count == 1 ? "day" : "days")")
                            SegmentedPillControl(IntelRange.allCases, selection: $range) { $0.label }
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                            SectionHeader("By Day", overline: "Recent",
                                          trailing: "\(filtered.count) \(filtered.count == 1 ? "day" : "days")")
                            SegmentedPillControl(IntelRange.allCases, selection: $range) { $0.label }
                        }
                    }
                    .staggeredAppear(index: 2)
                }
            }
            // By-Day list. When the window is empty, one note; otherwise the day cards stay DIRECT
            // children of the scaffold's `LazyVStack` so an 800+ day "ALL" history materialises on
            // demand instead of building every card up-front (#345).
            if !intelligence.computing, intelligence.note == nil, !intelligence.results.isEmpty {
                if filtered.isEmpty {
                    NoopCard(padding: 18) {
                        Text("No scored days in this window. Widen the range or import more history.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .staggeredAppear(index: 3)
                } else {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, day in
                        dayCard(day)
                            .staggeredAppear(index: index + 3)
                    }
                }
            }
        }
        .task { if intelligence.results.isEmpty { await intelligence.analyzeRecent() } }
        .toolbar {
            ToolbarItem {
                Button { Task { await intelligence.analyzeRecent() } } label: {
                    Label("Recompute", systemImage: "arrow.clockwise")
                }
                .disabled(intelligence.computing)
            }
        }
        // Liquid Glass for every card on Intelligence (cascades down via the environment). Neutral glass
        // when the scene is on; frosted fallback otherwise (and below iOS 26 / macOS).
        .environment(\.noopGlassSurface, useGlassSurface)
    }

    /// The day list narrowed to the selected window. `nil` cutoff (ALL) shows everything.
    private var filtered: [IntelligenceEngine.Computed] {
        guard let n = range.days else { return intelligence.results }
        let date = Calendar.current.date(byAdding: .day, value: -(n - 1), to: Date()) ?? Date()
        let cutoff = Self.dayFmt.string(from: date)
        return intelligence.results.filter { $0.day >= cutoff }
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Evening forecast of tomorrow-morning Charge from tonight's known levers. Anchored to
    /// the recent Charge baseline, nudged by today's Effort vs your norm and how much sleep
    /// you typically bank, then mean-reverted. `results` is newest-first; the forecaster wants
    /// oldest→newest, so each series is reversed. `nil` (and the card hidden) until there are
    /// enough scored nights to anchor honestly — never a fabricated number.
    private var forecast: RecoveryForecast? {
        let charge = intelligence.results.compactMap { $0.recovery }.reversed()
        let effort = intelligence.results.compactMap { $0.strain }.reversed()
        // Planned sleep tonight = the recent typical night (the honest "if you sleep ~Xh"
        // assumption surfaced in the card), from the scored nights that have a sleep total.
        let sleeps = intelligence.results.compactMap { $0.sleepMin }
        let plannedHours = sleeps.isEmpty ? RecoveryForecaster.defaultNeedHours
            : (sleeps.reduce(0, +) / Double(sleeps.count)) / 60.0
        return RecoveryForecaster.forecast(recentCharge: Array(charge),
                                           recentEffort: Array(effort),
                                           todayEffort: intelligence.results.first?.strain,
                                           plannedSleepHours: plannedHours)
    }

    /// The forecast hero — tomorrow-morning Charge as a clean flat GlowRing on a flat opaque
    /// surfaceRaised card (the Design Reset look), with the plain-English estimate read-out beneath.
    /// No scenic backdrop, no bloom gauge — the read-outs sit on an opaque card so they stay crisp,
    /// the same wash-out fix the Today hero got. The number, ± band and copy are unchanged.
    private func forecastCard(_ f: RecoveryForecast) -> some View {
        let frac = min(max(f.charge / 100.0, 0), 1)
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Tomorrow's Charge", overline: "Evening forecast", trailing: "Estimate")
            NoopCard(padding: 20) {
                VStack(spacing: 14) {
                    GlowRing(
                        fraction: frac,
                        value: f.charge,
                        format: { "\(Int($0.rounded()))" },
                        color: StrandPalette.recoveryColor(f.charge),
                        diameter: 184,
                        lineWidth: 18
                    )
                    .overlay(alignment: .bottom) {
                        Text("± \(Int(f.band.rounded())) · \(StrandPalette.recoveryState(f.charge))")
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .offset(y: 26)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 18)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Tomorrow's Charge estimate \(Int(f.charge.rounded())) plus or minus \(Int(f.band.rounded()))")
                    VStack(alignment: .leading, spacing: 10) {
                        Text("You'll likely wake around \(Int(f.charge.rounded())) ± \(Int(f.band.rounded())) Charge if you sleep about \(sleepHoursLabel(f.plannedSleepHours)) tonight.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Estimate from today's effort, your typical sleep and your \(f.nights)-night recovery baseline — not a measurement. Your real Charge is scored from tomorrow's HRV when you wake.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// "~7h" / "~7h 30m" for the planned-sleep assumption (hours rounded to the nearest 30 min).
    private func sleepHoursLabel(_ hours: Double) -> String {
        let half = (hours * 2).rounded() / 2
        let h = Int(half)
        let m = Int((half - Double(h)) * 60)
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private var explainerCard: some View {
        NoopCard(padding: 20) {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                HStack(spacing: NoopMetrics.rowSpacing) {
                    Image(systemName: "brain.head.profile").foregroundStyle(StrandPalette.chargeColor)
                        .accessibilityHidden(true)
                    Text("How this works").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                }
                Text("Charge weighs your HRV against your personal baseline (~55%), resting heart rate (~20%), rest quality (~15%), respiration (~5%) and skin-temperature deviation (~5%). Effort is a 0–\(UnitFormatter.effortScaleMax(effortScale)) cardiovascular load from time in heart-rate zones. Rest is staged from movement and heart rate. Everything is computed here from the strap's raw data — it works for any day Kineva collected raw streams.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // The Charge model made concrete — the five weighted inputs, each its own metric accent.
                VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                    Text("Charge model").strandOverline()
                    weightRow("Heart-rate variability", "~55%", fraction: 0.55, color: StrandPalette.metricPurple)
                    weightRow("Resting heart rate", "~20%", fraction: 0.20, color: StrandPalette.metricRose)
                    weightRow("Rest quality", "~15%", fraction: 0.15, color: StrandPalette.metricCyan)
                    weightRow("Respiration", "~5%", fraction: 0.05, color: StrandPalette.accent)
                    weightRow("Skin-temperature deviation", "~5%", fraction: 0.05, color: StrandPalette.metricAmber)
                    HStack {
                        Text("Effort").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        Spacer()
                        Text("0–\(UnitFormatter.effortScaleMax(effortScale)) scale")
                            .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.effortColor)
                    }
                    .padding(.top, 2)
                }
                .padding(.top, 2)
            }
        }
    }

    /// One weighted-input row: label + percent + a thin proportional meter on the inset well, tinted
    /// to the input's own metric accent. Presentation of the Charge model — no per-day data.
    private func weightRow(_ label: String, _ percent: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack {
                Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Text(percent).font(StrandFont.captionNumber).foregroundStyle(color)
            }
            // The Kineva signature segmented bar — counts up on appear, tinted to the input's accent.
            // The Charge weights span 0…0.55, so the bar reads each input's share of the model.
            PipBar(value: fraction, range: 0...0.55, segments: 18, tint: color, height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(percent) of Charge")
    }

    private func dayCard(_ d: IntelligenceEngine.Computed) -> some View {
        NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                HStack {
                    Text(d.day).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    // The REAL source of the day's dashboard headline, not a hard-coded "Kineva-computed".
                    // The By-Day numbers are always Kineva's on-device scores, but when an import covers the
                    // day it WINS the dashboard merge, so the badge says so ("Whoop" / "Apple Health") and
                    // a strap-scored night reads "On-device". Dynamic String → wrap in "\()" so it's shown
                    // verbatim, not looked up as a LocalizedStringKey (the String≠LocalizedStringKey
                    // SwiftUI footgun). Imported rows use the accent tint to stand out from computed ones.
                    SourceBadge("\(d.source.badge)",
                                tint: d.source == .computed ? StrandPalette.chargeColor : StrandPalette.accent)
                }
                // Five compact per-day values. An adaptive grid so they reflow to 2–3 rows on a narrow
                // iPhone instead of cramming five columns into one tight row (each stat still clamps
                // with lineLimit(1)+minimumScaleFactor(0.6)).
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: NoopMetrics.space3, alignment: .leading)],
                          alignment: .leading, spacing: NoopMetrics.space3) {
                    stat("Charge", d.recovery.map { "\(Int($0.rounded()))%" } ?? "—",
                         d.recovery.map { StrandPalette.recoveryColor($0) } ?? StrandPalette.textSecondary)
                    stat("Effort", d.strain.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "—",
                         d.strain.map { StrandPalette.strainColor($0) } ?? StrandPalette.textSecondary)
                    stat("Rest", d.sleepMin.map { "\(Int($0 / 60))h \(Int($0.truncatingRemainder(dividingBy: 60)))m" } ?? "—", StrandPalette.restColor)
                    stat("HRV", d.hrv.map { "\(Int($0.rounded()))" } ?? "—", StrandPalette.metricPurple)
                    stat("RHR", d.rhr.map { "\($0)" } ?? "—", StrandPalette.metricRose)
                }
                // Effort load meter (0–100) as the Kineva segmented bar — counts up on appear, tinted
                // along the strain ramp so it reads as at-a-glance cardio load.
                if let s = d.strain {
                    PipBar(value: s, range: 0...100, segments: 20,
                           tint: StrandPalette.strainColor(s), height: 8)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Text(value).font(StrandFont.number(20)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

/// The "Syncing strap history…" note, shown only while a historical offload is running (#77). Owns the
/// `LiveState` observation in its own leaf (scroll-stutter isolation) so the chunk count ticks without
/// re-rendering IntelligenceView. Renders byte-for-byte what the prior inline `live.backfilling` check did.
private struct IntelSyncingNote: View {
    @EnvironmentObject private var live: LiveState
    var body: some View {
        if live.backfilling { SyncingHistoryNote(chunks: live.syncChunksThisSession) }
    }
}

/// Recent-window options for the By Day list. `days == nil` means show everything.
private enum IntelRange: Int, CaseIterable, Hashable {
    case week = 7, month = 30, quarter = 90, half = 180, year = 365, all = 0

    /// Trailing days the window spans; `nil` for ALL.
    var days: Int? { self == .all ? nil : rawValue }

    var label: String {
        switch self {
        case .week: return "W"
        case .month: return "M"
        case .quarter: return "3M"
        case .half: return "6M"
        case .year: return "1Y"
        case .all: return "ALL"
        }
    }
}
