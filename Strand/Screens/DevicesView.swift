import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Devices
//
// Pair and manage the bands NOOP reads from. WHOOP-FIRST: the WHOOP is the primary, fully-supported
// device; generic heart-rate straps (Polar / Wahoo / Coospo / Garmin HRM …) are an early, in-development
// addition. The screen is a thin UI over `DeviceRegistry` (the Phase 1A/1B data layer): every mutation
// goes through a registry op, and the `SourceCoordinator` (already wired in AppModel) reacts to the
// active-device change — so this view never touches BLEManager or the WHOOP path directly.
struct DevicesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveState

    var body: some View {
        ScreenScaffold(title: "Devices",
                       subtitle: "Pair and manage the bands NOOP reads from.") {
            if let registry = model.deviceRegistry {
                DevicesContent(registry: registry)
            } else {
                // The registry is built once the on-device store opens (a beat after launch). Show a
                // calm pending note rather than an empty screen in that brief window.
                DataPendingNote(
                    title: "Getting your devices ready",
                    message: "NOOP is opening your on-device data. Your paired bands will appear here in a moment.",
                    symbol: "badge.plus.radiowaves.right")
            }
        }
    }
}

// MARK: - Content (registry resolved)

/// The screen body once `DeviceRegistry` exists. Split out so it can observe the registry's
/// `@Published devices` / `activeDeviceId` directly — the parent only observes `model.deviceRegistry`
/// becoming non-nil.
private struct DevicesContent: View {
    @ObservedObject var registry: DeviceRegistry
    @EnvironmentObject var live: LiveState

    // Sheets / alerts
    @State private var showAddWizard = false
    @State private var switchTarget: PairedDevice?
    @State private var renameTarget: PairedDevice?
    @State private var renameDraft = ""
    @State private var removeTarget: PairedDevice?
    @State private var deleteDataTarget: PairedDevice?
    /// After removing the ACTIVE device with other devices still paired, prompt to pick a new active one.
    @State private var pickNewActive = false

    private var activeDevices: [PairedDevice] { registry.devices.filter { $0.status != .archived } }
    private var removedDevices: [PairedDevice] { registry.devices.filter { $0.status == .archived } }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            ForEach(activeDevices) { device in
                DeviceCard(
                    device: device,
                    isActive: device.status == .active,
                    isLiveConnected: device.status == .active && live.connected,
                    onMakeActive: { switchTarget = device },
                    onRename: { renameDraft = device.nickname ?? device.displayName; renameTarget = device },
                    onRemove: { removeTarget = device })
            }

            addButton

            if !removedDevices.isEmpty { removedSection }

