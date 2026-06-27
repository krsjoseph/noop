package com.noop.analytics

import java.util.Locale
import kotlin.math.roundToLong

/**
 * "~X days left" for a strap, worked out from its battery state-of-charge (SoC) history (#713). Neither
 * the WHOOP app nor WHOOP's API ever give you a runtime estimate, but NOOP already banks a SoC time
 * series from the strap over BLE, so no manual logging is needed. We fit the recent DISCHARGE slope and
 * divide the current charge by it. When the discharge run is too short or too flat to trust, we fall back
 * to the device's typical full-charge life for its generation.
 *
 * The measured slope already bakes in how the user actually runs their strap (HR broadcast, strain,
 * recording), so there are no hand-tuned usage multipliers. The discharge curve IS the personalisation.
 *
 * Honest about the limits: battery drain is non-linear (faster near full and near empty) and the strap
 * reports SoC sparsely, so this is an estimate, not a guarantee. Behaviour-identical twin of the Swift
 * BatteryEstimator (same fixtures, same numbers).
 */
object BatteryEstimator {

    /** Typical full-charge life in hours per WHOOP generation, used before enough of the user's own
     *  discharge has been seen to fit a slope. WHOOP 4.0 is about 4.5 days, WHOOP 5.0 / MG about 12 days
     *  (the figures cited in #713). The caller maps its connected strap to one of these. */
    const val ratedLifeHoursWhoop4 = 108.0   // 4.5 days
    const val ratedLifeHoursWhoop5 = 288.0   // 12 days

    /** A discharge run has to span at least this long AND drop at least this much before its measured
     *  slope is trusted over the rated fallback. Short or noisy spans produce wild rates. */
    const val minSpanHours = 2.0
    const val minDropPct = 2.0

    /** A SoC rise larger than this (percentage points) between two consecutive readings marks a CHARGE.
     *  The discharge run restarts after it, so we never fit a rate across a charge. */
    const val chargeStepPct = 1.0

    /** Where the drain rate came from: the user's own measured discharge, or the rated fallback. */
    enum class Source { MEASURED, RATED }

    data class Estimate(
        /** Estimated hours of runtime left at the latest reading. */
        val remainingHours: Double,
        val source: Source,
        /** The latest SoC the estimate is anchored to, in percent. */
        val currentSoc: Double,
    ) {
        /** Convenience for callers that just want the days figure. */
        val daysRemaining: Double get() = remainingHours / 24
        /** Mirror so callers can read either name. */
        val hoursRemaining: Double get() = remainingHours
    }

    /**
     * Estimate remaining runtime from a SoC series.
     *
     * [samples] = (unix-seconds, SoC%) pairs in any order. The caller drops nil-SoC rows and maps the
     * banked battery series into this shape. [ratedHours] = the strap's typical full-charge life, one of
     * the `ratedLifeHours…` constants, chosen by the caller from the connected strap's generation.
     * Returns null only when there isn't a single reading to anchor to. Mirrors the Swift estimate().
     */
    fun estimate(samples: List<Pair<Long, Double>>, ratedHours: Double): Estimate? {
        val sorted = samples.sortedBy { it.first }
        val last = sorted.lastOrNull() ?: return null
        val current = last.second

        // Take the trailing discharge run only: everything after the most recent CHARGE step (a SoC rise
        // larger than chargeStepPct), so a charge earlier in the buffer never flattens the fitted slope.
        var startIdx = 0
        if (sorted.size >= 2) {
            for (i in sorted.size - 1 downTo 1) {
                if (sorted[i].second > sorted[i - 1].second + chargeStepPct) {
                    startIdx = i
                    break
                }
            }
        }
        val dischargeRun = sorted.subList(startIdx, sorted.size)

        // Fit the discharge slope over the run as a simple endpoints rate (%/h). The series is short and
        // monotone-ish within a run, so endpoints are as good as a least-squares line and far cheaper, and
        // they keep the test fixtures exact. null when the run is too short, too flat, or not discharging.
        val measuredRate: Double? = run {
            if (dischargeRun.size < 2) return@run null
            val first = dischargeRun.first()
            val lastRun = dischargeRun.last()
            val spanHours = (lastRun.first - first.first) / 3600.0
            val drop = first.second - lastRun.second
            if (spanHours < minSpanHours || drop < minDropPct) return@run null
            val rate = drop / spanHours
            if (rate > 0) rate else null
        }

        val rate = measuredRate ?: (100.0 / maxOf(ratedHours, 1.0))
        val remaining = maxOf(0.0, current) / rate
        // A fresh full charge can't realistically beat about 1.5x the rated life, so clamp out any wild
        // estimate from a near-flat measured run that still squeaked past the drop gate.
        val clamped = minOf(remaining, ratedHours * 1.5)
        return Estimate(clamped, if (measuredRate != null) Source.MEASURED else Source.RATED, current)
    }

