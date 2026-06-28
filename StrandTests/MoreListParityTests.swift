import XCTest
@testable import Strand

/// Guards the #805/#811 regression: the v7.3.1 #766 alarm consolidation folded Smart Alarm under a
/// single "Alarms" entry in the macOS/iPad sidebar (`NavItem.smartAlarm`), but the iPhone `RootTabView`
/// More list dropped the row, leaving Alarms unreachable on iPhone.
///
/// The iPhone More list is a `@ViewBuilder` (not directly introspectable), so this pins the *contract*
/// it must mirror: the shared sidebar exposes the `smartAlarm` destination with the exact SF Symbol the
/// restored `MoreRow("Alarms", "alarm.fill")` row uses. A future icon rename then fails here so the two
/// shells get fixed in lockstep rather than silently drifting apart again.
///
/// Notifications (`NavItem.notifications`) is deliberately NOT mirrored on iPhone: its screen
/// (`NotificationSettingsView`) is macOS-only (NSWorkspace app picker, imports AppKit, excluded from the
/// iOS target in project.yml), so the iPhone More list correctly omits it. The enum case still exists for
/// the macOS sidebar; that's all this asserts about it.
final class MoreListParityTests: XCTestCase {

    /// Alarms is the destination the iPhone More list had been missing; it must exist in the shared
    /// sidebar enum (the iPhone `MoreRow("Alarms")` routes to the same `SmartAlarmView`).
    func testSidebarExposesAlarms() {
        XCTAssertTrue(NavItem.allCases.contains(.smartAlarm),
                      "Alarms (smartAlarm) must stay a sidebar destination the iPhone More list mirrors.")
    }

    /// The restored iPhone Alarms row pins this exact SF Symbol; keep it identical to the sidebar so the
    /// two shells read the same.
    func testAlarmsIconMatchesTheRestorediPhoneRow() {
        XCTAssertEqual(NavItem.smartAlarm.icon, "alarm.fill")
    }

    /// Notifications stays a (macOS-only) sidebar destination. It is intentionally absent from the iPhone
    /// More list, so this only documents that the enum case is still the macOS home for it.
    func testNotificationsRemainsAMacOSSidebarDestination() {
        XCTAssertTrue(NavItem.allCases.contains(.notifications))
    }
}