            whoopFirstFooter
        }
        // Add a heart-rate strap
        .sheet(isPresented: $showAddWizard) {
            AddDeviceSheet(registry: registry, live: live) { showAddWizard = false }
        }
        // Switch confirm
        .alert("Make this your active strap?",
               isPresented: Binding(get: { switchTarget != nil },
                                    set: { if !$0 { switchTarget = nil } }),
               presenting: switchTarget) { device in
            Button("Cancel", role: .cancel) { switchTarget = nil }
            Button("Make active") {
                registry.setActive(device.id)
                switchTarget = nil
            }
        } message: { device in
            Text("Make \(device.displayName) your active strap? From now on it provides your live data. \(currentActiveName)'s history stays exactly as it is — only new days come from \(device.displayName).")
        }
        // Rename
        .alert("Rename device",
               isPresented: Binding(get: { renameTarget != nil },
                                    set: { if !$0 { renameTarget = nil } }),
               presenting: renameTarget) { device in
            TextField("Name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                registry.rename(device.id, to: renameDraft)
                renameTarget = nil
            }
        } message: { device in
            Text("Give \(device.brand) \(device.model) a name you'll recognise.")
        }
        // Remove confirm
        .alert("Remove this device?",
               isPresented: Binding(get: { removeTarget != nil },
                                    set: { if !$0 { removeTarget = nil } }),
               presenting: removeTarget) { device in
            Button("Cancel", role: .cancel) { removeTarget = nil }
            Button("Remove", role: .destructive) { confirmRemove(device) }
        } message: { device in
            Text("Remove \(device.displayName)? NOOP will stop connecting to it. Its recorded data is kept and you can re-add it any time.")
        }
        // Second, strongly-worded delete-data confirm (reached from the Remove card's secondary control)
        .alert("Delete all of this device's data?",
               isPresented: Binding(get: { deleteDataTarget != nil },
                                    set: { if !$0 { deleteDataTarget = nil } }),
               presenting: deleteDataTarget) { device in
            Button("Cancel", role: .cancel) { deleteDataTarget = nil }
            Button("Delete data", role: .destructive) {
                registry.deleteDeviceData(device.id)
                deleteDataTarget = nil
            }
        } message: { device in
            Text("This permanently deletes all data recorded from \(device.displayName). This can't be undone.")
        }
        // After removing the active device, offer to pick a new active one (if any remain).
        .confirmationDialog("Pick a new active strap",
                            isPresented: $pickNewActive,
                            titleVisibility: .visible) {
            ForEach(activeDevices) { device in
                Button(device.displayName) { registry.setActive(device.id) }
            }
            Button("Leave none active", role: .cancel) { }
        } message: {
            Text("You removed your active strap. Choose which paired band provides your live data, or leave none active and pair one later.")
        }
    }

    // MARK: Pieces

    private var addButton: some View {
        Button {
            showAddWizard = true
        } label: {
            Label("Add a device", systemImage: "plus")
                .font(StrandFont.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(StrandPalette.accent)
        .accessibilityLabel("Add a device")
        .padding(.top, 4)
    }

    private var removedSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            Text("Removed").strandOverline()
                .padding(.top, 8)
            ForEach(removedDevices) { device in
                DeviceCard(
                    device: device,
                    isActive: false,
                    isLiveConnected: false,
                    dimmed: true,
                    onMakeActive: { switchTarget = device },
                    onRename: { renameDraft = device.nickname ?? device.displayName; renameTarget = device },
                    onRemove: nil,
                    onReAdd: { registry.setActive(device.id) },
                    onDeleteData: { deleteDataTarget = device })
            }
        }
    }

    private var whoopFirstFooter: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
            Text("WHOOP is NOOP's primary, fully-supported band. Other heart-rate straps are an early, in-development addition — they stream live heart rate and HRV, but not WHOOP's deeper sleep and recovery data.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: Logic

    private var currentActiveName: String {
        registry.devices.first(where: { $0.status == .active })?.displayName ?? "Your current strap"
    }

    /// Archive the device, then — if it was the active one and other non-archived devices remain —
    /// prompt for a new active device. The active row is demoted to `.paired` by the registry's reload,
    /// so the dialog's choices come from the still-paired devices.
    private func confirmRemove(_ device: PairedDevice) {
        let wasActive = device.status == .active
        registry.archive(device.id)
        removeTarget = nil
        if wasActive {
            // Other paired devices left → ask which becomes active; otherwise no active device remains.
            if !activeDevices.isEmpty {
                pickNewActive = true
            }
        }
    }
}

// MARK: - Device card

/// One paired device as a card: name, brand/model, capabilities line, a state pill, last-seen, and a
/// per-device actions menu. The active device is tinted (gold) and carries an "Active" pill.
private struct DeviceCard: View {
    let device: PairedDevice
    let isActive: Bool
    let isLiveConnected: Bool
    var dimmed: Bool = false
    var onMakeActive: () -> Void
    var onRename: () -> Void
    var onRemove: (() -> Void)?
    /// Removed-section affordances (re-add as active / delete its data).
    var onReAdd: (() -> Void)? = nil
    var onDeleteData: (() -> Void)? = nil

