package com.noop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.ble.StandardHrSource
import com.noop.ble.WhoopBleClient
import com.noop.ble.WhoopModel
import com.noop.data.DeviceStatus
import com.noop.data.PairedDeviceRow
import com.noop.data.SourceKind
import kotlinx.coroutines.launch

// MARK: - Add a device — guided, branching wizard (MW-4)
//
// Different bands pair COMPLETELY differently, so this wizard asks the device TYPE first, then gives
// type-specific prep guidance and runs the RIGHT scan/connect for that type:
//
//   • WHOOP 4.0 / WHOOP 5.0 (MG)  → the WHOOP present-scan ([AppViewModel.presentWhoopScan]) targeted at
//     the chosen family. Lists nearby straps from [AppViewModel.discoveredWhoops] (a present-only mode
//     that never auto-connects).
//   • Heart-rate strap (Polar / Wahoo / Coospo / Garmin HRM / Amazfit Helio broadcast) → its OWN isolated
//     [StandardHrSource] scanning the standard 0x180D HR service. Lists from its `discovered` flow.
//
// Registration goes through [AppViewModel.registerDevice] → DeviceRegistry; the SourceCoordinator reacts
// to the active-device change and connects (pinning the WHOOP / starting the strap source). The wizard
// never touches the BLE client directly — only the AppViewModel pass-throughs. WHOOP-FIRST: WHOOP is the
// primary band; the type list shows it first and a footer reiterates it. Renders cleanly with nothing
// nearby (the type picker, every prep step, and the searching/empty pick state all need no hardware).
// Faithful Kotlin twin of Strand/Screens/AddDeviceWizard.swift. US English throughout.

/** What the user is adding. Drives the prep copy AND which scan/register path runs. */
private enum class DeviceType {
    Whoop5MG, Whoop4, HrStrap;

    val isWhoop: Boolean get() = this == Whoop4 || this == Whoop5MG
    val whoopModel: WhoopModel?
        get() = when (this) {
            Whoop4 -> WhoopModel.WHOOP4
            Whoop5MG -> WhoopModel.WHOOP5_MG
            HrStrap -> null
        }

    val title: String
        get() = when (this) {
            Whoop5MG -> "WHOOP 5.0 / MG"
            Whoop4 -> "WHOOP 4.0"
            HrStrap -> "Heart-rate strap"
        }
}

private enum class WizardStep { Type, Prep, Pick, Confirm }

