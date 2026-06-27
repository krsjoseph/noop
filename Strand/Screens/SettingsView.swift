import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif
import UniformTypeIdentifiers
import PhotosUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Settings — profile (powers zones / calories / recovery), strap connection, and about.
/// Native iOS grouped-list: light section headers + `SettingsGroup`/`SettingsRow` over glass.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState
    @EnvironmentObject var profile: ProfileStore

    /// Profile-photo picker selection (PhotosUI). Cleared back to nil once the bytes are loaded.
    @State private var avatarPickerItem: PhotosPickerItem?

    /// Backup & restore UI state.
    @State private var backupBusy = false
    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""
    @State private var showBackupAlert = false

    /// Opt-in WHOOP 5/MG protocol experiments (off by default). See [PuffinExperiment].
    @AppStorage(PuffinExperiment.defaultsKey) private var puffinExperiments = false

    /// Opt-in WHOOP 5/MG raw-frame capture to a file (off by default). See [PuffinFrameRecorder].
    @AppStorage(PuffinFrameRecorder.enabledKey) private var puffinCapture = false

    /// Opt-in WHOOP 5/MG "R22" deep-data unlock (off by default) — the one probe that writes a
    /// persistent feature flag to the strap. See [PuffinExperiment.deepDataKey]. (#174)
    @AppStorage(PuffinExperiment.deepDataKey) private var deepDataEnabled = false

    /// Opt-in "Broadcast heart rate" (off by default) — makes the strap advertise its HR as a standard
    /// BLE sensor for Garmin/Zwift/gym kit. See [PuffinExperiment.broadcastHrKey]. (#181)
    @AppStorage(PuffinExperiment.broadcastHrKey) private var broadcastHrEnabled = false

    /// Opt-in "Continuous HRV capture" (off by default) — holds the dense realtime stream armed 24/7 so
    /// the strap banks beat-to-beat R-R for better overnight HRV/recovery/sleep, at a battery cost.
    /// See [PuffinExperiment.keepRealtimeForDataKey].
    @AppStorage(PuffinExperiment.keepRealtimeForDataKey) private var continuousHrvEnabled = false

    /// Opt-in "Experimental sleep staging (V2)" (off by default). When on, detected nights are re-staged with
    /// `SleepStagerV2` (the transparent cardiorespiratory recipe) instead of the default V1 stager. Read at
    /// the staging call site in `Repository`. See [PuffinExperiment.experimentalSleepV2Key].
    @AppStorage(PuffinExperiment.experimentalSleepV2Key) private var experimentalSleepV2Enabled = false

    // Imperial/Metric display preference (D#103). Stored data is always SI; this only changes how
    // distances/weights/heights/temperatures are SHOWN — and lets the profile fields below take
    // imperial entry. Temperature has a separate override so °C/°F can be picked independently.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    // Effort display scale (#268). Display-only — Effort stays stored 0–100, this only chooses whether
    // it's shown on NOOP's 0–100 axis or WHOOP's 0–21 Day Strain axis.
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    // Live-HR Live Activity (Lock Screen + Dynamic Island), iOS only (#336). Default on.
    @AppStorage(UnitPrefs.liveActivityKey) private var liveActivityEnabled = true
    // Alternate app icon (iOS only) — false = Titanium (primary AppIcon), true = Blue Titanium
    // ("AppIcon-Navy"). Display-only preference; the live switch goes through setAlternateIconName.
    @AppStorage("appIcon.alt") private var useNavyIcon = false
    // Light/Dark/System theme. Read by both app roots' .preferredColorScheme; default follows the OS.
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    // Chart colour style: Titanium (brand) or Classic (throwback red→green). Re-colours gauges + charts.
    @AppStorage(ChartStyle.storageKey) private var chartStyleRaw = ChartStyle.titanium.rawValue
    // Day-cycle scene backdrop behind Today (#698). Default ON. Off swaps the scene for a plain dark
    // canvas. TodayView reads the same key to gate its SceneScreenBackground.
    @AppStorage(SceneBackgroundPrefs.enabledKey) private var showDayCycleBackground = true
    // Hydration tracker (opt-in, MVP). Default OFF — when off the hydration dashboard card + detail are
    // hidden. Mirrors the Android pref so the toggle reads the same on both platforms.
    @AppStorage(HydrationStore.enabledKey) private var hydrationEnabled = false

    /// Opt-in "Auto-detect workouts" (default OFF). When ON, Today scans the last day or two of HR for a
    /// sustained-elevated window and offers — via a single dismissible card — to save it as a workout.
    /// Nothing is ever created automatically. Mirrors the Android `NoopPrefs.KEY_AUTO_DETECT_WORKOUTS`.
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetectWorkoutsEnabled = false

    /// Opt-in "Keep screen on during a workout" (default OFF, #703). When ON, the live-workout view
    /// holds the screen awake while a manual recording is running so you can glance at your live HR
    /// without the device dimming. The live-workout view reads this same key. The string is shared
    /// verbatim with the Android twin (SharedPreferences "workoutKeepScreenOn").
    @AppStorage("workoutKeepScreenOn") private var workoutKeepScreenOn = false

    /// The strap model the user last picked (same key the scan pickers write). Gates the WHOOP 4.0-only
    /// rename control in the strap card — renaming uses the Harvard command set, which a 5/MG doesn't share.
    @AppStorage("selectedWhoopModel") private var selectedWhoopModelRaw = WhoopModel.whoop4.rawValue
    /// Draft text for the strap-rename field (strap card). Empty placeholder; never pre-seeded so the
    /// current name stays visible separately above it.
    @State private var strapNameDraft = ""

    /// Whether to surface the WHOOP 5/MG-only probes (puffin/R22/broadcast-HR/frame-capture). Gated so a
    /// confident 4.0 owner never sees 5/MG controls that can't touch their strap (#22). The model
    /// preference DEFAULTS to whoop4, so we deliberately do NOT hide on the raw default alone — the same
    /// `"selectedWhoopModel"` key is rewritten to the family that actually advertised when a strap
    /// connects (BLEManager, PR#195), so a real 5/MG owner who never opened the model picker still flips
    /// this true the moment their strap is discovered. We hide the 5/MG block only when the user is
    /// confidently on a 4.0 (pref says whoop4 AND nothing 5/MG is connected). The always-on raw-CSV
    /// diagnostic stays visible on every model regardless.
    private var showFiveMGControls: Bool {
        selectedWhoopModelRaw == WhoopModel.whoop5mg.rawValue
    }

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: unitSystem, override: temperatureRaw)
    }

    // Day-cycle scene + Liquid Glass, shared with Today/Trends so Settings reads as the same surface.
    // Gated on the existing `showDayCycleBackground` toggle; glass falls back to frosted below iOS 26 / macOS.
    private var useGlassSurface: Bool {
        #if os(iOS)
        return showDayCycleBackground
        #else
        return false
        #endif
    }

    /// Raw-sensor CSV export (experimental diagnostic, #308/#276/#322). Holds the last-written file so
    /// macOS can "Reveal in Finder" after a share, mirroring the puffin-capture export.
    @State private var rawCsvBusy = false
    @State private var lastRawCsvURL: URL?

    /// Scheduled daily debug auto-export (#510, parity with Android). Seeded from the persisted store;
    /// the toggle + time picker write back through `ScheduledDebugExport`. Opt-in, default OFF.
    @State private var debugExportOn = ScheduledDebugExport.isEnabled
    @State private var debugExportMinutes = ScheduledDebugExport.timeMinutes

    /// Confirm gate for the "Recalibrate Charge baseline" action (it re-learns the HRV anchor from tonight).
    @State private var showRecalibrateConfirm = false

    /// "What's New" changelog sheet, reachable any time from About.
    @State private var showWhatsNew = false

    /// "How your scores work" explainer sheet, reachable any time from About.
    @State private var showScoringGuide = false

    /// "How NOOP works" primer sheet (the four-section explainability primer), reachable any
    /// time from About — covers how sleep is sorted, how scores + calibration work, what
    /// recording means, and where the provenance badges come from.
    @State private var showHowNoopWorks = false

    /// "Set up Apple Watch" sheet: the honest watch onboarding flow (what it's great at, where
    /// it's lighter, then the Health permission request). Presented from the About page's primary
    /// action. iOS does the real HealthKit request; macOS reads as an iPhone-only step.
    @State private var showAppleWatchSetup = false

    /// Steps-estimate calibration sheet (WHOOP 4.0). Reached from the Profile card's "Steps estimate"
    /// tap-through; explains the estimate, shows the current fit + a recent estimated-vs-phone table,
    /// and offers a manual coefficient override. See [StepsCalibrationSheet].
    @State private var showStepsCalibration = false

    /// iOS environment-diagnostics sheet (device, iOS+build, Data Protection, background refresh,
    /// low-power, sideload + cert expiry). iOS-only; the macOS strap log already carries OS + version.
    @State private var showDiagnostics = false

    /// User-initiated GitHub release check behind the About "Check for updates" button.
    @StateObject private var updateChecker = UpdateChecker()
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScreenScaffold(title: "Settings",
                       subtitle: "Your numbers, your strap, and how NOOP works. All on \(Platform.deviceNounPhrase).",
                       // Shared day-cycle scene behind the header (flattened to one GPU layer), as on Today.
                       topBackground: showDayCycleBackground
                           ? AnyView(SceneScreenBackground().drawingGroup()) : nil) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                profileGroup.staggeredAppear(index: 0)
                unitsGroup.staggeredAppear(index: 1)
                appearanceGroup.staggeredAppear(index: 2)
                strapGroup.staggeredAppear(index: 3)
                recoveryGroup.staggeredAppear(index: 4)
                featuresGroup.staggeredAppear(index: 5)
                testCentreCard.staggeredAppear(index: 6)
                experimentalGroup.staggeredAppear(index: 7)
                backupGroup.staggeredAppear(index: 8)
                aboutGroup.staggeredAppear(index: 9)
            }
        }
        .alert(backupAlertTitle, isPresented: $showBackupAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(backupAlertMessage)
        }
        .confirmationDialog("Recalibrate your Charge baseline?",
                            isPresented: $showRecalibrateConfirm, titleVisibility: .visible) {
            Button("Recalibrate") { recalibrateHrvBaseline() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This restarts the roughly 4-night build-up for Charge and your HRV baseline. Your history stays. Use it if a bad first week, like wearing it while sick, set your baseline off.")
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(onClose: { showWhatsNew = false })
        }
        .sheet(isPresented: $showScoringGuide) {
            ScoringGuideView(onClose: { showScoringGuide = false })
        }
        .sheet(isPresented: $showHowNoopWorks) {
            HowNoopWorksView(onClose: { showHowNoopWorks = false })
        }
        .sheet(isPresented: $showAppleWatchSetup) {
            AppleWatchSetupView(onClose: { showAppleWatchSetup = false })
        }
        .sheet(isPresented: $showStepsCalibration) {
            StepsCalibrationSheet(repo: model.repo, onClose: { showStepsCalibration = false })
                .environmentObject(profile)
        }
        #if os(iOS)
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsSheet(onClose: { showDiagnostics = false })
        }
        #endif
        // Liquid Glass for the Settings groups (SettingsGroup → NoopCard, glass-aware). Cascades
        // via the environment; neutral glass when on, frosted fallback otherwise (below iOS 26 / macOS).
        .environment(\.noopGlassSurface, useGlassSurface)
    }

    // MARK: - Profile (photo + the fields that power zones / calories / recovery)

    /// One grouped-list section: an optional on-device photo, then the body fields. PhotosUI's
    /// `PhotosPicker` works on iOS 16+ and macOS 13+ (NOOP's floor), so the same control serves both.
    private var profileGroup: some View {
        SettingsGroup(
            header: "Profile",
            footer: "These power your heart-rate zones, calorie estimates and recovery baselines. Keep them accurate. Everything stays on \(Platform.deviceNounPhrase)."
        ) {
            // Optional avatar — tap the thumbnail to choose / change; stored on-device only.
            SettingsRow(icon: "person.crop.circle", title: "Photo",
                        subtitle: "Optional · on \(Platform.deviceNounPhrase) only") {
                HStack(spacing: NoopMetrics.space3) {
                    if profile.hasAvatar {
                        Button("Remove") { profile.clearAvatar() }
                            .buttonStyle(.plain)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .accessibilityHint("Reverts to the default profile icon")
                    }
                    PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                        ProfileAvatarView(imageData: profile.avatarImageData, size: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(profile.hasAvatar ? "Change profile photo" : "Choose profile photo")
                }
            }
            SettingsRow(icon: "calendar", title: "Age") {
                HStack(spacing: NoopMetrics.space3) {
                    Text("\(profile.age)")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(minWidth: 28, alignment: .trailing)
                    Stepper("Age", value: $profile.age, in: 13...100)
                        .labelsHidden()
                        .accessibilityLabel("Age, \(profile.age) years")
                }
            }
            SettingsRow(icon: "person.fill", title: "Sex") {
                Picker("Sex", selection: $profile.sex) {
                    Text("Male").tag("male")
                    Text("Female").tag("female")
                    Text("Non-binary").tag("nonbinary")
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                .accessibilityLabel("Sex")
            }
            SettingsRow(icon: "scalemass", title: "Weight") {
                // Imperial mode steps in pounds and stores the kg equivalent; metric steps in kg.
                if unitSystem == .imperial {
                    poundsField(weightKg: $profile.weightKg)
                } else {
                    measureField(value: $profile.weightKg, unit: "kg",
                                 range: 30...250, step: 0.5, format: "%.1f",
                                 accessibility: "Weight in kilograms")
                }
            }
            SettingsRow(icon: "ruler", title: "Height") {
                // Imperial mode steps in whole inches and stores the cm equivalent; metric steps in cm.
                if unitSystem == .imperial {
                    feetInchesField(heightCm: $profile.heightCm)
                } else {
                    measureField(value: $profile.heightCm, unit: "cm",
                                 range: 120...230, step: 1, format: "%.0f",
                                 accessibility: "Height in centimetres")
                }
            }
            // Waist (optional, 0 = unset) — the ONE measurement that ADDS the VO₂max estimate. It does
            // NOT sharpen Fitness Age itself (the body term cancels in the Nes model), hence the honest
            // "adds your VO₂max estimate" subtitle rather than implying it tunes the age.
            SettingsRow(icon: "figure", title: "Waist",
                        subtitle: "Optional — adds your VO₂max estimate. Measure at the navel.") {
                if unitSystem == .imperial {
                    waistInchesField(waistCm: $profile.waistCm)
                } else {
                    waistCentimetresField(waistCm: $profile.waistCm)
                }
            }
            SettingsRow(icon: "heart.fill", title: "Max heart rate",
                        subtitle: profile.hrMaxOverride > 0 ? "Manual override · bpm"
                                                            : "Auto · \(profile.hrMax) bpm (Tanaka)") {
                hrMaxField
            }
            // Step calibration (#139/#132): daily steps = @57 counter ticks ÷ this divisor. Up to 30
            // because a 5/MG motion counter can overcount ~24×; the stepper increment scales near 1.0.
            SettingsRow(icon: "figure.walk", title: "Step calibration",
                        subtitle: "Counter ticks per step — leave at 1.0 unless steps run high (5/MG can run 10×+).") {
                HStack(spacing: NoopMetrics.space3) {
                    Text(String(format: "%.1f", profile.stepTicksPerStep))
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(minWidth: 44, alignment: .trailing)
                    Stepper("Step calibration") {
                        profile.stepTicksPerStep = ProfileStore.steppedStepScale(profile.stepTicksPerStep, up: true)
                    } onDecrement: {
                        profile.stepTicksPerStep = ProfileStore.steppedStepScale(profile.stepTicksPerStep, up: false)
                    }
                        .labelsHidden()
                        .accessibilityLabel("Step calibration, \(String(format: "%.1f", profile.stepTicksPerStep)) counter ticks per step")
                }
            }
            // Tap-through to the WHOOP 4.0 steps-ESTIMATE calibration (separate from the 5/MG divisor):
            // a 4.0 sends no step count, so NOOP estimates steps from motion and calibrates to the phone.
            SettingsRow(icon: "shoeprints.fill", title: "Steps estimate",
                        subtitle: "WHOOP 4.0 — calibrate the motion-based step estimate to your phone.",
                        value: stepsCalibrationSummary,
                        action: { showStepsCalibration = true })
        }
        // Load the picked photo's bytes, then hand them to the store (which downscales + persists).
        // Clearing the selection afterwards lets the user re-pick the same photo if they want.
        .onChange(of: avatarPickerItem) { newItem in
            guard let newItem else { return }
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data { profile.setAvatar(data) }
                    avatarPickerItem = nil
                }
            }
        }
    }

    /// One-line state for the "Steps estimate" tap-through row: manual, the auto-fit confidence, or a
    /// not-yet-calibrated prompt — so the row reflects the current calibration without opening the sheet.
    private var stepsCalibrationSummary: String {
        if profile.stepsManualCoefficient > 0 { return "Manual" }
        if profile.stepsCalibrationCoefficient > 0 {
            return "Auto · \(StepsCalibrationFormat.confidenceLabel(profile.stepsCalibrationConfidence)) confidence"
        }
        return "Not calibrated"
    }

    /// Numeric weight/height field: tabular value + small +/- stepper.
    private func measureField(value: Binding<Double>, unit: String,
                              range: ClosedRange<Double>, step: Double,
                              format: String, accessibility: String) -> some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: format, value.wrappedValue))
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(minWidth: 48, alignment: .trailing)
                Text(unit)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Stepper(accessibility, value: value, in: range, step: step)
                .labelsHidden()
                .accessibilityLabel(accessibility)
        }
    }

    /// Imperial weight entry: shows pounds, steps in 1-lb increments, and writes the kg equivalent back
    /// to the SI-stored profile. Range mirrors the metric 30…250 kg (≈66…551 lb).
    private func poundsField(weightKg: Binding<Double>) -> some View {
        let lb = Binding<Double>(
            get: { UnitFormatter.kgToPounds(weightKg.wrappedValue) },
            set: { weightKg.wrappedValue = $0 / UnitFormatter.poundsPerKilogram }
        )
        return HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", lb.wrappedValue))
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(minWidth: 48, alignment: .trailing)
                Text("lb")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Stepper("Weight in pounds", value: lb, in: 66...551, step: 1)
                .labelsHidden()
                .accessibilityLabel("Weight, \(Int(lb.wrappedValue.rounded())) pounds")
        }
    }

    /// Imperial height entry: shows feet′ inches″, steps in whole inches, and writes the cm equivalent
    /// back to the SI-stored profile. Range mirrors the metric 120…230 cm (≈47…91 in).
    private func feetInchesField(heightCm: Binding<Double>) -> some View {
        let inches = Binding<Double>(
            get: { UnitFormatter.cmToInches(heightCm.wrappedValue).rounded() },
            set: { heightCm.wrappedValue = $0 * UnitFormatter.centimetersPerInch }
        )
        let parts = UnitFormatter.cmToFeetInches(heightCm.wrappedValue)
        return HStack(spacing: 10) {
            Text("\(parts.feet)′ \(parts.inches)″")
                .font(StrandFont.bodyNumber)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(minWidth: 56, alignment: .trailing)
            Stepper("Height in inches", value: inches, in: 47...91, step: 1)
                .labelsHidden()
                .accessibilityLabel("Height, \(parts.feet) feet \(parts.inches) inches")
        }
    }

    /// Metric waist entry: 0 = unset (shows a muted "Not set" rather than a misleading 0 cm). Steps in
    /// 1-cm increments; the first increment from unset lands at a sensible 80 cm so the stepper doesn't
    /// crawl up from the range floor. Mirrors `measureField` but tolerant of the optional empty state.
    private func waistCentimetresField(waistCm: Binding<Double>) -> some View {
        let set = waistCm.wrappedValue > 0
        return HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(set ? String(format: "%.0f", waistCm.wrappedValue) : "Not set")
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(set ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                    .frame(minWidth: 48, alignment: .trailing)
                if set {
                    Text("cm")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            Stepper("Waist in centimetres") {
                waistCm.wrappedValue = min(160, (set ? waistCm.wrappedValue : 79) + 1)
            } onDecrement: {
                // Stepping below the 60-cm floor clears it back to unset (optional).
                let next = waistCm.wrappedValue - 1
                waistCm.wrappedValue = next < 60 ? 0 : next
            }
                .labelsHidden()
                .accessibilityLabel(set ? "Waist, \(Int(waistCm.wrappedValue.rounded())) centimetres" : "Waist not set")
        }
    }

    /// Imperial waist entry: 0 = unset (muted "Not set"); otherwise shows whole inches and stores the cm
    /// equivalent — the same metric/imperial treatment as Height. First increment from unset lands near a
    /// sensible 31″. Range mirrors the metric 60…160 cm (≈24…63 in).
    private func waistInchesField(waistCm: Binding<Double>) -> some View {
        let set = waistCm.wrappedValue > 0
        let inches = set ? UnitFormatter.cmToInches(waistCm.wrappedValue).rounded() : 0
        return HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(set ? "\(Int(inches))" : "Not set")
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(set ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                    .frame(minWidth: 48, alignment: .trailing)
                if set {
                    Text("in")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            Stepper("Waist in inches") {
                let nextIn = (set ? inches : 30) + 1
                waistCm.wrappedValue = min(160, nextIn * UnitFormatter.centimetersPerInch)
            } onDecrement: {
                let nextIn = inches - 1
                // Stepping below the ~24″ floor clears it back to unset (optional).
                waistCm.wrappedValue = nextIn < 24 ? 0 : nextIn * UnitFormatter.centimetersPerInch
            }
                .labelsHidden()
                .accessibilityLabel(set ? "Waist, \(Int(inches)) inches" : "Waist not set")
        }
    }

    /// HR-max override: 0 = auto. Shown as a compact tabular value with a stepper.
    private var hrMaxField: some View {
        HStack(spacing: 10) {
            Text(profile.hrMaxOverride > 0 ? "\(profile.hrMaxOverride)" : "Auto")
                .font(StrandFont.bodyNumber)
                .foregroundStyle(profile.hrMaxOverride > 0
                                 ? StrandPalette.textPrimary
                                 : StrandPalette.textTertiary)
                .frame(minWidth: 44, alignment: .trailing)
            Stepper("Max heart rate override",
                    value: $profile.hrMaxOverride, in: 0...230, step: 1)
                .labelsHidden()
                .accessibilityLabel("Max heart rate override, \(profile.hrMaxOverride == 0 ? "automatic" : "\(profile.hrMaxOverride) bpm")")
        }
    }

    // MARK: - Units

    /// Imperial/Metric display toggle + a separate temperature override. Display-only — nothing stored
    /// changes, NOOP keeps everything in SI and converts at the point of display.
    private var unitsGroup: some View {
        SettingsGroup(
            header: "Units",
            footer: "Display only — your data is always stored the same way; this just changes how it's shown."
        ) {
            SettingsRow(icon: "ruler", title: "Measurement system") {
                Picker("Measurement system", selection: $unitSystemRaw) {
                    Text("Metric").tag(UnitSystem.metric.rawValue)
                    Text("Imperial").tag(UnitSystem.imperial.rawValue)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                .accessibilityLabel("Measurement system")
            }
            // Three-way: "Match" follows the system above; °C / °F pin it explicitly.
            SettingsRow(icon: "thermometer.medium", title: "Temperature") {
                Picker("Temperature", selection: $temperatureRaw) {
                    Text("Match").tag("")
                    Text("°C").tag(TemperatureUnit.celsius.rawValue)
                    Text("°F").tag(TemperatureUnit.fahrenheit.rawValue)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                .accessibilityLabel("Temperature unit")
            }
            // Effort scale (#268) — NOOP's native 0–100 or WHOOP's 0–21 Day Strain axis. Display-only.
            SettingsRow(icon: "bolt.fill", title: "Effort scale") {
                Picker("Effort scale", selection: $effortScaleRaw) {
                    Text("0–100").tag(EffortScale.hundred.rawValue)
                    Text("0–21").tag(EffortScale.whoop.rawValue)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                .accessibilityLabel("Effort scale")
            }
        }
    }

    // MARK: - Appearance (Theme everywhere; alternate app icon iOS-only)

    /// Theme (System / Light / Dark) on every platform, plus the iOS app-icon choice. The Theme picker
    /// writes `AppearanceMode.storageKey`, which both app roots read via `.preferredColorScheme`; because
    /// every palette token is a dynamic `Color(light:dark:)`, the whole UI re-resolves on change.
    private var appearanceGroup: some View {
        SettingsGroup(
            header: "Appearance",
            footer: "Dark is the signature near-black; Light keeps the same clean look on a bright canvas."
        ) {
            SettingsRow(icon: "circle.lefthalf.filled", title: "Theme") {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                .accessibilityLabel("Theme")
            }
            // Default = NOOP's clean metric ramps; Classic = the throwback red→amber→green scale.
            SettingsRow(icon: "paintpalette", title: "Chart colours") {
                Picker("Chart colours", selection: $chartStyleRaw) {
                    ForEach(ChartStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                .accessibilityLabel("Chart colours")
            }
            #if os(iOS)
            SettingsRow(icon: "app.badge", title: "App icon") {
                Picker("App icon", selection: $useNavyIcon) {
                    Text("Default").tag(false)
                    Text("Navy").tag(true)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                .accessibilityLabel("App icon")
                .onChangeCompat(of: useNavyIcon) { applyAppIcon($0) }
            }
            #endif
            // Day-cycle background — the time-of-day scene behind Today (#698). On by default.
            SettingsRow(icon: "sun.haze.fill", title: "Day-cycle background",
                        subtitle: "A soft sunrise → day → dusk → night scene behind Today. Off = plain dark canvas.") {
                Toggle("", isOn: $showDayCycleBackground)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Day-cycle background")
            }
        }
    }

    #if os(iOS)
    /// Apply the alternate-icon choice. Runs on the main actor (UIKit requirement) and tolerates the
    /// no-op cases (already-set, unsupported); on failure it surfaces the error and reverts the toggle
    /// so the control never disagrees with what's actually on the Home Screen.
    private func applyAppIcon(_ useNavy: Bool) {
        Task { @MainActor in
            let target = useNavy ? "AppIcon-Navy" : nil
            // No-op if iOS already shows the requested icon (avoids a needless system prompt).
            guard UIApplication.shared.supportsAlternateIcons,
                  UIApplication.shared.alternateIconName != target else { return }
            do {
                try await UIApplication.shared.setAlternateIconName(target)
            } catch {
                useNavyIcon = !useNavy
                backupAlertTitle = "Couldn't change the app icon"
                backupAlertMessage = error.localizedDescription
                showBackupAlert = true
            }
        }
    }
    #endif

    // MARK: - Strap

    private var strapGroup: some View {
        SettingsGroup(
            header: "Strap",
            footer: "NOOP pairs directly with your WHOOP over Bluetooth — no WHOOP app, no cloud."
        ) {
            // Connection status + battery + the two primary actions — a rich block, inset to the grid.
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: NoopMetrics.space3) {
                    StatePill("\(strapStatusTitle)", tone: strapTone, pulsing: live.connected)
                    if let pct = live.batteryPct {
                        StatePill(live.charging == true
                                  ? "Battery \(Int(pct.rounded()))% · Charging"
                                  : "Battery \(Int(pct.rounded()))%",
                                  tone: batteryTone(pct), showsDot: false)
                    }
                    Spacer(minLength: 0)
                }
                Text(strapStatusDetail)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: NoopMetrics.space3) {
                    NoopButton("Re-scan", systemImage: "arrow.clockwise", kind: .primary) { model.scan() }
                    NoopButton("Disconnect", systemImage: "xmark.circle", kind: .secondary) { model.disconnect() }
                        .disabled(!live.connected && !live.bonded)
                }
            }
            .settingsRowInsets()

            // Strap log — a Settings shortcut so people don't have to hunt for it on the Live screen
            // (#507/#509). Copy / Save sit in the trailing slot; the subtitle says why you'd want it.
            SettingsRow(icon: "doc.text", title: "Strap log",
                        subtitle: "Grab this for a bug report — it tells me what the app saw.") {
                HStack(spacing: NoopMetrics.space3) {
                    Button("Copy") { PlatformPasteboard.copy(live.exportableLogText()) }
                        .buttonStyle(.plain).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.accent)
                    Button("Save…") {
                        FileExport.exportText(live.exportableLogText(),
                                              suggestedName: FileExport.timestampedName("noop-strap-log", ext: "txt"))
                    }
                    .buttonStyle(.plain).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.accent)
                }
            }

            // Continuous HRV capture — keep the dense beat-to-beat (R-R) stream armed 24/7.
            SettingsRow(icon: "waveform.path.ecg", title: "Continuous HRV capture",
                        subtitle: "Keeps the beat-to-beat stream armed day and night for better overnight HRV, recovery and sleep. Uses more battery.") {
                Toggle("", isOn: $continuousHrvEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Continuous HRV capture")
            }
            .onChangeCompat(of: continuousHrvEnabled) { on in model.ble.setKeepRealtimeForData(on) }

            // Strap name — rename the WHOOP 4.0's BLE advertising name (Harvard command set).
            if live.connected && selectedWhoopModelRaw == WhoopModel.whoop4.rawValue {
                strapNameControl.settingsRowInsets()
            }

            #if os(iOS)
            // Live Activity — show live HR on the Lock Screen + Dynamic Island (#336).
            SettingsRow(icon: "bolt.heart", title: "Live HR in Dynamic Island",
                        subtitle: "Shows your live heart rate on the Lock Screen and Dynamic Island while connected.") {
                Toggle("", isOn: $liveActivityEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Live heart rate in Dynamic Island")
            }
            #endif
        }
    }

    /// Rename the WHOOP 4.0's BLE advertising name. Shows the current name (read back from firmware in
    /// the connect handshake → `LiveState.advertisingName`) and writes a new one via `renameStrap`. The
    /// strap reboots to apply, so the new name lands on the next connect. WHOOP 4.0 only (Harvard).
    @ViewBuilder private var strapNameControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Strap name").strandOverline()
            Text("Current: \(live.advertisingName ?? "—")")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            HStack(spacing: NoopMetrics.space3) {
                TextField("New strap name", text: $strapNameDraft)
                    .textFieldStyle(.plain)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .padding(.horizontal, NoopMetrics.space3)
                    .padding(.vertical, 9)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                    .disableAutocorrection(true)
                    .accessibilityLabel("New strap name")
                NoopButton("Rename", systemImage: "pencil", kind: .primary) {
                    model.ble.renameStrap(strapNameDraft)
                }
                .disabled(strapNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let status = live.renameStatus {
                Text(status)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Text("Changes the Bluetooth name your WHOOP 4.0 advertises — what you see when pairing. The strap reboots to apply, so the new name appears the next time it connects. WHOOP 4.0 only.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Shares LiveState.connectionStatus* with the sidebar footer (RootView) so the two never drift (#266).
    private var strapStatusTitle: String { live.connectionStatusLabel }

    private var strapTone: StrandTone {
        if live.connectionStatusIsActive { return .positive }
        if live.connectionStatusIsIdle { return .warning }
        return .critical
    }

    private var strapStatusDetail: String {
        if live.bonded && live.connected {
            return "Your strap is paired and sending data. Open Live for a real-time heart rate."
        }
        if live.connected, let hint = live.pairingHint { return hint }
        if live.connected { return "Connected. Finishing the secure pairing handshake…" }
        if live.bonded { return "Previously paired but not currently connected. Re-scan to reconnect." }
        return "No strap connected. Put your WHOOP nearby and tap Re-scan to pair."
    }

    private func batteryTone(_ pct: Double) -> StrandTone {
        if pct <= 15 { return .critical }
        if pct <= 30 { return .warning }
        return .positive
    }

    // MARK: - Recovery (Charge baseline)

    /// Advanced recovery controls. The Recalibrate button re-anchors the whole Charge (recovery)
    /// baseline from tonight onward — the cure for a baseline poisoned by a bad first week (worn sick,
    /// or an early reading that anchored too high). It writes now (epoch SECONDS) to BOTH the
    /// `noop.hrvBaselineEpoch` and `noop.recoveryBaselineEpoch` settings the recovery engine reads, then
    /// kicks a recompute the same way the sleep-edit path does (analyzeRecent → refresh). History stays.
    private var recoveryGroup: some View {
        SettingsGroup(
            header: "Recovery",
            footer: "Charge learns a personal baseline from your HRV, resting heart rate and more. If a bad first week set it off, re-learn it from tonight — your history stays."
        ) {
            SettingsRow(icon: "arrow.triangle.2.circlepath", title: "Recalibrate Charge baseline",
                        subtitle: "Restarts the ~4-night build-up from tonight. Use it if a bad first week set your baseline off.",
                        action: { showRecalibrateConfirm = true })
        }
    }

    /// Write the recalibration anchor and trigger a recompute. Re-anchors EVERY baseline that feeds
    /// Charge — HRV plus resting HR / respiration / skin temp — by writing now (epoch SECONDS) to both
    /// `noop.hrvBaselineEpoch` and `noop.recoveryBaselineEpoch` via the single cross-platform source of
    /// truth (`Baselines.recalibrateRecoveryBaselines`). No stored day is deleted; only the day the
    /// baselines re-learn from moves. Then re-score + refresh so the change is reflected without a
    /// relaunch (same path as a sleep edit), and Today honestly shows the building/calibrating state.
    private func recalibrateHrvBaseline() {
        Baselines.recalibrateRecoveryBaselines()
        Task {
            await model.intelligence.analyzeRecent()
            await model.repo.refresh()
        }
        backupAlertTitle = "Charge baseline recalibrating"
        backupAlertMessage = "NOOP will re-learn your baseline from tonight's data onward. Your history is kept, and it takes a few nights to settle."
        showBackupAlert = true
    }

    // MARK: - Test Centre (the diagnostic home, #507/#509)

    /// A nav row into the Test Centre, the single home for the diagnostic, log and test controls (spec
    /// section 7). The strap log, recalibrate, scheduled export and experimental toggles also live there
    /// on the same bindings, so this is a faster door to the full set without growing this screen.
    private var testCentreCard: some View {
        SettingsGroup(
            header: "Test Centre",
            footer: "Turn on a test for the thing that's wrong, wear the strap, then tap Report. Your strap log, recalibrate, scheduled export and experimental probes all live here too."
        ) {
            NavigationLink {
                TestCentreView()
            } label: {
                aboutRowLabel(icon: "testtube.2", title: "Open Test Centre",
                              subtitle: "The single home for the diagnostic, log and test controls.")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Test Centre")
        }
    }

    // MARK: - Features (opt-in trackers)

    /// Opt-in, manual-first feature toggles (default OFF). Hydration tracking gates the water-log card on
    /// the Today dashboard and its detail screen — nothing is shown or stored until it's enabled.
    private var featuresGroup: some View {
        SettingsGroup(
            header: "Features",
            footer: "Optional trackers, off by default. Turn them on to add their cards. Everything stays on \(Platform.deviceNounPhrase)."
        ) {
            SettingsRow(icon: "drop.fill", title: "Hydration tracking",
                        subtitle: "Adds a fluid log with a goal that adjusts to your effort — tap to add a sip, cup or bottle.") {
                Toggle("", isOn: $hydrationEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Hydration tracking")
                    .accessibilityHint("Adds a water-log card to your dashboard")
            }
            SettingsRow(icon: "figure.run", title: "Auto-detect workouts",
                        subtitle: "After a sync, offers to save a sustained raised-HR stretch as a workout. Only ever suggests — nothing saved until you tap Save.") {
                Toggle("", isOn: $autoDetectWorkoutsEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Auto-detect workouts")
                    .accessibilityHint("Offers to save a workout when it spots sustained elevated heart rate")
            }
            SettingsRow(icon: "display", title: "Keep screen on during a workout",
                        subtitle: "Holds the screen awake while you're recording so live heart rate stays visible. Only applies during a workout.") {
                Toggle("", isOn: $workoutKeepScreenOn)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Keep screen on during a workout")
                    .accessibilityHint("Stops the screen dimming while a workout is recording")
            }
        }
    }

    // MARK: - Backup & restore

    // MARK: - Experimental (WHOOP 5 / MG)

    /// Entry point used by `body`. The 5/MG probe card only renders for a 5/MG (see `showFiveMGControls`,
    /// #22); the raw-sensor CSV diagnostic is split into its own card so it stays available on every
    /// model — a 4.0 owner still needs the export to share decoded streams.
    @ViewBuilder private var experimentalGroup: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            if showFiveMGControls { fiveMGGroup }
            sleepStagingGroup
            rawSensorDiagnosticsGroup
        }
    }

    /// Opt-in experimental sleep staging (V2). Model-agnostic — the V2 recipe works on WHOOP 4 and 5 — so it
    /// renders on every strap, separate from the 5/MG probe card. Default OFF; flipping it on re-stages
    /// future (and re-derived) nights with `SleepStagerV2`. The default V1 stager is untouched.
    private var sleepStagingGroup: some View {
        SettingsGroup(
            header: "Experimental · Sleep staging",
            footer: "A separate, opt-in recipe for splitting a night into light / deep / REM — your default staging is unchanged unless you turn it on. Takes effect on the next nights staged."
        ) {
            SettingsRow(icon: "bed.double.fill", title: "Sleep staging (V2)",
                        subtitle: "A transparent cardiorespiratory recipe that recovers deep and REM better. Detection and scores are unchanged.") {
                Toggle("", isOn: $experimentalSleepV2Enabled)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Experimental sleep staging V2")
            }
        }
    }

    /// The R22 "send enable sequence" button is structurally impossible on macOS — a Mac can't form the
    /// encrypted bond a 5/MG needs to accept the write (BLEManager forms a live-HR-only link there), so it
    /// stays disabled regardless of bond/wear state (#587). On iOS/Android it gates on the real bond + wear.
    private var deepDataButtonDisabled: Bool {
        #if os(macOS)
        return true
        #else
        return !live.encryptedBond || !live.worn
        #endif
    }

    /// The reason line under the R22 button. macOS gets an explicit "needs an iPhone/Android" message
    /// rather than the misleading "needs the full encrypted bond" one (a Mac can never get that bond).
    private var deepDataButtonReason: String {
        #if os(macOS)
        return "Deep data (R22) needs an iPhone or Android — a Mac can't form the encrypted bond a 5/MG requires."
        #else
        if !live.encryptedBond {
            return "Needs the full encrypted bond — close the official WHOOP app and pair the strap to NOOP first (a live-HR-only link can't carry the unlock)."
        }
        return live.worn
            ? "Wear the strap, tap once, then let it sync and share your strap log."
            : "Put the strap on first — the deep stream is on-wrist only."
        #endif
    }

    private var fiveMGGroup: some View {
        SettingsGroup(
            header: "Experimental · WHOOP 5 / MG",
            footer: "Probes that try to coax more out of a 5/MG strap. Guesses, off by default, and only ever touch a 5/MG — WHOOP 4.0 is never affected."
        ) {
            SettingsRow(icon: "flask.fill", title: "Protocol probes",
                        subtitle: "Sends a puffin realtime-stream request after the handshake and logs what comes back. Sharing the strap log helps map the protocol.") {
                Toggle("", isOn: $puffinExperiments)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Try WHOOP 5/MG protocol probes")
            }

            // R22 deep-data unlock — the one probe that writes to the strap.
            SettingsRow(icon: "lock.open.fill", title: "Unlock deep data (R22)",
                        subtitle: "Writes the documented feature-flag sequence the official app uses to switch on high-rate HR + motion + history. Reversible. iPhone/Android only.") {
                Toggle("", isOn: $deepDataEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Unlock WHOOP 5/MG deep data R22")
            }
            if deepDataEnabled {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    NoopButton("Send enable sequence to strap", systemImage: "bolt.badge.automatic", kind: .primary) {
                        model.ble.enableWhoop5DeepData()
                    }
                    .disabled(deepDataButtonDisabled)
                    Text(deepDataButtonReason)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Live R22 telemetry (#174): proof of what the strap is doing right now.
                    if live.r22FlagsAccepted > 0 {
                        Label(live.r22FlagsAccepted >= 15
                              ? "Strap accepted all 15 R22 flags"
                              : "Strap accepted \(live.r22FlagsAccepted)/15 R22 flags…",
                              systemImage: live.r22FlagsAccepted >= 15 ? "checkmark.seal.fill" : "ellipsis")
                            .font(StrandFont.caption)
                            .foregroundStyle(live.r22FlagsAccepted >= 15 ? StrandPalette.statusPositive : StrandPalette.textSecondary)
                    }
                    if live.deepPacketsThisSession > 0 {
                        Label("\(live.deepPacketsThisSession) type-0x2F historical-offload frame\(live.deepPacketsThisSession == 1 ? "" : "s") seen outside our sync — these are history (e.g. another app pulling the strap's backlog), not a live R22 stream (#494).",
                              systemImage: "clock.arrow.circlepath")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    } else if live.r22FlagsAccepted >= 15 {
                        Text("Flags accepted, but the enable sequence doesn't start a separate live stream — the deep records arrive as part of the normal history sync (#494).")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .settingsRowInsets()
            }

            // Broadcast HR — make the strap a standard BLE HR sensor (Garmin/Zwift/gym).
            SettingsRow(icon: "dot.radiowaves.left.and.right", title: "Broadcast heart rate",
                        subtitle: "Advertises HR as a standard Bluetooth sensor for Garmin / Zwift / gym kit. Reversible. iPhone-side only.") {
                Toggle("", isOn: $broadcastHrEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Broadcast heart rate")
            }
            .onChangeCompat(of: broadcastHrEnabled) { on in model.ble.setBroadcastHr(on) }
            // #573: leaving broadcast on keeps the strap radio hot — surface that, persistently.
            if broadcastHrEnabled {
                HStack(alignment: .top, spacing: NoopMetrics.space2) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(StrandPalette.statusWarning)
                        .accessibilityHidden(true)
                    Text("Broadcast HR is ON — your strap is advertising continuously, which drains the battery faster. Turn it off when you're not using it with another device.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.statusWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .settingsRowInsets()
            }

            SettingsRow(icon: "doc.badge.gearshape", title: "Record puffin frames",
                        subtitle: "Saves every raw 5/MG frame to a JSON file to help map the biometric layout. Read-only — never writes to your strap.") {
                Toggle("", isOn: $puffinCapture)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Record puffin frames to a file")
            }
            if live.puffinCaptureCount > 0 {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text("\(live.puffinCaptureCount) frame\(live.puffinCaptureCount == 1 ? "" : "s") captured this session.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    HStack(spacing: NoopMetrics.space3) {
                        NoopButton("Export frames…", systemImage: "square.and.arrow.up", kind: .primary) {
                            exportPuffinCaptures()
                        }
                        #if os(macOS)
                        NoopButton("Reveal in Finder", systemImage: "folder", kind: .secondary) {
                            revealPuffinCaptures()
                        }
                        #endif
                        Spacer(minLength: 0)
                    }
                    // One-tap matched-pair export (#510): the raw capture + the strap log together.
                    NoopButton("Export raw + log", systemImage: "square.and.arrow.up.on.square", kind: .secondary) {
                        exportRawAndLog()
                    }
                    Text("Saves the raw capture and the strap log together as a matched pair — attach both to a protocol-mapping issue.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .settingsRowInsets()
            }
        }
    }

    // MARK: - Diagnostics (every model)

    /// Raw-sensor CSV export — a read-only diagnostic over the decoded streams NOOP already stores
    /// (HR, R-R, motion, steps, PPG-HR, SpO₂, skin temp, resp, events). Split out of the 5/MG card so it
    /// stays visible on EVERY model (#22): a WHOOP 4.0 owner still needs this to share decoded data.
    private var rawSensorDiagnosticsGroup: some View {
        SettingsGroup(
            header: "Diagnostics",
            footer: "Read-only exports of the decoded streams NOOP already stores. Works on any strap — nothing is written to your device, nothing uploaded."
        ) {
            // Export raw sensor data (CSV) — a read-only diagnostic over the decoded streams NOOP
            // stores (HR, R-R, motion, steps, PPG-HR, SpO₂, skin temp, resp, events).
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Button {
                    exportRawSensorCSV()
                } label: {
                    if rawCsvBusy {
                        HStack(spacing: NoopMetrics.space1 + 2) {
                            ProgressView().controlSize(.small)
                            Text("Exporting…")
                        }
                    } else {
                        Label("Export raw sensor data (CSV)", systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(NoopButtonStyle(.secondary))
                .disabled(rawCsvBusy)

                #if os(macOS)
                if let url = lastRawCsvURL {
                    NoopButton("Reveal in Finder", systemImage: "folder", kind: .secondary) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                #endif

                Text("The last 24 h of decoded per-sample streams (HR, R-R, motion, steps, SpO₂, skin temp, respiration, events) to one CSV — all on \(Platform.deviceNounPhrase). Share it to help prototype sleep, activity and strength algorithms.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingsRowInsets()

            scheduledExportControls
        }
        // Re-arm / catch-up the daily export whenever Settings appears (self-heals after a relaunch).
        .onAppear { ScheduledDebugExport.activateIfEnabled() }
    }

    /// Daily auto-export of the strap log (#510 — parity with Android's DebugExportScheduler). Opt-in,
    /// default OFF: a toggle + a time-of-day picker + a "Run now". Honest about iOS background timing —
    /// the macOS drop is reliable (the app is usually running), the iOS one fires when iOS next wakes
    /// NOOP near the chosen time, never guaranteed to the minute.
    @ViewBuilder private var scheduledExportControls: some View {
        SettingsRow(icon: "clock.arrow.circlepath", title: "Daily auto-export",
                    subtitle: LocalizedStringKey(debugExportCaption)) {
            Toggle("", isOn: $debugExportOn)
                .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                .accessibilityLabel("Daily auto-export of the strap log")
        }
        .onChangeCompat(of: debugExportOn) { on in ScheduledDebugExport.setEnabled(on) }

        if debugExportOn {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack {
                    Text("Time of day")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    DatePicker("", selection: debugExportTimeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityLabel("Daily auto-export time")
                }
                NoopButton("Run now", systemImage: "square.and.arrow.down.on.square", kind: .secondary) {
                    runScheduledExportNow()
                }
            }
            .settingsRowInsets()
        }
    }

    /// Honest caption — the drop location plus the platform-specific timing reality.
    private var debugExportCaption: String {
        #if os(iOS)
        return "Writes a timestamped copy of your strap log to NOOP's folder in the Files app, once a day — handy for a bug report without remembering to grab it. On iPhone it fires when iOS next wakes NOOP near your chosen time, not guaranteed to the minute (keep NOOP open overnight for the best chance). Everything stays on \(Platform.deviceNounPhrase); nothing is uploaded."
        #else
        return "Writes a timestamped copy of your strap log to your Documents folder, once a day — handy for a bug report without remembering to grab it. On Mac it runs while NOOP is open (and catches up on launch if the time passed while it was closed). Everything stays on \(Platform.deviceNounPhrase); nothing is uploaded."
        #endif
    }

    /// Bridges the minutes-since-midnight store to the DatePicker, persisting + rescheduling on change
    /// (mirrors SmartAlarmView's wakeBinding).
    private var debugExportTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = debugExportMinutes / 60
                c.minute = debugExportMinutes % 60
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                let m = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                debugExportMinutes = m
                ScheduledDebugExport.setTimeMinutes(m)
            }
        )
    }

    /// "Run now": write an immediate timestamped strap-log drop (with the raw capture beside it, if a
    /// session has recorded one) and tell the user where it landed.
    private func runScheduledExportNow() {
        model.ble.flushPuffinCaptures()
        let url = ScheduledDebugExport.runNow(captureURL: live.puffinCaptureURL)
        if let url {
            backupAlertTitle = "Strap log exported"
            #if os(iOS)
            backupAlertMessage = "Saved \(url.lastPathComponent) to NOOP's folder in the Files app."
            #else
            backupAlertMessage = "Saved \(url.lastPathComponent) to your Documents folder."
            #endif
        } else {
            backupAlertTitle = "Export failed"
            backupAlertMessage = "Couldn't write the strap log right now."
        }
        showBackupAlert = true
    }

    /// Export the last 24h of decoded sensor streams for the connected strap to a CSV, then save (macOS
    /// NSSavePanel) or share (iOS share sheet) — the same pattern as exportPuffinCaptures(). The store
    /// handle and the strap deviceId both come from the app's single "my-whoop" id.
    private func exportRawSensorCSV() {
        rawCsvBusy = true
        Task {
            let since = Date().timeIntervalSince1970 - 24 * 60 * 60
            guard let store = await model.repo.storeHandle() else {
                await MainActor.run {
                    rawCsvBusy = false
                    backupAlertTitle = "Export failed"
                    backupAlertMessage = "Couldn't open the local store."
                    showBackupAlert = true
                }
                return
            }
            do {
                let url = try await store.exportRawCSV(deviceId: model.deviceId, since: since)
                await MainActor.run {
                    rawCsvBusy = false
                    lastRawCsvURL = url
                    #if os(macOS)
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.commaSeparatedText]
                    panel.nameFieldStringValue = url.lastPathComponent
                    panel.canCreateDirectories = true
                    guard panel.runModal() == .OK, let dest = panel.url else { return }
                    let fm = FileManager.default
                    do {
                        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                        try fm.copyItem(at: url, to: dest)
                    } catch {
                        backupAlertTitle = "Export failed"
                        backupAlertMessage = error.localizedDescription
                        showBackupAlert = true
                    }
                    #else
                    FileExport.exportFile(at: url)
                    #endif
                }
            } catch {
                await MainActor.run {
                    rawCsvBusy = false
                    backupAlertTitle = "Export failed"
                    backupAlertMessage = error.localizedDescription
                    showBackupAlert = true
                }
            }
        }
    }

    /// Flush the in-flight capture, then copy it to a user-chosen location (save panel on macOS) or
    /// hand it to the system share sheet (iOS).
    private func exportPuffinCaptures() {
        model.ble.flushPuffinCaptures()
        guard let src = live.puffinCaptureURL else { return }
        // Suggest a friendly, timestamped name so a reporter saving several captures gets sortable,
        // non-colliding files (#510) — e.g. noop-raw-capture-260617-1042.json.
        let suggested = FileExport.timestampedName("noop-raw-capture", ext: "json")
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = suggested
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: src, to: dest)
        } catch {
            backupAlertTitle = "Export failed"
            backupAlertMessage = error.localizedDescription
            showBackupAlert = true
        }
        #else
        FileExport.exportFile(at: src, suggestedName: suggested)
        #endif
    }

    /// One-tap matched-pair export (#510): export the raw puffin capture AND the strap log together,
    /// both stamped with the same `yyMMdd-HHmm` minute so they're obviously a pair. Reuses the existing
    /// export utilities — `FileExport.exportPair` shares both files in one iOS share sheet, and saves
    /// each via its own NSSavePanel on macOS (no new file plumbing).
    private func exportRawAndLog() {
        model.ble.flushPuffinCaptures()
        guard let capture = live.puffinCaptureURL else {
            backupAlertTitle = "Nothing to export"
            backupAlertMessage = "No raw capture has been recorded yet this session."
            showBackupAlert = true
            return
        }
        let stamp = FileExport.timestamp()
        FileExport.exportPair(
            file: capture, fileSuggestedName: "noop-raw-capture-\(stamp).json",
            text: live.exportableLogText(), textSuggestedName: "noop-strap-log-\(stamp).txt")
    }

    #if os(macOS)
    /// Flush, then reveal the capture file in Finder so the user can grab it directly.
    private func revealPuffinCaptures() {
        model.ble.flushPuffinCaptures()
        guard let url = live.puffinCaptureURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #endif

    private var backupGroup: some View {
        SettingsGroup(
            header: "Backup & restore",
            footer: "Export saves everything — history, sleeps, workouts, settings — to one file you can copy to another \(Platform.deviceNoun); import replaces this \(Platform.deviceNoun)'s data with a backup (needs a relaunch)."
        ) {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                // Three labelled buttons must share a narrow iPhone row without wrapping mid-word
                // (the labels otherwise broke to one character per line). Equal width + shrink-to-fit
                // keeps each on a single line. On iPhone the SF Symbol icons were the main space-thief
                // (~90pt/button) and there's no room for them in a 3-up row, so we drop to icon-less
                // text there; macOS is wide enough to keep the icons. No trailing Spacer/ProgressView
                // inside this HStack — either would steal a share of the equal-width row. (#188)
                HStack(spacing: NoopMetrics.space3) {
                    Button {
                        runExport()
                    } label: {
                        backupButtonLabel("Export…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                    .disabled(backupBusy)

                    Button {
                        runImport()
                    } label: {
                        backupButtonLabel("Import…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                    .disabled(backupBusy)

                    Button {
                        runCsvExport()
                    } label: {
                        backupButtonLabel("Export CSV…", systemImage: "tablecells")
                    }
                    .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                    .disabled(backupBusy)
                }

                if backupBusy {
                    HStack(spacing: NoopMetrics.space2) {
                        ProgressView().controlSize(.small)
                        Text("Working…")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(StrandPalette.textTertiary)
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                    Text("Importing overwrites everything currently on \(Platform.deviceNounPhrase). Your old data is kept in a side file just in case. NOOP needs a relaunch for an import to take effect. Export CSV writes a WHOOP-format zip of your days, sleeps, workouts and journal that re-imports into NOOP on Mac, iPhone, or Android — on-device computed rows are marked APPROXIMATE in its Source column; the full backup stays the lossless restore path.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .settingsRowInsets()
        }
    }

    // Equal-width, single-line label for the three Backup buttons. iPhone is too narrow to fit
    // an icon + text three-up, so it goes icon-less there; macOS keeps the SF Symbol. (#188)
    @ViewBuilder
    private func backupButtonLabel(_ title: String, systemImage: String) -> some View {
        // The NoopButtonStyle (fullWidth) owns the width + padding; the label just supplies the
        // content and the single-line shrink-to-fit so the 3-up iPhone row never wraps mid-word (#188).
        #if os(macOS)
        Label(title, systemImage: systemImage)
            .lineLimit(1).minimumScaleFactor(0.7)
        #else
        Text(title)
            .lineLimit(1).minimumScaleFactor(0.6)
        #endif
    }

    private func runExport() {
        backupBusy = true
        Task {
            let result = await DataBackup.runExport(checkpoint: { await model.repo.checkpointForBackup() })
            handleBackup(result)
        }
    }

    private func runImport() {
        backupBusy = true
        Task {
            let result = await DataBackup.runImport()
            handleBackup(result)
        }
    }

    private func runCsvExport() {
        backupBusy = true
        Task {
            let result = await CsvExport.run(repo: model.repo)
            backupBusy = false
            switch result {
            case .cancelled:
                return
            case .exported(let url):
                backupAlertTitle = "CSV exported"
                backupAlertMessage = "Saved to \(url.lastPathComponent). The zip re-imports into NOOP (Data Sources → WHOOP Export) on any Mac, iPhone, or Android device."
                showBackupAlert = true
            case .failure(let message):
                backupAlertTitle = "Export problem"
                backupAlertMessage = message
                showBackupAlert = true
            }
        }
    }

    @MainActor
    private func handleBackup(_ result: DataBackup.BackupResult) {
        backupBusy = false
        switch result {
        case .cancelled:
            return
        case .exported(let url):
            backupAlertTitle = "Backup exported"
            backupAlertMessage = "Saved to \(url.lastPathComponent). Copy this file to your other \(Platform.deviceNoun) and use Import there to restore everything."
            showBackupAlert = true
        case .imported:
            backupAlertTitle = "Backup imported"
            backupAlertMessage = "Your data has been restored. Quit and reopen NOOP for it to take effect."
            showBackupAlert = true
        case .failure(let message):
            backupAlertTitle = "Backup problem"
            backupAlertMessage = message
            showBackupAlert = true
        }
    }

    // MARK: - About

    /// The real marketing version straight from the bundle (CFBundleShortVersionString, set from
    /// project.yml MARKETING_VERSION), so the About pill can never go stale the way a hand-edited
    /// Swift constant can. Mirrors how Android's pill reads BuildConfig.VERSION_NAME. Falls back to
    /// the hand-maintained changelog version only if the Info.plist key is somehow missing.
    private var bundleVersionString: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? AppChangelog.currentVersion
    }

    private var aboutGroup: some View {
        SettingsGroup(
            header: "About",
            footer: "A standalone companion for your WHOOP — all your data, none of the cloud. An independent, experimental project, not the WHOOP app."
        ) {
            // Version header + What's new.
            HStack(spacing: NoopMetrics.space3) {
                Text("NOOP")
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                StatePill("v\(bundleVersionString)", tone: .neutral, showsDot: false)
                Spacer()
                NoopButton("What's new", systemImage: "sparkles", kind: .secondary) {
                    showWhatsNew = true
                }
                .fixedSize()
            }
            .settingsRowInsets()

            // How NOOP works — the four-section explainability primer.
            Button { showHowNoopWorks = true } label: {
                aboutRowLabel(icon: "questionmark.circle", title: "How NOOP works",
                              subtitle: "Sleep sorting, scores, recording, and where your numbers come from.")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("How NOOP works")

            // How your scores work — Charge / Effort / Rest + the confidence labels.
            Button { showScoringGuide = true } label: {
                aboutRowLabel(icon: "chart.bar.doc.horizontal", title: "How your scores work",
                              subtitle: "Charge, Effort and Rest — and how they differ from WHOOP.")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("How your scores work")

            // About Apple Watch data: what is supported when NOOP runs from Apple Watch data alone.
            NavigationLink {
                AppleWatchAboutView(onStartSetup: { showAppleWatchSetup = true })
            } label: {
                aboutRowLabel(icon: "applewatch", title: "About Apple Watch data",
                              subtitle: "Use NOOP with just an Apple Watch. What it's great at, and where it's lighter than a strap.")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About Apple Watch data")

            // Storage (#590) — on-device space breakdown + a one-tap clean-up.
            NavigationLink {
                StorageView()
            } label: {
                aboutRowLabel(icon: "internaldrive", title: "Storage",
                              subtitle: "Where NOOP's on-device space is going — and a one-tap clean-up.")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Storage")

            #if os(iOS)
            // iOS reality & diagnostics (iOS-only — macOS doesn't have these gotchas).
            iosDiagnosticsRow
            iphoneExpectations.settingsRowInsets()
            #endif

            // Check for updates — a single, user-initiated read of GitHub's public releases API.
            updateCheckBlock.settingsRowInsets()

            // Project home — NOOP's code, releases, issues and wiki live on GitHub.
            Link(destination: URL(string: "https://github.com/NoopApp/noop")!) {
                aboutRowLabel(icon: "chevron.left.forwardslash.chevron.right", title: "Project home & source",
                              subtitle: "GitHub — code, releases, issues and the wiki.", trailing: "arrow.up.right")
            }
            .accessibilityLabel("Project home and source code on GitHub")

            // Mirror — noop.fans carries every release alongside GitHub, so users have a fallback.
            Link(destination: URL(string: "https://noop.fans")!) {
                aboutRowLabel(icon: "arrow.triangle.2.circlepath", title: "Mirror — noop.fans",
                              subtitle: "Every release, mirrored. A fallback if GitHub is ever down.", trailing: "arrow.up.right")
            }
            .accessibilityLabel("Mirror at noop dot fans, a fallback if GitHub is down")

            // Medical disclaimer + attribution.
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(alignment: .top, spacing: NoopMetrics.space3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(StrandPalette.statusWarning)
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                    Text("NOOP is not a medical device — for informational and personal-insight use only, not to diagnose, treat, cure or prevent any condition. Talk to a clinician for medical advice.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().overlay(StrandPalette.hairline)
                Text("Built on").strandOverline()
                attribution(repo: "johnmiddleton12/my-whoop", note: "WHOOP 4.0 protocol")
                attribution(repo: "b-nnett/goose", note: "WHOOP 5.0 protocol")
                Text("Open-source BLE reverse-engineering work. Thank you.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .settingsRowInsets()
        }
    }

    /// Shared chrome for an About disclosure / link row: tinted icon square + title + subtitle + a
    /// trailing glyph, inset to the grouped-list grid. Used by the Button / NavigationLink / Link rows
    /// so they all read identically inside the About group.
    private func aboutRowLabel(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey,
                               trailing: String = "chevron.right") -> some View {
        HStack(alignment: .top, spacing: NoopMetrics.space3) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(StrandPalette.accent.opacity(0.16))
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StrandPalette.accent))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Text(subtitle).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: NoopMetrics.space2)
            Image(systemName: trailing)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
        }
        .settingsRowInsets()
        .contentShape(Rectangle())
    }

    /// The "Check for updates" block: the button + state line, the available-update detail, and the
    /// honest "only reads the version when you tap" caption. Kept as one inset block in the About group.
    @ViewBuilder private var updateCheckBlock: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(spacing: NoopMetrics.space2 + 2) {
                Button {
                    // Compare the ACTUAL installed bundle version against GitHub's latest (#697-adjacent).
                    updateChecker.check(currentVersion: bundleVersionString)
                } label: {
                    if updateChecker.state == .checking {
                        HStack(spacing: NoopMetrics.space1 + 2) {
                            ProgressView().controlSize(.small)
                            Text("Checking…")
                        }
                    } else {
                        Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(NoopButtonStyle(.secondary))
                .disabled(updateChecker.state == .checking)

                if case .upToDate(let v) = updateChecker.state {
                    Text("You're on the latest (\(v)).")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                } else if case .failed = updateChecker.state {
                    Text("Couldn't check. Try again.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.statusWarning)
                }
                Spacer()
            }

            if case .available(let v, let url, let notes) = updateChecker.state {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    HStack {
                        Text("Version \(v) is available")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        NoopButton("Download", systemImage: "arrow.down.circle.fill", kind: .primary) {
                            openURL(url)
                        }
                    }
                    if !notes.isEmpty {
                        ScrollView {
                            Text(notes)
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StrandPalette.surfaceInset,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(StrandPalette.accent.opacity(0.3), lineWidth: 1)
                )
            }

            Text("Checks GitHub for the latest version when you tap — nothing else is sent.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private func attribution(repo: String, note: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(StrandPalette.accent)
                .accessibilityHidden(true)
            Text(repo)
                .font(StrandFont.mono(12))
                .foregroundStyle(StrandPalette.textPrimary)
            Text("· \(note)")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - iOS reality & diagnostics (iOS-only)

    #if os(iOS)
    /// A tappable row (mirroring "How your scores work") that opens the environment-diagnostics sheet.
    private var iosDiagnosticsRow: some View {
        Button { showDiagnostics = true } label: {
            aboutRowLabel(icon: "stethoscope", title: "Diagnostics",
                          subtitle: "Device, iOS build, Data Protection and sideload status — for bug reports.")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Diagnostics")
    }

    /// Calm, honest "what to expect running NOOP on iPhone" callout — sideloading reality, re-sign
    /// cadence, the unlock-after-reboot (#222) note, background-BLE limits, and beta-iOS caveat. Surfaces
    /// the live sideload-cert expiry when we can read it, with a gentle warning under ~3 days.
    private var iphoneExpectations: some View {
        let diag = IOSDiagnostics.capture()
        let expiry = diag.expiryDaysRemaining()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "iphone.gen3")
                    .foregroundStyle(StrandPalette.accent)
                    .accessibilityHidden(true)
                Text("Using NOOP on iPhone")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
            }

            iphoneExpectationLine("This is a sideloaded build — installed outside the App Store. It needs re-signing periodically: roughly every 7 days on a free Apple ID, about a year on a paid developer account.")
            iphoneExpectationLine("After your iPhone reboots, unlock it once. Until you do, iOS keeps NOOP's files locked (Data Protection), so new history can't be written or synced.")
            iphoneExpectationLine("Background Bluetooth has OS limits — iOS may pause NOOP when it's not in the foreground, so keep it open while syncing a fresh strap.")
            iphoneExpectationLine("On a beta version of iOS, things can break that work on the release build.")

            if let days = expiry {
                let warning = days <= 3
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: warning ? "exclamationmark.triangle.fill" : "clock.badge.checkmark")
                        .font(.system(size: 13))
                        .foregroundStyle(warning ? StrandPalette.statusWarning : StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                    Text(expiryMessage(days))
                        .font(StrandFont.footnote)
                        .foregroundStyle(warning ? StrandPalette.statusWarning : StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceInset,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(StrandPalette.hairline, lineWidth: 1)
        )
    }

    private func expiryMessage(_ days: Int) -> String {
        if days < 0 {
            return "This sideloaded build expired \(-days) day\(abs(days) == 1 ? "" : "s") ago — re-sign it to keep it running."
        }
        return "This sideloaded build expires in \(days) day\(days == 1 ? "" : "s") — re-sign to keep it running."
    }

    private func iphoneExpectationLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(StrandPalette.textTertiary)
                .padding(.top, 6)
                .accessibilityHidden(true)
            Text(text)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif

}

// MARK: - iOS diagnostics sheet

#if os(iOS)
/// A read-only environment dump for bug reports: device, iOS+build, Data Protection (#222),
/// background refresh, low-power, sideload + cert expiry — with a one-tap Copy.
private struct DiagnosticsSheet: View {
    let onClose: () -> Void

    /// Captured once at presentation; a snapshot, not a live monitor.
    private let lines: [String] = IOSDiagnostics.capture().summaryLines()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diagnostics").font(StrandFont.title2)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Attach this to a bug report.").font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(20)

            Divider().overlay(StrandPalette.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if lines.isEmpty {
                        Text("No iOS diagnostics available.")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textTertiary)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(StrandFont.mono(12))
                                .foregroundStyle(StrandPalette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StrandPalette.surfaceInset,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(20)
            }

            Divider().overlay(StrandPalette.hairline)

            HStack {
                Spacer()
                Button {
                    // UIPasteboard via the shared cross-platform wrapper.
                    PlatformPasteboard.copy(lines.joined(separator: "\n"))
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(minWidth: 120)
                }
                .buttonStyle(NoopButtonStyle(.primary))
                .disabled(lines.isEmpty)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StrandPalette.surfaceBase)
    }
}
#endif

// MARK: - Steps estimate calibration

/// Small shared formatters for the steps-estimate calibration UI — kept apart from the sheet so the
/// Profile-card summary row and the sheet agree on the confidence wording. Mirrors the Android
/// `StepsCalibrationFormat` object.
enum StepsCalibrationFormat {
    /// A 0–1 confidence as Low / Medium / High — the honest read-out the sheet and the summary row share.
    /// Thirds: < 0.34 Low, < 0.67 Medium, else High. A manual coefficient is confidence 1.0 → "High".
    static func confidenceLabel(_ confidence: Double) -> String {
        switch confidence {
        case ..<0.34: return "Low"
        case ..<0.67: return "Medium"
        default:      return "High"
        }
    }
}

/// One recent day's estimated-vs-phone steps comparison row, for the sheet's accuracy table.
private struct StepsComparisonRow: Identifiable {
    let day: String          // yyyy-MM-dd
    let estimated: Int
    let actual: Int
    var id: String { day }
    /// Signed error of the estimate against the phone count, as a percentage (estimate − actual) / actual.
    var errorPct: Double { actual > 0 ? Double(estimated - actual) / Double(actual) * 100 : 0 }
}

/// WHOOP 4.0 steps-ESTIMATE calibration — honest explainer + current fit + a recent estimated-vs-phone
/// table + a manual coefficient override with a live preview. Presented as a sheet from Settings →
/// Profile → "Steps estimate". Reads the SAME data the engine fits against (the computed `steps_est`
/// series and the phone's `steps`), never recomputing the headline. Mirrors Android `StepsCalibrationScreen`.
// Internal (not file-private) so the Today Steps tile can present the SAME calibration sheet directly
// when it's showing an ESTIMATE for a WHOOP 4.0 user — one shared entry point, no duplicated screen (H6).
struct StepsCalibrationSheet: View {
    let repo: Repository
    let onClose: () -> Void
    @EnvironmentObject var profile: ProfileStore

    /// Recent days that have BOTH an estimate and a real phone step count, newest first — the accuracy table.
    @State private var comparison: [StepsComparisonRow] = []
    /// A representative recent motion volume (median of recent days' motion), used so the manual-coefficient
    /// preview reflects a TYPICAL day. nil until loaded / no recent estimated day with a known motion.
    @State private var sampleMotion: Double?

    /// The draft manual coefficient the slider edits, committed to ProfileStore on release. 0 = auto-fit.
    @State private var draftManual: Double = 0
    @State private var didLoad = false

    /// The coefficient the slider's max anchors to — generous headroom over whatever the auto-fit found so
    /// a manual nudge in either direction is reachable. Floor keeps the slider usable before any fit.
    private var sliderMax: Double {
        max(profile.stepsCalibrationCoefficient, profile.stepsManualCoefficient, 50) * 2
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(StrandPalette.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    explainerCard
                    if didLoad && sampleMotion == nil { noMotionNote }
                    currentFitCard
                    comparisonCard
                    manualAdjustCard
                }
                .padding(20)
            }
            Divider().overlay(StrandPalette.hairline)
            footerBar
        }
        #if os(macOS)
        .frame(width: 560, height: 680)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .noopSheetPresentation(largeFirst: true)
        #endif
        .background(StrandPalette.surfaceBase)
        .task { await loadIfNeeded() }
    }

    // MARK: Header / footer

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STEPS ESTIMATE").font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("Calibrate your steps").font(StrandFont.rounded(26, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("WHOOP 4.0 · motion → steps").font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(20)
    }

    private var footerBar: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Text("Done").frame(minWidth: 120)
            }
            .buttonStyle(NoopButtonStyle(.primary))
            .keyboardShortcut(.defaultAction)
        }
        .padding(NoopMetrics.space4)
    }

    // MARK: Cards

    /// The honest "it's an estimate, not a step counter" framing — reused verbatim from the engine doc.
    private var explainerCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("How this works", systemImage: "figure.walk.motion")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("NOOP estimates your steps from your WHOOP's motion, calibrated to your phone's step count. It's an estimate, not a step counter — a WHOOP 4.0 doesn't transmit steps.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("On the days your phone also counted steps, NOOP learns how much your motion maps to steps, then applies that to the strap-only days. The more matching days it has, the more it trusts the estimate.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Shown when the strap has banked NO motion yet (sampleMotion is nil) — the real reason a fresh
    /// WHOOP 4.0 shows zero steps (#37 bringiton321). Steps are built from the strap's synced motion
    /// history, so without a backfill there is nothing to estimate from — calibration can't help yet.
    private var noMotionNote: some View {
        NoopCard(tint: StrandPalette.metricAmber) {
            VStack(alignment: .leading, spacing: 10) {
                Label("No motion synced yet", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("We're not seeing any motion from your strap yet. Steps are estimated from your WHOOP's banked motion history — so your strap needs to sync that history before NOOP has anything to count.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Open NOOP near your strap and let it catch up (a full history sync can take a while on first run). Once a day or two of motion lands, your step estimate and the calibration below will start to fill in.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The current calibration read-out: coefficient, sample days, and a Low/Medium/High confidence —
    /// or, if nothing's fit yet and no manual value is set, an honest "what we still need" prompt.
    private var currentFitCard: some View {
        NoopCard(tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current calibration").strandOverline()
                if profile.stepsCalibrationCoefficient > 0 || profile.stepsManualCoefficient > 0 {
                    let coeff = profile.stepsManualCoefficient > 0
                        ? profile.stepsManualCoefficient : profile.stepsCalibrationCoefficient
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f", coeff))
                            .font(StrandFont.number(30))
                            .foregroundStyle(StrandPalette.accent)
                        Text("steps per motion unit")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    if profile.stepsManualCoefficient > 0 {
                        statLine("Source", "Manual — you set this by hand")
                    } else {
                        statLine("Fitted from", "\(profile.stepsCalibrationSampleDays) day\(profile.stepsCalibrationSampleDays == 1 ? "" : "s") your phone also counted")
                        statLine("Confidence", "\(StepsCalibrationFormat.confidenceLabel(profile.stepsCalibrationConfidence)) · \(Int((profile.stepsCalibrationConfidence * 100).rounded()))%")
                    }
                } else {
                    Text("Not calibrated yet")
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(StrandPalette.textPrimary)
                    // #589: a concrete countdown instead of a vague "a few days". Headline comes straight
                    // from the engine's needsMoreDays state so the wording matches the Today steps tile.
                    // #693: drive `have` off `profile.stepsCalibrationSampleDays` — the value the engine
                    // persists for the not-yet-calibrated case (IntelligenceEngine.swift sets it to the
                    // usable-day `have`, the SAME source the Today tile reads). `usableMatchedDays` can't be
                    // used here: `loadIfNeeded` early-returns before computing it when coeff == 0 (no fit
                    // yet), so it would always read 0 and the card was stuck on "Need 3 more days".
                    Text(StepsEstimateEngine.CalibrationStatus
                        .needsMoreDays(have: profile.stepsCalibrationSampleDays,
                                       need: StepsEstimateEngine.minCalibrationDays)
                        .headline)
                        .font(StrandFont.bodyNumber)
                        .foregroundStyle(StrandPalette.accent)
                    Text("These are the days where your phone also counted steps, so NOOP can learn how your motion maps to steps. Or set the coefficient manually below.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The accuracy table: recent days that have BOTH an estimate and a phone count, side by side, so the
    /// user can SEE how close the estimate runs. Empty until enough both-have days exist.
    private var comparisonCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Estimated vs your phone").strandOverline()
                if comparison.isEmpty {
                    Text("No days yet where both NOOP and your phone counted steps. Once your phone logs a few days alongside the strap, they'll appear here so you can see how close the estimate is.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Column header.
                    HStack {
                        Text("Day").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Est.").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            .frame(width: 64, alignment: .trailing)
                        Text("Phone").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            .frame(width: 64, alignment: .trailing)
                        Text("Δ").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    ForEach(comparison) { row in
                        HStack {
                            Text(Self.shortDay(row.day))
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Self.grouped(row.estimated))
                                .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                                .frame(width: 64, alignment: .trailing)
                            Text(Self.grouped(row.actual))
                                .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                                .frame(width: 64, alignment: .trailing)
                            Text(String(format: "%+.0f%%", row.errorPct))
                                .font(StrandFont.captionNumber)
                                .foregroundStyle(abs(row.errorPct) <= 15
                                                 ? StrandPalette.metricCyan : StrandPalette.statusWarning)
                                .frame(width: 52, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(Self.shortDay(row.day)): estimated \(row.estimated) steps, phone \(row.actual) steps, \(Int(row.errorPct.rounded())) percent difference")
                    }
                    Text("These days are excluded from the estimate (your phone's real count is shown instead) — they're here only so you can judge the estimate's accuracy.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// Manual override: a slider bound to a draft, committed on release, with a live preview of what a
    /// typical recent day would estimate at the chosen coefficient. 0 returns to auto-fit.
    private var manualAdjustCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Adjust manually").strandOverline()
                Text("Override the automatic fit with your own steps-per-motion value. Useful if your phone has no step history to learn from, or the estimate runs consistently high or low. Set it back to auto by dragging to the far left.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(draftManual > 0 ? String(format: "%.1f", draftManual) : "Auto")
                        .font(StrandFont.number(24))
                        .foregroundStyle(draftManual > 0 ? StrandPalette.accent : StrandPalette.textSecondary)
                    Text(draftManual > 0 ? "steps / motion unit" : "fit from your phone")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                }

                Slider(value: $draftManual, in: 0...sliderMax, step: 0.5) {
                    Text("Manual steps coefficient")
                } minimumValueLabel: {
                    Text("Auto").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                } maximumValueLabel: {
                    Text("High").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                } onEditingChanged: { editing in
                    // Commit on release — snap a tiny drag back to 0 (auto) so "auto" is reachable.
                    if !editing { profile.stepsManualCoefficient = draftManual < 0.5 ? 0 : draftManual }
                }
                .tint(StrandPalette.accent)
                .accessibilityValue(draftManual > 0
                                    ? "\(String(format: "%.1f", draftManual)) steps per motion unit"
                                    : "Automatic")

                // Live preview: a typical recent day re-estimated at the draft coefficient.
                if let motion = sampleMotion {
                    let effective = draftManual > 0 ? draftManual : profile.stepsCalibrationCoefficient
                    if effective > 0 {
                        let preview = Int((motion * effective).rounded())
                        statLine("A typical recent day",
                                 "≈ \(Self.grouped(preview)) steps\(draftManual > 0 ? " at this setting" : " (auto)")")
                    }
                }
                if draftManual > 0 {
                    Text("Takes effect on the next analytics pass (after the next sync).")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    /// A small "label … value" line shared by the fit + preview cards.
    private func statLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Spacer(minLength: 12)
            Text(value).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: Data

    /// Build the comparison table + a typical-day motion, once. The engine stores `steps_est` ONLY for
    /// strap-only days (a phone-covered day uses the phone's real count), so an estimate and a phone count
    /// never co-exist in storage. To still SHOW "how close the estimate is", we reconstruct what the
    /// estimate WOULD have been on recent phone-covered days: read each day's motion volume the same way
    /// the engine does (gravity over [localMidnight, +24h)) and run the public `StepsEstimateEngine` with
    /// the live calibration. This reuses the engine, never invents a number, and needs no extra storage.
    private func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        draftManual = profile.stepsManualCoefficient

        // Effective calibration in force right now: a manual override wins, else the persisted auto-fit.
        let coeff = profile.stepsManualCoefficient > 0
            ? profile.stepsManualCoefficient : profile.stepsCalibrationCoefficient

        // Phone reference steps from Apple Health daily rows (steps > 0 only), newest first.
        let appleRows = await repo.appleDailyRows()
        let phoneDays = appleRows
            .compactMap { row -> (day: String, steps: Int)? in
                guard let s = row.steps, s > 0 else { return nil }
                return (row.day, s)
            }
            .sorted { $0.day > $1.day }

        // Reconstruct the estimate for the most recent phone-covered days, motion-by-motion.
        guard coeff > 0, let store = await repo.storeHandle() else { return }
        let cal = StepsEstimateEngine.Calibration(coefficient: coeff,
                                                  sampleDays: profile.stepsCalibrationSampleDays,
                                                  confidence: profile.stepsCalibrationConfidence,
                                                  manual: profile.stepsManualCoefficient > 0)
        let dayParser = DateFormatter(); dayParser.locale = Locale(identifier: "en_US_POSIX"); dayParser.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        var rows: [StepsComparisonRow] = []
        var motions: [Double] = []
        for entry in phoneDays.prefix(10) {           // scan a few extra to fill 7 after motion gaps
            guard let dayDate = dayParser.date(from: entry.day) else { continue }
            let mid = Int(calendar.startOfDay(for: dayDate).timeIntervalSince1970)
            let grav = (try? await store.gravitySamples(deviceId: repo.deviceId, from: mid,
                                                        to: mid + 86_400 - 1, limit: 200_000)) ?? []
            let motion = StepsEstimateEngine.dayMotionIntensity(grav)
            guard motion > 0, let est = StepsEstimateEngine.estimate(motion: motion, calibration: cal) else { continue }
            motions.append(motion)
            rows.append(StepsComparisonRow(day: entry.day, estimated: est, actual: entry.steps))
            if rows.count >= 7 { break }
        }
        comparison = rows
        // #693: the "Need N more days…" countdown is now driven by `profile.stepsCalibrationSampleDays`
        // (the engine-persisted usable-day count, read directly in the card) — NOT a local match count
        // computed here. This scan reaches here ONLY when coeff > 0 (already calibrated), so a local count
        // would never reflect the not-yet-calibrated state the countdown describes. The rows still feed the
        // accuracy table (`comparison`) above.

        // Typical recent day's motion for the live preview = median of the motions we just measured.
        if !motions.isEmpty {
            let s = motions.sorted()
            sampleMotion = s[s.count / 2]
        }
    }

    // MARK: Formatting

    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
    /// "yyyy-MM-dd" → "EEE d MMM" for the table's day column.
    private static func shortDay(_ key: String) -> String {
        let inF = DateFormatter(); inF.locale = Locale(identifier: "en_US_POSIX"); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: key) else { return key }
        let outF = DateFormatter(); outF.dateFormat = "EEE d MMM"
        return outF.string(from: d)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Settings") {
    let model = AppModel()
    model.live.bonded = true
    model.live.connected = true
    model.live.batteryPct = 64
    return SettingsView()
        .environmentObject(model)
        .environmentObject(model.live)
        .environmentObject(model.profile)
        // iPhone-width (402pt) so the narrow Backup row stays in the preview's blast radius —
        // at 720 the three-up button row had slack and the truncation regression slipped through. (#188)
        .frame(width: 402, height: 900)
        .background(StrandPalette.surfaceBase)
        .preferredColorScheme(.dark)
}
#endif