    var body: some View {
        StrandCard(padding: 18, tint: isActive ? StrandPalette.accent : nil) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(StrandFont.title2)
                        .foregroundStyle(isActive ? StrandPalette.accent : StrandPalette.textSecondary)
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.displayName)
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("\(device.brand) · \(device.model)")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer()
                    statePill
                }

                if !capabilityLine.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.path.ecg")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .accessibilityHidden(true)
                        Text(capabilityLine)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }

                HStack {
                    Text(lastSeenLine)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                    actionsMenu
                }
            }
        }
        .opacity(dimmed ? 0.6 : 1)
        .accessibilityElement(children: .contain)
    }

    private var statePill: some View {
        Group {
            if device.status == .archived {
                StatePill("Removed", tone: .neutral, showsDot: false)
            } else if isActive {
                StatePill(isLiveConnected ? "Active · Live" : "Active",
                          tone: .positive, pulsing: isLiveConnected)
            } else {
                StatePill("Paired", tone: .neutral)
            }
        }
    }

    private var actionsMenu: some View {
        Menu {
            if device.status == .archived {
                if let onReAdd {
                    Button { onReAdd() } label: { Label("Make active", systemImage: "bolt.fill") }
                }
                Button { onRename() } label: { Label("Rename", systemImage: "pencil") }
                if let onDeleteData {
                    Divider()
                    Button(role: .destructive) { onDeleteData() } label: {
                        Label("Delete this device's data…", systemImage: "trash")
                    }
                }
            } else {
                if !isActive {
                    Button { onMakeActive() } label: { Label("Make active", systemImage: "bolt.fill") }
                }
                Button { onRename() } label: { Label("Rename", systemImage: "pencil") }
                if let onRemove {
                    Divider()
                    Button(role: .destructive) { onRemove() } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Device actions for \(device.displayName)")
    }

    /// SF Symbol for the device: WHOOP keeps the band glyph; generic straps read as a heart-rate strap.
    private var icon: String {
        SourceCoordinator.isWhoop(device) ? "applewatch.side.right" : "heart.circle"
    }

    /// "Heart rate · HRV · …" from the device's capabilities, in a stable, readable order.
    private var capabilityLine: String {
        let order: [(Metric, String)] = [
            (.hr, "Heart rate"), (.hrv, "HRV"), (.spo2, "Blood oxygen"),
            (.skinTemp, "Skin temp"), (.steps, "Steps"), (.sleep, "Sleep"),
            (.strainLoad, "Strain"),
        ]
        return order.filter { device.capabilities.contains($0.0) }.map(\.1).joined(separator: " · ")
    }

    private var lastSeenLine: String {
        if device.status == .archived { return "Removed · data kept" }
        if isLiveConnected { return "Connected now" }
        return "Last seen \(relativeAgo(TimeInterval(device.lastSeenAt)))"
    }
}

// MARK: - Add device sheet (scan + name + add)

/// "Add a heart-rate strap" — runs its OWN `StandardHRSource` purely for discovery (it never connects
/// here; the SourceCoordinator owns connection once the strap becomes active). Lists nearby straps live;
/// tapping one reveals a name field and an Add button. On Add it registers a `.paired` device, then
/// offers to make it active. Renders its searching/empty state cleanly with no hardware present.
private struct AddDeviceSheet: View {
    @ObservedObject var registry: DeviceRegistry
    let live: LiveState
    let onClose: () -> Void

    /// A discovery-only source for this sheet. It never persists (no-op persist closure) and is never
    /// asked to `connect` — we only read its `@Published discovered` list while scanning.
    @StateObject private var scanner: StandardHRSource

    @State private var selected: StandardHRSource.DiscoveredStrap?
    @State private var nameDraft = ""
    /// After adding, ask whether to make the new strap active.
    @State private var justAdded: PairedDevice?

    init(registry: DeviceRegistry, live: LiveState, onClose: @escaping () -> Void) {
        self.registry = registry
        self.live = live
        self.onClose = onClose
        // Discovery only — a no-op persist closure and a throwaway deviceId; this instance never writes.
        _scanner = StateObject(wrappedValue: StandardHRSource(
            live: live, deviceId: "scan-preview", persist: { _ in }))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(StrandPalette.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                    if let selected {
                        namingStep(for: selected)
                    } else {
                        scanStep
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StrandPalette.surfaceBase)
        .onAppear { scanner.scan() }
        .onDisappear { scanner.stopScan() }
        // After adding, offer to make the new strap active.
        .alert("Make this your active strap?",
               isPresented: Binding(get: { justAdded != nil },
                                    set: { if !$0 { justAdded = nil } }),
               presenting: justAdded) { device in
            Button("Not now", role: .cancel) { justAdded = nil; onClose() }
            Button("Make active") {
                registry.setActive(device.id)
                justAdded = nil
                onClose()
            }
        } message: { device in
            Text("Make \(device.displayName) your active strap now? It will provide your live heart rate. You can change this any time.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add a heart-rate strap").font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Polar, Wahoo, Coospo, Garmin HRM and other standard BLE straps.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer()
            Button(action: { scanner.stopScan(); onClose() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(20)
    }

    // Step 1 — live scan list / empty state.
    @ViewBuilder private var scanStep: some View {
        HStack(spacing: 8) {
            StatePill(scanner.scanning ? "Searching…" : "Idle",
                      tone: scanner.scanning ? .accent : .neutral,
                      pulsing: scanner.scanning)
            Spacer()
            Button("Rescan") { scanner.scan() }
                .font(StrandFont.subhead)
                .buttonStyle(.plain)
                .foregroundStyle(StrandPalette.accent)
        }

        if scanner.discovered.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView()
                    .tint(StrandPalette.accent)
                Text("Searching for nearby straps…")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Make sure your strap is awake and not connected to another app.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .frostedCardSurface(cornerRadius: 14)
        } else {
            ForEach(scanner.discovered.sorted(by: { $0.rssi > $1.rssi })) { strap in
                Button {
                    nameDraft = strap.name
                    selected = strap
                } label: {
                    HStack(spacing: 12) {
                        SignalBars(rssi: strap.rssi)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(strap.name)
                                .font(StrandFont.body)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text(brandGuess(from: strap.name))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frostedCardSurface(cornerRadius: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(strap.name), signal \(SignalBars.level(for: strap.rssi)) of 4")
            }
        }
    }

    // Step 2 — name the chosen strap + Add.
    @ViewBuilder private func namingStep(for strap: StandardHRSource.DiscoveredStrap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                SignalBars(rssi: strap.rssi)
                VStack(alignment: .leading, spacing: 2) {
                    Text(strap.name).font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(brandGuess(from: strap.name)).font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frostedCardSurface(cornerRadius: 12)

            Text("Name").strandOverline()
            TextField("Strap name", text: $nameDraft)
                .textFieldStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(12)
                .background(StrandPalette.surfaceInset,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Strap name")

            HStack(spacing: 12) {
                Button("Back") { selected = nil }
                    .buttonStyle(.bordered)
                    .tint(StrandPalette.textSecondary)
                Spacer()
                Button("Add") { add(strap) }
                    .buttonStyle(.borderedProminent)
                    .tint(StrandPalette.accent)
                    .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
    }

    /// Register the chosen strap as a `.paired` device, then ask whether to make it active.
    private func add(_ strap: StandardHRSource.DiscoveredStrap) {
        scanner.stopScan()
        let now = Int(Date().timeIntervalSince1970)
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = PairedDevice(
            id: strap.id.uuidString,
            brand: brandGuess(from: strap.name),
            model: name.isEmpty ? strap.name : name,
            nickname: nil,
            sourceKind: .liveBLE,
            capabilities: [.hr, .hrv],
            status: .paired,
            addedAt: now, lastSeenAt: now)
        registry.add(device)
        justAdded = device
    }

    /// Best-effort brand from the advertised name. Falls back to a neutral label for unknown straps.
    private func brandGuess(from name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("polar") { return "Polar" }
        if lower.contains("wahoo") || lower.contains("tickr") { return "Wahoo" }
        if lower.contains("coospo") { return "Coospo" }
        if lower.contains("garmin") || lower.contains("hrm") { return "Garmin" }
        if lower.contains("scosche") || lower.contains("rhythm") { return "Scosche" }
        if lower.contains("magene") { return "Magene" }
        return "Heart-rate strap"
    }
}

// MARK: - Signal indicator

/// A four-bar Wi-Fi-style signal indicator derived from RSSI. RSSI is negative dBm: closer to 0 is
/// stronger. Buckets are coarse on purpose — a precise dBm readout would be noise to the user.
private struct SignalBars: View {
    let rssi: Int

    static func level(for rssi: Int) -> Int {
        switch rssi {
        case (-55)...:    return 4   // very strong
        case (-67)...:    return 3
        case (-80)...:    return 2
        case (-90)...:    return 1
        default:          return 0
        }
    }

    var body: some View {
        let level = Self.level(for: rssi)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(i < level ? StrandPalette.accent : StrandPalette.hairlineStrong)
                    .frame(width: 3, height: 6 + CGFloat(i) * 3)
            }
        }
        .frame(width: 22, height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Devices") {
    let model = AppModel()
    return DevicesView()
        .environmentObject(model)
        .environmentObject(model.live)
        .frame(width: 480, height: 760)
        .background(StrandPalette.surfaceBase)
        .preferredColorScheme(.dark)
}
#endif