    /**
     * Side-effect-free diagnostic twin of [estimate]: returns the SAME Estimate plus a list of trace
     * lines describing the full (t, soc) series, the detected charge step(s), the trailing discharge run
     * start/span/drop, the fitted slope, and which gate (minSpanHours / minDropPct) decided source =
     * measured vs rated. The Battery test mode gates this behind TestCentre.active(BATTERY); when the mode
     * is off it is never called, so there is zero cost. Pure: no clock, no I/O. Twin of the Swift trace.
     */
    fun estimateTrace(samples: List<Pair<Long, Double>>, ratedHours: Double):
        Pair<Estimate?, List<String>> {
        val sorted = samples.sortedBy { it.first }
        val last = sorted.lastOrNull()
        val first0 = sorted.firstOrNull()
        if (last == null || first0 == null) {
            return null to listOf("battery series=0 readings, no reading to anchor to")
        }
        val lines = mutableListOf<String>()
        lines.add("battery series=${sorted.size} readings span ${first0.first}..${last.first}s")
        for (s in sorted) lines.add("battery read t=${s.first}s soc=${soc(s.second)}")

        var startIdx = 0
        if (sorted.size >= 2) {
            for (i in sorted.size - 1 downTo 1) {
                if (sorted[i].second > sorted[i - 1].second + chargeStepPct) {
                    startIdx = i
                    val rise = sorted[i].second - sorted[i - 1].second
                    lines.add("battery chargeStep at t=${sorted[i].first}s +${soc(rise)}pp " +
                        "(>chargeStepPct ${soc(chargeStepPct)})")
                    break
                }
            }
        }
        val run = sorted.subList(startIdx, sorted.size)

        var spanPass = false
        var dropPass = false
        if (run.size >= 2) {
            val runFirst = run.first()
            val runLast = run.last()
            val spanHours = (runLast.first - runFirst.first) / 3600.0
            val drop = runFirst.second - runLast.second
            lines.add("battery dischargeRun start=${runFirst.first}s " +
                "span=${hrs(spanHours)}h drop=${soc(drop)}pp")
            spanPass = spanHours >= minSpanHours
            dropPass = drop >= minDropPct
            if (spanPass && dropPass && drop / spanHours > 0) {
                lines.add("battery slope=${slope(drop / spanHours)}pct/h fitted from run endpoints")
            }
        } else {
            lines.add("battery dischargeRun too short to fit (run=${run.size} readings)")
        }

        val measured = spanPass && dropPass && run.size >= 2 &&
            (run.first().second - run.last().second) /
            ((run.last().first - run.first().first) / 3600.0) > 0
        lines.add("battery gate minSpanHours ${hrs(minSpanHours)} " +
            "${if (spanPass) "PASS" else "FAIL"}, minDropPct ${soc(minDropPct)} " +
            "${if (dropPass) "PASS" else "FAIL"} -> source=${if (measured) "measured" else "rated"}")

        return estimate(samples, ratedHours) to lines
    }

    private fun soc(v: Double) = String.format(Locale.US, "%.1f", v)
    private fun hrs(v: Double) = String.format(Locale.US, "%.1f", v)
    private fun slope(v: Double) = String.format(Locale.US, "%.1f", v)

    /** Display rule from #713: hours under 48h ("~14h"), days above ("~4.5 days"). Unit text only, the UI
     *  adds the "left" / "remaining" copy. Locale-fixed so the tests stay stable. */
    fun label(hours: Double): String =
        if (hours < 48) "~${hours.roundToLong()}h"
        else "~${String.format(Locale.US, "%.1f", hours / 24)} days"
}