@Composable
fun AddDeviceWizard(viewModel: AppViewModel, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()

    var step by remember { mutableStateOf(WizardStep.Type) }
    var type by remember { mutableStateOf<DeviceType?>(null) }

    // The chosen strap, in whichever shape its path produces.
    var pickedWhoop by remember { mutableStateOf<WhoopBleClient.DiscoveredWhoop?>(null) }
    var pickedStrap by remember { mutableStateOf<StandardHrSource.DiscoveredStrap?>(null) }

    var nameDraft by remember { mutableStateOf("") }
    var askMakeActive by remember { mutableStateOf(false) }

    // Discovery-only HR source for the strap path. Never persists, never connects — we only read its
    // `discovered` / `scanning` StateFlows while scanning. Created once per wizard.
    val hrScanner = remember { viewModel.makeStrapScanner() }

    fun startScan(t: DeviceType) {
        if (t.isWhoop) viewModel.presentWhoopScan(t.whoopModel ?: WhoopModel.WHOOP4)
        else hrScanner.scan()
    }

    fun stopAllScans() {
        viewModel.stopWhoopScan()
        hrScanner.stopScan()
    }

    // Belt-and-braces: stop whichever scan is live whenever the wizard leaves composition.
    DisposableEffect(Unit) { onDispose { stopAllScans() } }

    fun goBack() {
        when (step) {
            WizardStep.Type -> Unit
            WizardStep.Prep -> step = WizardStep.Type
            WizardStep.Pick -> { stopAllScans(); step = WizardStep.Prep }
            WizardStep.Confirm -> {
                // Re-enter the pick step and restart its scan so the user can choose a different device.
                type?.let { startScan(it) }
                pickedWhoop = null; pickedStrap = null
                step = WizardStep.Pick
            }
        }
    }

    val confirmAdvertisedName = run {
        pickedWhoop?.let { return@run it.name?.takeIf { n -> n.isNotBlank() } ?: (type?.title ?: "Device") }
        pickedStrap?.let { return@run it.name }
        type?.title ?: "Device"
    }
    val confirmName = nameDraft.trim().ifEmpty { confirmAdvertisedName }
    val confirmBrand = when {
        type?.isWhoop == true -> "WHOOP"
        pickedStrap != null -> brandGuess(pickedStrap!!.name)
        else -> "Heart-rate strap"
    }
    val confirmRssi = pickedWhoop?.rssi ?: pickedStrap?.rssi ?: -70

    fun finishAdd(makeActive: Boolean) {
        stopAllScans()
        val now = System.currentTimeMillis() / 1000
        val pw = pickedWhoop
        val ps = pickedStrap
        val device: PairedDeviceRow? = when {
            pw != null && type?.whoopModel != null -> {
                // WHOOP: full capability set; id namespaced by address; model "4.0" / "5.0 MG".
                val wm = type!!.whoopModel!!
                val modelLabel = if (wm == WhoopModel.WHOOP4) "4.0" else "5.0 MG"
                PairedDeviceRow(
                    id = "whoop-${pw.address}",
                    brand = "WHOOP",
                    model = modelLabel,
                    nickname = confirmName,
                    peripheralId = pw.address,
                    sourceKind = SourceKind.liveBLE.name,
                    capabilities = "hr,hrv,spo2,skinTemp,sleep,strainLoad",
                    status = DeviceStatus.paired.name,
                    addedAt = now,
                    lastSeenAt = now,
                )
            }
            ps != null -> {
                // Generic HR strap: HR + HRV only.
                PairedDeviceRow(
                    id = "strap-${ps.address}",
                    brand = brandGuess(ps.name),
                    model = ps.name,
                    nickname = if (confirmName == ps.name) null else confirmName,
                    peripheralId = ps.address,
                    sourceKind = SourceKind.liveBLE.name,
                    capabilities = "hr,hrv",
                    status = DeviceStatus.paired.name,
                    addedAt = now,
                    lastSeenAt = now,
                )
            }
            else -> null
        }
        if (device == null) { onClose(); return }
        scope.launch { viewModel.registerDevice(device, makeActive = makeActive) }
        onClose()
    }

    AlertDialog(
        onDismissRequest = { stopAllScans(); onClose() },
        containerColor = Palette.surfaceOverlay,
        title = {
            Row(verticalAlignment = Alignment.Top) {
                if (step != WizardStep.Type) {
                    IconButton(onClick = { goBack() }, modifier = Modifier.size(28.dp)) {
                        Icon(
                            Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                            contentDescription = "Back",
                            tint = Palette.textSecondary,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                    Spacer(Modifier.width(6.dp))
                }
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(headerTitle(step, type), style = NoopType.title2, color = Palette.textPrimary)
                    headerSubtitle(step)?.let {
                        Text(it, style = NoopType.caption, color = Palette.textTertiary)
                    }
                }
                IconButton(onClick = { stopAllScans(); onClose() }, modifier = Modifier.size(28.dp)) {
                    Icon(Icons.Filled.Close, contentDescription = "Close", tint = Palette.textTertiary, modifier = Modifier.size(20.dp))
                }
            }
        },
        text = {
            when (step) {
                WizardStep.Type -> TypeStep(onPick = { t -> type = t; nameDraft = ""; step = WizardStep.Prep })
                WizardStep.Prep -> type?.let { t ->
                    PrepStep(t, onScan = { startScan(t); step = WizardStep.Pick })
                }
                WizardStep.Pick -> type?.let { t ->
                    if (t.isWhoop) {
                        WhoopPickStep(
                            viewModel = viewModel,
                            onSelect = { strap ->
                                pickedWhoop = strap; pickedStrap = null
                                nameDraft = strap.name?.takeIf { it.isNotBlank() } ?: t.title
                                viewModel.stopWhoopScan()
                                step = WizardStep.Confirm
                            },
                            onRescan = { viewModel.presentWhoopScan(t.whoopModel ?: WhoopModel.WHOOP4) },
                        )
                    } else {
                        HrPickStep(
                            scanner = hrScanner,
                            onSelect = { strap ->
                                pickedStrap = strap; pickedWhoop = null
                                nameDraft = strap.name
                                hrScanner.stopScan()
                                step = WizardStep.Confirm
                            },
                            onRescan = { hrScanner.scan() },
                        )
                    }
                }
                WizardStep.Confirm -> ConfirmStep(
                    advertisedName = confirmAdvertisedName,
                    brand = confirmBrand,
                    rssi = confirmRssi,
                    name = nameDraft,
                    onName = { nameDraft = it },
                    onAdd = { askMakeActive = true },
                )
            }
        },
        confirmButton = {},
        dismissButton = {},
    )

    // After adding, offer to make the new device active.
    if (askMakeActive) {
        AlertDialog(
            onDismissRequest = { askMakeActive = false; finishAdd(makeActive = false) },
            containerColor = Palette.surfaceOverlay,
            title = { Text("Make this your active device?", style = NoopType.title2, color = Palette.textPrimary) },
            text = {
                Text(
                    "Make $confirmName your active device now? It will provide your live data. You can change " +
                        "this any time.",
                    style = NoopType.subhead,
                    color = Palette.textSecondary,
                )
            },
            confirmButton = {
                TextButton(onClick = { askMakeActive = false; finishAdd(makeActive = true) }) {
                    Text("Make active", style = NoopType.body, color = Palette.accent)
                }
            },
            dismissButton = {
                TextButton(onClick = { askMakeActive = false; finishAdd(makeActive = false) }) {
                    Text("Not now", style = NoopType.body, color = Palette.textSecondary)
                }
            },
        )
    }
}

private fun headerTitle(step: WizardStep, type: DeviceType?): String = when (step) {
    WizardStep.Type -> "Add a device"
    WizardStep.Prep -> type?.title ?: "Add a device"
    WizardStep.Pick -> "Pick your device"
    WizardStep.Confirm -> "Name & confirm"
}

private fun headerSubtitle(step: WizardStep): String? = when (step) {
    WizardStep.Type -> "What are you adding?"
    WizardStep.Prep -> "Get it ready, then scan."
    WizardStep.Pick -> "Tap the one that's yours."
    WizardStep.Confirm -> null
}

// MARK: - Step 1 — type picker

@Composable
private fun TypeStep(onPick: (DeviceType) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        TypeRow(Icons.Filled.Watch, DeviceType.Whoop5MG.title, "Newer WHOOP band — experimental in NOOP") {
            onPick(DeviceType.Whoop5MG)
        }
        TypeRow(Icons.Filled.Watch, DeviceType.Whoop4.title, "NOOP's primary, fully-supported band") {
            onPick(DeviceType.Whoop4)
        }
        TypeRow(Icons.Filled.FavoriteBorder, DeviceType.HrStrap.title, "Polar, Wahoo, Coospo, Garmin HRM, Amazfit Helio broadcast") {
            onPick(DeviceType.HrStrap)
        }

        Overline("Coming soon", modifier = Modifier.padding(top = 8.dp))
        ComingSoonRow(Icons.Filled.Watch, "Garmin watch")
        ComingSoonRow(Icons.Filled.GraphicEq, "Amazfit / Zepp")
        ComingSoonRow(Icons.Filled.FileDownload, "Import from Oura or Fitbit")

        WhoopFirstNote()
    }
}

