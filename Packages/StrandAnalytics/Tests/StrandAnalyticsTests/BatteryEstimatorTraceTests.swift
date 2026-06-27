import XCTest
@testable import StrandAnalytics

/// The Battery test mode's pure SoC-series + discharge-run + slope + gate trace. Pins the exact lines a
/// fixture series produces AND proves the emitter never changes the engine value `estimate(...)` returns
/// (#713, Test Centre). Twin of the Android BatteryEstimatorTraceTest. No em-dashes.
final class BatteryEstimatorTraceTests: XCTestCase {

    private let h = 3600

    func testTraceNilWhenNoSamples() {
        let (estimate, lines) = BatteryEstimator.estimateTrace(
            samples: [], ratedHours: BatteryEstimator.ratedLifeHoursWhoop5)
        XCTAssertNil(estimate)
        XCTAssertEqual(lines, ["battery series=0 readings, no reading to anchor to"])
    }

    func testTraceEmitsSeriesChargeStepRunSlopeAndGate() {
        // Same fixture as the discharge-restart case: discharge 100->70, a charge back to 100 at 5h, then
        // 100->88 over 6h. The run is fit on the post-charge segment only (2 %/h), source measured.
        let samples: [(ts: Int, soc: Double)] = [(0, 100), (4 * h, 70), (5 * h, 100), (11 * h, 88)]
        let (estimate, lines) = BatteryEstimator.estimateTrace(
            samples: samples, ratedHours: BatteryEstimator.ratedLifeHoursWhoop5)

        // The emitter must NOT change the engine result (byte-identical to estimate()).
        let plain = BatteryEstimator.estimate(samples: samples,
                                              ratedHours: BatteryEstimator.ratedLifeHoursWhoop5)
        XCTAssertEqual(estimate, plain)

        XCTAssertEqual(lines, [
            "battery series=4 readings span 0..39600s",
            "battery read t=0s soc=100.0",
            "battery read t=14400s soc=70.0",
            "battery read t=18000s soc=100.0",
            "battery read t=39600s soc=88.0",
            "battery chargeStep at t=18000s +30.0pp (>chargeStepPct 1.0)",
            "battery dischargeRun start=18000s span=6.0h drop=12.0pp",
            "battery slope=2.0pct/h fitted from run endpoints",
            "battery gate minSpanHours 2.0 PASS, minDropPct 2.0 PASS -> source=measured",
        ])
    }

    func testTraceGateDropToRatedWhenDropTooSmall() {
        // 100->99 over 10h is a 1pp drop, under minDropPct 2, so the gate fails and source=rated.
        let samples: [(ts: Int, soc: Double)] = [(0, 100), (10 * h, 99)]
        let (estimate, lines) = BatteryEstimator.estimateTrace(
            samples: samples, ratedHours: BatteryEstimator.ratedLifeHoursWhoop5)
        XCTAssertEqual(estimate?.source, .rated)
        XCTAssertTrue(lines.contains(
            "battery gate minSpanHours 2.0 PASS, minDropPct 2.0 FAIL -> source=rated"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("battery chargeStep") })
    }
}
