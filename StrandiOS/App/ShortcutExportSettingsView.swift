#if os(iOS)
import SwiftUI
import StrandDesign

/// #155 — the opt-in surface for the Apple-Health-free export. Sideloaded installs (free 7-day
/// signing) can't carry the HealthKit entitlement, so HealthKitBridge never runs for them; this
/// toggle instead has NOOP rewrite Documents/noop_sync.txt on every background transition, and the
/// user's Siri Shortcut reads the file and logs the rows into Apple Health. Default OFF.
struct ShortcutExportSettingsView: View {
    @AppStorage(ShortcutHealthExport.enabledKey) private var enabled = false

    // Day-cycle scene + Liquid Glass, shared with Today/Trends/Settings so this reads as the same
    // surface. Gated on the existing scene toggle; glass falls back to frosted below iOS 26 / macOS.
    @AppStorage(SceneBackgroundPrefs.enabledKey) private var showDayCycleBackground = true
    private var useGlassSurface: Bool {
        #if os(iOS)
        return showDayCycleBackground
        #else
        return false
        #endif
    }

    var body: some View {
        ScreenScaffold(title: "Shortcuts Export",
                       subtitle: "Strap data into Apple Health without HealthKit — for sideloaded installs.",
                       topBackground: showDayCycleBackground ? AnyView(SceneScreenBackground().drawingGroup()) : nil) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                SettingsGroup(
                    header: "Apple Health",
                    footer: "When this is on, NOOP rewrites a plain-text file — On My iPhone › NOOP › noop_sync.txt — each time you leave the app: one line per 15 minutes of heart rate, HRV and steps, read straight from your strap. Pair it with the Siri Shortcut that reads the file and logs everything into Apple Health — no HealthKit entitlement needed, so it works on sideloaded installs. The setup guide and the pre-built Shortcut live in the project wiki on GitHub."
                ) {
                    SettingsRow(icon: "square.and.arrow.up.on.square.fill",
                                title: "Export for Shortcuts",
                                subtitle: "Writes noop_sync.txt on every background — no HealthKit needed.") {
                        Toggle("", isOn: $enabled)
                            .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                            .accessibilityLabel("Export for Shortcuts to Apple Health")
                    }
                }
            }
        }
        // Liquid Glass for the group (SettingsGroup → NoopCard, glass-aware). Cascades to the card.
        .environment(\.noopGlassSurface, useGlassSurface)
    }
}
#endif
