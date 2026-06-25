#if os(iOS)
import SwiftUI
import AppIntents
import StrandDesign

/// Surfaces NOOP's already-registered App Intents (see StrandiOS/System/NOOPAppIntents.swift) in the
/// UI so users discover them. `NOOPShortcuts` auto-registers "Buzz Strap" and "Mark a Moment" with
/// Siri/Spotlight/Shortcuts, but nothing in-app advertised them — this is the iOS analogue of the
/// Mac's strap-double-tap-runs-a-Shortcut feature. Apple's `SiriTipView`/`ShortcutsLink` (iOS 16+)
/// do exactly that: tip the user on the spoken phrase and deep-link into the Shortcuts app, scoped to
/// this app automatically. Native grouped-list idiom: light section headers + grey footers over glass.
struct SiriShortcutsSettingsView: View {
    /// The live app model — tapping a ready-made action runs it directly (we're in the foreground, so
    /// the PendingIntents queue the Siri path uses wouldn't drain until the next activation).
    @EnvironmentObject private var model: AppModel
    /// The action whose row is briefly showing its "done" confirmation (nil = none). Gives visible
    /// feedback that the tap registered even when the underlying buzz is silent (no strap bonded).
    @State private var confirmedAction: String?

    /// Day-cycle scene behind the header (shared with Today/Trends/Settings). Gates the glass surface.
    @AppStorage(SceneBackgroundPrefs.enabledKey) private var showDayCycleBackground = true

    /// Neutral Liquid Glass when the scene is on; frosted fallback below iOS 26. Always false on macOS.
    private var useGlassSurface: Bool {
        #if os(iOS)
        return showDayCycleBackground
        #else
        return false
        #endif
    }

    var body: some View {
        ScreenScaffold(title: "Siri & Shortcuts",
                       subtitle: "Run NOOP actions hands-free.",
                       topBackground: showDayCycleBackground
                           ? AnyView(SceneScreenBackground().drawingGroup()) : nil) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                readyMadeGroup.staggeredAppear(index: 0)
                buildYourOwnGroup.staggeredAppear(index: 1)
            }
        }
        // Liquid Glass for the groups (SettingsGroup → NoopCard, glass-aware). Apple's own
        // SiriTipView/ShortcutsLink keep their opaque chrome and sit on the glass, not become it.
        .environment(\.noopGlassSurface, useGlassSurface)
    }

    /// The two ready-made intents, shown as plain grouped rows that name the action and its spoken
    /// phrase. We deliberately DON'T use Apple's `SiriTipView` here: it renders as an opaque dark bar
    /// with redacted/blank text until the system has indexed the App Shortcuts (it never does in the
    /// Simulator), which read as broken. A static row always shows the phrase and matches the app's
    /// grouped-list chrome; `ShortcutsLink` below still deep-links into Shortcuts for the real wiring.
    private var readyMadeGroup: some View {
        SettingsGroup(header: "Ready-made actions",
                      footer: "Tap to run now, or trigger from Siri, Spotlight, the Shortcuts app, or a Back-Tap / automation — no setup needed.") {
            actionRow(id: "buzz", icon: "waveform.path", title: "Buzz Strap",
                      phrase: "Buzz my NOOP strap", done: "Buzz sent") { model.buzz(loops: 1) }
            actionRow(id: "mark", icon: "mappin.and.ellipse", title: "Mark a Moment",
                      phrase: "Mark a moment in NOOP", done: "Moment marked") { model.markMoment(at: Date()) }
        }
    }

    /// One ready-made action: its icon + name, with the Siri-spoken phrase as a full-width subtitle
    /// (in quotes) so it reads as "say this to Siri" and never crowds the title. Tapping the row runs
    /// the action and briefly swaps in a green check + confirmation so the tap is visibly registered.
    private func actionRow(id: String, icon: String, title: LocalizedStringKey,
                           phrase: String, done: LocalizedStringKey,
                           perform: @escaping () -> Void) -> some View {
        let confirmed = confirmedAction == id
        return SettingsRow(icon: confirmed ? "checkmark.circle.fill" : icon,
                           iconTint: confirmed ? StrandPalette.statusPositive : StrandPalette.accent,
                           title: title,
                           subtitle: confirmed ? done : "“\(phrase)”",
                           showsChevron: false) {
            perform()
            withAnimation(.easeOut(duration: 0.18)) { confirmedAction = id }
            Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                await MainActor.run {
                    if confirmedAction == id {
                        withAnimation(.easeOut(duration: 0.18)) { confirmedAction = nil }
                    }
                }
            }
        }
        .accessibilityHint("Runs now. Say to Siri: \(phrase)")
    }

    /// Deep-link into the Shortcuts app to wire these actions into automations.
    private var buildYourOwnGroup: some View {
        SettingsGroup(header: "Build your own",
                      footer: "Wire NOOP's actions into a Back-Tap, a focus automation, or a longer Shortcut — for example, double-tap the back of your iPhone to buzz the strap.") {
            ShortcutsLink()
                .settingsRowInsets()
        }
    }
}
#endif