@Composable
private fun TypeRow(icon: ImageVector, title: String, subtitle: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .frostedCardSurface(cornerRadius = 14.dp)
            .clickable(onClick = onClick)
            .semantics { contentDescription = "$title. $subtitle" }
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = Palette.accent, modifier = Modifier.size(28.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = NoopType.headline, color = Palette.textPrimary)
            Text(subtitle, style = NoopType.caption, color = Palette.textTertiary)
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = Palette.textTertiary,
            modifier = Modifier.size(20.dp),
        )
    }
}

@Composable
private fun ComingSoonRow(icon: ImageVector, title: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .frostedCardSurface(cornerRadius = 14.dp)
            .padding(16.dp)
            .semantics { contentDescription = "$title, coming soon" },
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = Palette.textTertiary, modifier = Modifier.size(28.dp))
        Text(title, style = NoopType.headline, color = Palette.textTertiary, modifier = Modifier.weight(1f))
        StatePill("Soon", tone = StrandTone.Neutral, showsDot = false)
    }
}

@Composable
private fun WhoopFirstNote() {
    Row(
        modifier = Modifier.padding(top = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(Icons.Filled.FavoriteBorder, contentDescription = null, tint = Palette.textTertiary, modifier = Modifier.size(16.dp))
        Text(
            "WHOOP is NOOP's primary, fully-supported band. Other heart-rate straps stream live heart rate " +
                "and HRV, but not WHOOP's deeper sleep and recovery data.",
            style = NoopType.footnote,
            color = Palette.textTertiary,
        )
    }
}

// MARK: - Step 2 — type-specific prep + guidance

@Composable
private fun PrepStep(type: DeviceType, onScan: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(
                if (type.isWhoop) Icons.Filled.Watch else Icons.Filled.FavoriteBorder,
                contentDescription = null,
                tint = Palette.accent,
                modifier = Modifier.size(28.dp),
            )
            Text(type.title, style = NoopType.title2, color = Palette.textPrimary)
        }

        if (type == DeviceType.Whoop5MG) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(Palette.statusWarning.copy(alpha = 0.10f))
                    .padding(12.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Icon(Icons.Filled.Science, contentDescription = null, tint = Palette.statusWarning, modifier = Modifier.size(18.dp))
                Text(
                    "WHOOP 5.0 / MG support is newer and still experimental in NOOP.",
                    style = NoopType.footnote,
                    color = Palette.statusWarning,
                )
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .frostedCardSurface(cornerRadius = 14.dp)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            prepInstructions(type).forEach { line ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                    Text("•", style = NoopType.body, color = Palette.accent)
                    Text(line, style = NoopType.body, color = Palette.textSecondary)
                }
            }
        }

        TextButton(
            onClick = onScan,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(Palette.accent)
                .semantics { contentDescription = "Scan for ${type.title}" },
        ) {
            Text("Scan", style = NoopType.headline, color = Palette.goldDeepText)
        }
    }
}

