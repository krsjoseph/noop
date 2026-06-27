package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Twin of the Swift BatteryEstimatorTraceTests: same fixtures, same trace lines, and the same proof that
 *  the emitter never changes the engine value estimate() returns (#713, Test Centre). No em-dashes. */
class BatteryEstimatorTraceTest {

    private val h = 3600L

    @Test fun traceNullWhenNoSamples() {
        val (estimate, lines) = BatteryEstimator.estimateTrace(
            emptyList(), BatteryEstimator.ratedLifeHoursWhoop5)
        assertNull(estimate)
        assertEquals(listOf("battery series=0 readings, no reading to anchor to"), lines)
    }

    @Test fun traceEmitsSeriesChargeStepRunSlopeAndGate() {
        val samples = listOf(0L to 100.0, 4 * h to 70.0, 5 * h to 100.0, 11 * h to 88.0)
        val (estimate, lines) = BatteryEstimator.estimateTrace(
            samples, BatteryEstimator.ratedLifeHoursWhoop5)

        // The emitter must NOT change the engine result.
        assertEquals(BatteryEstimator.estimate(samples, BatteryEstimator.ratedLifeHoursWhoop5), estimate)

        assertEquals(listOf(
            "battery series=4 readings span 0..39600s",
            "battery read t=0s soc=100.0",
            "battery read t=14400s soc=70.0",
            "battery read t=18000s soc=100.0",
            "battery read t=39600s soc=88.0",
            "battery chargeStep at t=18000s +30.0pp (>chargeStepPct 1.0)",
            "battery dischargeRun start=18000s span=6.0h drop=12.0pp",
            "battery slope=2.0pct/h fitted from run endpoints",
            "battery gate minSpanHours 2.0 PASS, minDropPct 2.0 PASS -> source=measured",
        ), lines)
    }

    @Test fun traceGateDropToRatedWhenDropTooSmall() {
        val samples = listOf(0L to 100.0, 10 * h to 99.0)
        val (estimate, lines) = BatteryEstimator.estimateTrace(
            samples, BatteryEstimator.ratedLifeHoursWhoop5)
        assertEquals(BatteryEstimator.Source.RATED, estimate?.source)
        assertTrue(lines.contains(
            "battery gate minSpanHours 2.0 PASS, minDropPct 2.0 FAIL -> source=rated"))
        assertFalse(lines.any { it.startsWith("battery chargeStep") })
    }
}
