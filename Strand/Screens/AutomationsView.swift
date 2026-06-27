import SwiftUI
import StrandDesign

/// Automations — turn the strap's physical inputs (double-tap, wrist on/off) and live biometrics
/// into actions (Shortcuts, and Mac-only screen lock) and haptic coaching. All on-device.
///
/// Native iOS grouped-list idiom, shared with Settings: light overline section headers + one
/// rounded `SettingsGroup` of `SettingsRow`s over Liquid Glass, the old per-card blurb de-noised
/// into a grey group footer. Colour stays in the data (status words / accent icon squares) — the
/// card chrome is neutral glass.
struct AutomationsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var behavior: BehaviorStore
    // PERF: this screen does NOT observe `LiveState`. Its only live-dependent pixel is the "Strap
    // bonded / not connected" pill inside the double-tap card, which is now the `BondStatePill` leaf
    // that owns its own `@EnvironmentObject live`. Observing `live` at this level would re-render the
    // whole 8-9 card automations column on every ~1 Hz strap tick (bond state changes only rarely);
    // scoping it means a tick re-renders just the one pill.
    /// Deep-link into the experimental Rhythm visualization (it self-gates on its own consent).
    @EnvironmentObject var router: NavRouter

    /// v5 cycle-awareness opt-in (default OFF — the most sensitive health category, manual-first).
    @AppStorage(AppModel.cycleAwarenessKey) private var cycleAwareness = false
    /// v5 Rhythm experimental gate (the screen still shows its own consent clickwrap when opened).
    @AppStorage(RhythmConsent.enabledKey) private var rhythmEnabled = false
    /// Inactivity reminder (#419) — UI-local store, persisted in UserDefaults. The buzz itself fires
    /// from the BLE offload path (BLEManager.maybeBuzzInactivity → the shipped SedentaryDetector); this
    /// screen only edits the prefs the engine reads.
    @StateObject private var inactivity = InactivityPrefs()
    #if os(iOS)
    /// Wrist-alerts master gate (PR #572). On iOS the NotificationSettingsView (and its store) are
    /// excluded by project.yml, so `notif.masterEnabled` — the key SedentaryDetector + the wrist-buzz
    /// posting read — has no UI to flip and is stuck at its default OFF. Bind the SAME raw key here so
    /// iPhone users can actually turn wrist alerts on. Default OFF, matching the store's default.
    @AppStorage("notif.masterEnabled") private var wristAlertsMaster = false
    #endif
    // Day-cycle scene + Liquid Glass, shared with Today/Trends/Settings so Automations reads as the
    // same surface. Gated on the existing `showDayCycleBackground` toggle; glass falls back to frosted
    // below iOS 26 / on macOS.
    @AppStorage(SceneBackgroundPrefs.enabledKey) private var showDayCycleBackground = true
    private var useGlassSurface: Bool {
        #if os(iOS)
        return showDayCycleBackground
        #else
        return false
        #endif
    }

    var body: some View {
        ScreenScaffold(title: "Automations",
                       subtitle: "Make the strap do things — tap to act, walk away to lock, train by feel.",
                       // PERF: the groups are direct children of the scaffold column, so the LazyVStack
                       // path genuinely builds the off-screen cards on demand instead of constructing all
                       // eight/nine + their toggle subtrees up-front.
                       lazy: true,
                       // Shared day-cycle scene behind the header (flattened to one GPU layer), as on Today.
                       topBackground: showDayCycleBackground
                           ? AnyView(SceneScreenBackground().drawingGroup()) : nil) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                #if os(iOS)
                wristAlertsCard.staggeredAppear(index: 0)
                #endif
                doubleTapCard.staggeredAppear(index: 1)
                wearCard.staggeredAppear(index: 2)
                coachingCard.staggeredAppear(index: 3)
                // #766: the strap's silent wake-alarm card used to sit here, which let users conflate it
                // with the wind-down reminder. It's moved to the dedicated Alarms screen (SmartAlarmView)
                // so every wake/wind-down control lives in one place. Automations is just inputs-to-actions now.
                inactivityCard.staggeredAppear(index: 4)
                illnessCard.staggeredAppear(index: 5)
                healthInsightsCard.staggeredAppear(index: 6)
                batteryCard.staggeredAppear(index: 7)
            }
        }
        // Liquid Glass for the groups (SettingsGroup → NoopCard, glass-aware). Cascades via the
        // environment; neutral glass when on, frosted fallback otherwise (below iOS 26 / macOS).
        .environment(\.noopGlassSurface, useGlassSurface)
    }

    // MARK: - Wrist alerts master (iOS only — PR #572)

    #if os(iOS)
    /// The master switch for wrist-buzz notifications. On macOS this lives in its own Notifications
    /// screen; that screen is excluded from the iOS target, so without this the gate is unreachable on
    /// iPhone and every wrist alert (inactivity, app notifications) stays silently off. Binds the same
    /// `notif.masterEnabled` key the SedentaryDetector and the notification posting read.
    private var wristAlertsCard: some View {
        SettingsGroup(
            header: "Wrist alerts",
            footer: "Let NOOP tap your wrist for the things you turn on below, so you can leave your phone and still feel what matters."
        ) {
            SettingsRow(icon: "bell.badge.fill", title: "Enable wrist alerts",
                        subtitle: "The master switch for every wrist buzz (inactivity, stress, alerts). Off keeps the strap quiet no matter what else is on.",
                        value: wristAlertsMaster ? "On" : nil) {
                Toggle("", isOn: $wristAlertsMaster)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Enable wrist alerts")
            }
        }
    }
    #endif

    // MARK: - Double tap

    private var doubleTapCard: some View {
        SettingsGroup(
            header: "Double-tap",
            footer: "Double-tap the strap to trigger an action on \(Platform.deviceNounPhrase). (The strap exposes a single double-tap gesture.)"
        ) {
            SettingsRow(icon: "hand.tap.fill", title: "When I double-tap") {
                Picker("", selection: $behavior.doubleTapAction) {
                    ForEach(doubleTapOptions) { Text($0.label).tag($0) }
                }
                .labelsHidden().fixedSize()
                .accessibilityLabel("When I double-tap")
            }
            if behavior.doubleTapAction == .runShortcut {
                shortcutField("Shortcut name", text: $behavior.doubleTapShortcut)
                    .settingsRowInsets()
            }
            HStack(spacing: NoopMetrics.space3) {
                Button {
                    model.runMacAction(behavior.doubleTapAction, shortcut: behavior.doubleTapShortcut)
                } label: { Label("Test action", systemImage: "play.fill") }
                .buttonStyle(.bordered).tint(StrandPalette.accent)
                .disabled(behavior.doubleTapAction == .none)
                Spacer()
                // Live-observing leaf: re-renders on its own when the strap's bond state flips, so a
                // ~1 Hz strap tick doesn't re-render the whole automations column (scroll-stutter
                // isolation). Renders byte-for-byte the previous inline pill.
                BondStatePill()
            }
            .settingsRowInsets()
            if !model.moments.isEmpty {
                momentsView.settingsRowInsets()
            }
        }
    }

    private var momentsView: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack {
                Text("Recent moments").strandOverline()
                Spacer()
                Button("Clear") {
                    model.moments.removeAll()
                    UserDefaults.standard.removeObject(forKey: "moments")
                }
                .buttonStyle(.plain).font(StrandFont.caption).foregroundStyle(StrandPalette.accent)
            }
            ForEach(Array(model.moments.suffix(5).reversed().enumerated()), id: \.offset) { _, d in
                Text(Self.momentFormatter.string(from: d))
                    .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
    private static let momentFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        // Keep the "EEE d MMM ·" layout but honor the device's 12-/24-hour clock (#337): the "j"
        // template resolves to a 12-hour pattern (contains "a") only where the user prefers it.
        let uses24h = !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "H").contains("a")
        f.dateFormat = "EEE d MMM · " + (uses24h ? "HH:mm" : "h:mm a")
        return f
    }()

    // MARK: - Wear & presence

    private var wearCard: some View {
        SettingsGroup(
            header: "Wear & presence",
            footer: wearBlurb
        ) {
            #if os(macOS)
            SettingsRow(icon: "lock.laptopcomputer", title: "Lock the Mac when I take the strap off",
                        subtitle: "Fires the moment the strap leaves your wrist.") {
                Toggle("", isOn: $behavior.autoLockOnWristOff)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Lock the Mac when I take the strap off")
            }
            #endif
            shortcutFieldRow("figure.walk.motion", label: "Run a Shortcut when taken off",
                             help: "Presence automation — set a Focus, pause media, set away…",
                             text: $behavior.wristOffShortcut)
            shortcutFieldRow("arrow.uturn.backward", label: "Run a Shortcut when put back on",
                             help: "Reverse the above when you return.",
                             text: $behavior.wristOnShortcut)
        }
    }

    // MARK: - Coaching

    private var coachingCard: some View {
        SettingsGroup(
            header: "Haptic coaching",
            footer: "Train by feel — the strap buzzes so you don't have to watch a screen."
        ) {
            SettingsRow(icon: "bolt.heart.fill", title: "HR-zone coaching",
                        subtitle: "Buzz when you hit your top zone (ease off) and again when you recover. Uses your max HR from Settings.",
                        value: behavior.zoneCoaching ? "On" : nil) {
                Toggle("", isOn: $behavior.zoneCoaching)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("HR-zone coaching")
            }
            SettingsRow(icon: "wind", title: "Resting stress nudge (experimental)",
                        subtitle: "A gentle buzz when your HRV drops while your heart rate is calm — a cue to take a paced breath. Rate-limited to once every 15 minutes; off by default.",
                        value: behavior.stressNudge ? "On" : nil) {
                Toggle("", isOn: $behavior.stressNudge)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Resting stress nudge")
            }
            // v5 L3 closed-loop check-in (master + sub toggles). Default OFF, manual-first. The keys
            // mirror BiofeedbackPrefs, which the central detector (AppModel.evaluateStress) reads.
            SettingsRow(icon: "lungs.fill", title: "Stress check-ins (haptic)",
                        subtitle: "When a fresh, non-exercise HRV dip is detected while you're still, NOOP offers a one-minute guided breath — a single confirming buzz and a dismissible card. Never an alarm, never a diagnosis.",
                        value: behavior.stressCheckIn ? "On" : nil) {
                Toggle("", isOn: $behavior.stressCheckIn)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Stress check-ins")
            }
            if behavior.stressCheckIn {
                SettingsRow(title: "Auto-nudge",
                            subtitle: "Let the check-in fire on its own. Off keeps it manual — you start a breath from Breathe yourself.") {
                    Toggle("", isOn: $behavior.stressAutoNudge)
                        .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                        .accessibilityLabel("Auto-nudge")
                }
                SettingsRow(title: "Respect quiet hours",
                            subtitle: "Suppress auto-nudges overnight (10pm–7am).") {
                    Toggle("", isOn: $behavior.stressQuietHours)
                        .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                        .accessibilityLabel("Respect quiet hours")
                }
                SettingsRow(title: "Use my resonance pace",
                            subtitle: "Breathe at the pace your last \u{201C}find my pace\u{201D} sweep locked in, if you have one — otherwise a calm 5.5 breaths/min.") {
                    Toggle("", isOn: $behavior.stressUseResonancePace)
                        .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                        .accessibilityLabel("Use my resonance pace")
                }
            }
        }
    }

    // MARK: - Inactivity reminder (#419)

    private var inactivityCard: some View {
        SettingsGroup(
            header: "Inactivity reminder",
            footer: "A gentle wrist buzz when you've been sitting too long — a nudge to get up and move. Inferred from the strap's motion on each history sync, so it lags real time by a sync or two."
        ) {
            SettingsRow(icon: "timer", title: "Enable inactivity reminder",
                        subtitle: "Buzzes after you've been sitting past your threshold.",
                        value: inactivity.enabled ? "On" : nil) {
                Toggle("", isOn: $inactivity.enabled)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Enable inactivity reminder")
            }
            if inactivity.enabled {
                if !notifMasterOn {
                    HStack(alignment: .top, spacing: NoopMetrics.space3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(StrandPalette.statusWarning)
                            .font(.system(size: 13))
                            .accessibilityHidden(true)
                        Text("Notifications are off, so this can't buzz yet — turn on the master switch in Notifications to let it through.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.statusWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .settingsRowInsets()
                }
                stepperRow(label: "Sitting for", help: "Minutes seated before the first nudge.",
                           value: $inactivity.thresholdMinutes, suffix: "min", range: 15...120, step: 15)
                stepperRow(label: "Re-nudge every", help: "If you're still seated, buzz again this often.",
                           value: $inactivity.reNudgeMinutes, suffix: "min", range: 15...120, step: 15)
                stepperRow(label: "Buzz strength", help: "How strong the buzz is.",
                           value: $inactivity.buzzLoops, suffix: "×", range: 1...4, step: 1)
                // Reuses the shared notification only-when-worn gate (notif.onlyWhenWorn).
                SettingsRow(title: "Only when worn",
                            subtitle: "Don't buzz when the strap is off your wrist.") {
                    Toggle("", isOn: onlyWhenWornBinding)
                        .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                        .accessibilityLabel("Only when worn")
                }
                SettingsRow(title: "Only during active hours",
                            subtitle: "Only nudge during your active hours.") {
                    Toggle("", isOn: $inactivity.activeHoursEnabled)
                        .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                        .accessibilityLabel("Only during active hours")
                }
                if inactivity.activeHoursEnabled {
                    HStack(spacing: NoopMetrics.space3) {
                        Text("From").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                        DatePicker("", selection: activeStartBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.compact)
                            .accessibilityLabel("Active hours start")
                        Text("to").font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                        DatePicker("", selection: activeEndBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.compact)
                            .accessibilityLabel("Active hours end")
                        Spacer(minLength: 0)
                    }
                    .settingsRowInsets()
                }
            }
        }
    }

    /// The reused global notification master (notif.masterEnabled, default OFF) — drives the inert-feature
    /// warning so enabling the reminder while master is off isn't silently a no-op.
    private var notifMasterOn: Bool {
        UserDefaults.standard.object(forKey: "notif.masterEnabled") as? Bool ?? false
    }
    /// The reused only-when-worn gate (notif.onlyWhenWorn, default ON) — the SAME key the notifications
    /// screen and the engine read, so the two screens stay in sync.
    private var onlyWhenWornBinding: Binding<Bool> {
        Binding(get: { UserDefaults.standard.object(forKey: "notif.onlyWhenWorn") as? Bool ?? true },
                set: { UserDefaults.standard.set($0, forKey: "notif.onlyWhenWorn") })
    }
    private var activeStartBinding: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: inactivity.activeStartMinutes) },
                set: { inactivity.activeStartMinutes = Self.minutes(from: $0) })
    }
    private var activeEndBinding: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: inactivity.activeEndMinutes) },
                set: { inactivity.activeEndMinutes = Self.minutes(from: $0) })
    }

    /// A label/help row with a native −[value]+ stepper, clamped to `range` and moved by `step`. The
    /// tabular value keeps a fixed min-width so it never reflows or collides with the stepper on a
    /// narrow iPhone (#cutoff): label+help own the left column, value+stepper the right.
    private func stepperRow(label: LocalizedStringKey, help: LocalizedStringKey, value: Binding<Int>,
                            suffix: String, range: ClosedRange<Int>, step: Int) -> some View {
        SettingsRow(title: label, subtitle: help) {
            HStack(spacing: NoopMetrics.space3) {
                Text("\(value.wrappedValue) \(suffix)")
                    .font(StrandFont.bodyNumber)
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(minWidth: 48, alignment: .trailing)
                Stepper("", value: value, in: range, step: step).labelsHidden()
                    .accessibilityLabel(label)
            }
        }
    }

    // MARK: - Illness early-warning

    private var illnessCard: some View {
        SettingsGroup(
            header: "Illness early-warning",
            footer: "Watches your resting HR, HRV, skin temperature and respiration against your own 28-day baseline. On-device and approximate — informational only, not a diagnosis."
        ) {
            SettingsRow(icon: "waveform.path.ecg", title: "Watch for early-illness signs",
                        subtitle: "Needs at least 14 days of history. When two or more signals drift together you get a banner on the dashboard and a notification — at most once a day.",
                        value: behavior.illnessWatch ? "On" : nil) {
                Toggle("", isOn: $behavior.illnessWatch)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Watch for early-illness signs")
            }
        }
        .onChangeCompat(of: behavior.illnessWatch) { _ in
            model.reevaluateIllness()
            if behavior.illnessWatch { IllnessNotifier.requestAuthorization() }
        }
    }

    // MARK: - Health insights (v5: cycle awareness opt-in · experimental Rhythm)

    private var healthInsightsCard: some View {
        SettingsGroup(
            header: "Health insights",
            footer: "Optional, on-device reads from your nightly signals. Each is off by default — for awareness only, never a diagnosis."
        ) {
            SettingsRow(icon: "thermometer.medium", title: "Cycle awareness",
                        subtitle: "Reads a coarse menstrual-cycle phase from your nightly skin temperature, entirely on \(Platform.deviceNounPhrase). Awareness only — not contraception, not a fertility predictor, not a medical service. The card appears in Health.",
                        value: cycleAwareness ? "On" : nil) {
                Toggle("", isOn: $cycleAwareness)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Cycle awareness")
            }
            .onChangeCompat(of: cycleAwareness) { on in
                model.cycleAwarenessEnabled = on
                Task { await model.refreshV5Signals() }
            }
            SettingsRow(icon: "waveform.path", title: "Rhythm visualization (experimental)",
                        subtitle: "An experimental picture of your beat-to-beat heart timing. Not an ECG and not a diagnosis. You'll read and accept an experimental note before it shows anything.",
                        value: rhythmEnabled ? "On" : nil) {
                Toggle("", isOn: $rhythmEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Rhythm visualization")
            }
            if rhythmEnabled {
                SettingsRow(title: "Open Rhythm") {
                    Button {
                        router.openRhythm()
                    } label: { Label("Open", systemImage: "waveform.path") }
                    .buttonStyle(.bordered).tint(StrandPalette.accent)
                }
            }
        }
    }

    // MARK: - Strap battery alerts

    private var batteryCard: some View {
        SettingsGroup(
            header: "Battery alerts",
            footer: "Get a notification when the strap battery runs low (15%) so you can top it up before tonight, and when it finishes charging."
        ) {
            SettingsRow(icon: "battery.25", title: "Notify on low and full battery",
                        subtitle: "A reminder to recharge before bed when the strap drops to 15%, and a heads-up when it reaches 100% — each at most once per charge cycle.",
                        value: behavior.batteryAlerts ? "On" : nil) {
                Toggle("", isOn: $behavior.batteryAlerts)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Notify on low and full battery")
            }
        }
        .onChangeCompat(of: behavior.batteryAlerts) { on in
            if on { BatteryNotifier.requestAuthorization() }
        }
    }

    // MARK: - Helpers

    /// Double-tap actions offered in the picker. The "Lock the Mac" action can't work on iPhone
    /// (a third-party app can't lock iOS), so it's dropped there.
    private var doubleTapOptions: [MacActionKind] {
        #if os(iOS)
        MacActionKind.allCases.filter { $0 != .lockScreen }
        #else
        MacActionKind.allCases
        #endif
    }

    /// Wear & presence blurb. macOS mentions the auto-lock affordance (and the Apple-Watch unlock
    /// caveat); iOS, where that toggle is hidden, describes the Shortcut-driven presence reactions.
    private var wearBlurb: LocalizedStringKey {
        #if os(macOS)
        "React when the strap comes off or goes on. Note: macOS reserves true auto-UNLOCK for Apple Watch — this can lock, not unlock."
        #else
        "React when the strap comes off or goes on — run a Shortcut to set a Focus, pause media, mark yourself away."
        #endif
    }

    // `date(fromMinutes:)` / `minutes(from:)` stay: the inactivity active-hours pickers above use them.
    // (The strap-alarm time binding moved to SmartAlarmView with the rest of the alarm UI, #766.)
    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
    private static func minutes(from d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// The shortcut-name text field. Kept narrow (≤200pt) so it never crowds its label on a small
    /// iPhone; used both inline beneath the double-tap picker and inside the wear-presence rows.
    private func shortcutField(_ placeholder: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .font(StrandFont.body)
            .frame(maxWidth: 200)
    }

    /// A wear-presence row: label + help on the left, the narrow shortcut field on the right. The field
    /// drops to its own full-width inset line below the label so it never competes horizontally on a
    /// narrow screen.
    private func shortcutFieldRow(_ icon: String, label: LocalizedStringKey, help: LocalizedStringKey,
                                  text: Binding<String>) -> some View {
        SettingsRow(icon: icon, title: label, subtitle: help) {
            shortcutField("Shortcut name", text: text)
        }
    }
}

// MARK: - Live-observing leaf (scroll-stutter isolation)

/// The strap bond-status pill in the double-tap card ("Strap bonded" / "Strap not connected"). It owns
/// its OWN `@EnvironmentObject live` so a ~1 Hz strap publish re-renders only this pill, not the whole
/// automations column (the parent `AutomationsView` no longer observes `LiveState`). Renders
/// byte-for-byte the previous inline `StatePill(live.bonded ? …)`.
private struct BondStatePill: View {
    @EnvironmentObject private var live: LiveState
    var body: some View {
        StatePill(live.bonded ? "Strap bonded" : "Strap not connected",
                  tone: live.bonded ? .positive : .warning, showsDot: true)
    }
}