/** Type-specific "get it ready" guidance — the point of the branching wizard. US English copy. */
private fun prepInstructions(type: DeviceType): List<String> = when (type) {
    DeviceType.Whoop4 -> listOf(
        "Put your WHOOP 4.0 on your wrist and make sure it's awake.",
        "Make sure it's NOT connected to the official WHOOP app right now.",
        "NOOP will look for it nearby.",
    )
    DeviceType.Whoop5MG -> listOf(
        "WHOOP 5.0 / MG bonds to one device at a time — unpair it from the official WHOOP app first.",
        "Put the band into pairing mode, on your wrist and awake.",
        "NOOP will look for it nearby.",
    )
    DeviceType.HrStrap -> listOf(
        "Wake your strap — put it on, or dampen the contacts.",
        "Make sure it isn't connected to another app (a bike computer, the brand's own app…).",
        "NOOP will look for it nearby.",
    )
}

// MARK: - Step 3 — pick from the live scan

@Composable
private fun WhoopPickStep(
    viewModel: AppViewModel,
    onSelect: (WhoopBleClient.DiscoveredWhoop) -> Unit,
    onRescan: () -> Unit,
) {
    val found by viewModel.discoveredWhoops.collectAsStateWithLifecycle()
    PickList(searching = true, isEmpty = found.isEmpty(), onRescan = onRescan) {
        found.sortedByDescending { it.rssi }.forEach { strap ->
            DiscoveredRow(
                name = strap.name?.takeIf { it.isNotBlank() } ?: "WHOOP",
                subtitle = "WHOOP",
                rssi = strap.rssi,
                onTap = { onSelect(strap) },
            )
        }
    }
}

