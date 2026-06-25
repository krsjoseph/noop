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

    /// The two ready-made intents, hosted as Apple's tip controls inside the grouped list.
    private var readyMadeGroup: some View {
        SettingsGroup(header: "Ready-made actions",
                      footer: "Buzz your strap or mark a moment from Siri, Spotlight, the Shortcuts app, or a Back-Tap / automation — no setup needed.") {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                SiriTipView(intent: BuzzStrapIntent(), isVisible: .constant(true))
                    .siriTipViewStyle(.dark)
                SiriTipView(intent: MarkMomentIntent(), isVisible: .constant(true))
                    .siriTipViewStyle(.dark)
            }
            .settingsRowInsets()
        }
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