@Composable
private fun HrPickStep(
    scanner: StandardHrSource,
    onSelect: (StandardHrSource.DiscoveredStrap) -> Unit,
    onRescan: () -> Unit,
) {
    val discovered by scanner.discovered.collectAsStateWithLifecycle()
    val scanning by scanner.scanning.collectAsStateWithLifecycle()
    PickList(searching = scanning, isEmpty = discovered.isEmpty(), onRescan = onRescan) {
        discovered.sortedByDescending { it.rssi }.forEach { strap ->
            DiscoveredRow(
                name = strap.name,
                subtitle = brandGuess(strap.name),
                rssi = strap.rssi,
                onTap = { onSelect(strap) },
            )
        }
    }
}

/** Shared pick-step shell: a searching status bar + a Rescan button, then either the searching card
 *  (while [isEmpty]) or the caller's discovered [rows]. Mirrors the iOS pick step's ScanStatusBar +
 *  SearchingCard. */
@Composable
private fun PickList(
    searching: Boolean,
    isEmpty: Boolean,
    onRescan: () -> Unit,
    rows: @Composable () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(Metrics.gap)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            StatePill(
                if (searching) "Searching…" else "Idle",
                tone = if (searching) StrandTone.Accent else StrandTone.Neutral,
                pulsing = searching,
            )
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onRescan) {
                Text("Rescan", style = NoopType.subhead, color = Palette.accent)
            }
        }
        if (isEmpty) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .frostedCardSurface(cornerRadius = 14.dp)
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                CircularProgressIndicator(color = Palette.accent, modifier = Modifier.size(22.dp))
                Text("Searching…", style = NoopType.body, color = Palette.textPrimary)
                Text(
                    "Make sure it's awake and not connected elsewhere.",
                    style = NoopType.subhead,
                    color = Palette.textSecondary,
                )
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(Metrics.gap)) { rows() }
        }
    }
}

@Composable
private fun DiscoveredRow(name: String, subtitle: String, rssi: Int, onTap: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .frostedCardSurface(cornerRadius = 12.dp)
            .clickable(onClick = onTap)
            .semantics { contentDescription = "$name, signal ${SignalBars.level(rssi)} of 4" }
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SignalBars(rssi)
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(name, style = NoopType.body, color = Palette.textPrimary)
            Text(subtitle, style = NoopType.caption, color = Palette.textTertiary)
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = Palette.textTertiary,
            modifier = Modifier.size(18.dp),
        )
    }
}

// MARK: - Step 4 — name + confirm

@Composable
private fun ConfirmStep(
    advertisedName: String,
    brand: String,
    rssi: Int,
    name: String,
    onName: (String) -> Unit,
    onAdd: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .frostedCardSurface(cornerRadius = 12.dp)
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SignalBars(rssi)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(advertisedName, style = NoopType.headline, color = Palette.textPrimary)
                Text(brand, style = NoopType.caption, color = Palette.textTertiary)
            }
        }

        Overline("Name")
        OutlinedTextField(
            value = name,
            onValueChange = onName,
            singleLine = true,
            placeholder = { Text("Device name", style = NoopType.body, color = Palette.textTertiary) },
            colors = wizardFieldColors(),
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = "Device name" },
        )

        TextButton(
            onClick = onAdd,
            enabled = name.trim().isNotEmpty(),
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(if (name.trim().isNotEmpty()) Palette.accent else Palette.surfaceInset),
        ) {
            Text(
                "Add",
                style = NoopType.headline,
                color = if (name.trim().isNotEmpty()) Palette.goldDeepText else Palette.textTertiary,
            )
        }
    }
}

@Composable
private fun wizardFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedTextColor = Palette.textPrimary,
    unfocusedTextColor = Palette.textPrimary,
    cursorColor = Palette.accent,
    focusedBorderColor = Palette.accent,
    unfocusedBorderColor = Palette.hairline,
    focusedContainerColor = Palette.surfaceInset,
    unfocusedContainerColor = Palette.surfaceInset,
)
