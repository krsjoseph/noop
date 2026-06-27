import Foundation

/// "~X days left" for a strap, worked out from its battery state-of-charge (SoC) history (#713). Neither
/// the WHOOP app nor WHOOP's API ever give you a runtime estimate, but NOOP already banks a SoC time
/// series from the strap over BLE, so no manual logging is needed. We fit the recent DISCHARGE slope and
/// divide the current charge by it. When the discharge run is too short or too flat to trust, we fall back
/// to the device's typical full-charge life for its generation.
///
/// The measured slope already bakes in how the user actually runs their strap (HR broadcast, strain,
/// recording), so there are no hand-tuned usage multipliers. The discharge curve IS the personalisation.
///
/// Honest about the limits: battery drain is non-linear (faster near full and near empty) and the strap
/// reports SoC sparsely, so this is an estimate, not a guarantee. Pure value type with no I/O. The Kotlin
/// twin is BatteryEstimator.kt, kept behaviour-identical (same fixtures, same numbers).
public enum BatteryEstimator {

    // MARK: - Rated full-charge life (the cold-start fallback)

    /// Typical full-charge life in hours per WHOOP generation, used before enough of the user's own
    /// discharge has been seen to fit a slope. WHOOP 4.0 is about 4.5 days, WHOOP 5.0 / MG about 12 days
    /// (the figures cited in #713). The caller maps its connected strap to one of these.
    public static let ratedLifeHoursWhoop4: Double = 108   // 4.5 days
    public static let ratedLifeHoursWhoop5: Double = 288   // 12 days

    /// A discharge run has to span at least this long AND drop at least this much before its measured
    /// slope is trusted over the rated fallback. Short or noisy spans produce wild rates.
    public static let minSpanHours: Double = 2.0
    public static let minDropPct: Double = 2.0

    /// A SoC rise larger than this (percentage points) between two consecutive readings marks a CHARGE.
    /// The discharge run restarts after it, so we never fit a rate across a charge.
    public static let chargeStepPct: Double = 1.0

    // MARK: - Output

    /// Where the drain rate came from: the user's own measured discharge, or the rated fallback.
    public enum Source: String, Equatable, Sendable { case measured, rated }

    public struct Estimate: Equatable, Sendable {
        /// Estimated hours of runtime left at the latest reading.
        public let remainingHours: Double
        public let source: Source
        /// The latest SoC the estimate is anchored to, in percent.
        public let currentSoc: Double

        public init(remainingHours: Double, source: Source, currentSoc: Double) {
            self.remainingHours = remainingHours
            self.source = source
            self.currentSoc = currentSoc
        }

        /// Convenience for callers that just want the days figure.
        public var daysRemaining: Double { remainingHours / 24 }
        /// Mirror so callers can read either name.
        public var hoursRemaining: Double { remainingHours }
    }

    // MARK: - Estimate

    /// Estimate remaining runtime from a SoC series.
    ///
    /// - Parameters:
    ///   - samples: `(unix-seconds, SoC%)` pairs in any order. The caller drops nil-SoC rows and maps the
    ///     banked battery series into this shape.
    ///   - ratedHours: the strap's typical full-charge life, one of the `ratedLifeHours…` constants,
    ///     chosen by the caller from the connected strap's generation.
    /// - Returns: an estimate, or nil when there isn't a single reading to anchor to.
    public static func estimate(samples: [(ts: Int, soc: Double)], ratedHours: Double) -> Estimate? {
        let sorted = samples.sorted { $0.ts < $1.ts }
        guard let last = sorted.last else { return nil }
        let current = last.soc

        // Take the trailing discharge run only: everything after the most recent CHARGE step (a SoC rise
        // larger than chargeStepPct), so a charge earlier in the buffer never flattens the fitted slope.
        var startIdx = 0
        if sorted.count >= 2 {
            for i in stride(from: sorted.count - 1, through: 1, by: -1)
            where sorted[i].soc > sorted[i - 1].soc + chargeStepPct {
                startIdx = i
                break
            }
        }
        let run = Array(sorted[startIdx...])

        // Fit the discharge slope over the run as a simple endpoints rate (%/h). The series is short and
        // monotone-ish within a run, so endpoints are as good as a least-squares line and far cheaper, and
        // they keep the test fixtures exact. nil when the run is too short, too flat, or not discharging.
        let measuredRate: Double? = {
            guard run.count >= 2, let first = run.first, let lastRun = run.last else { return nil }
            let spanHours = Double(lastRun.ts - first.ts) / 3600.0
            let drop = first.soc - lastRun.soc
            guard spanHours >= minSpanHours, drop >= minDropPct else { return nil }
            let rate = drop / spanHours
            return rate > 0 ? rate : nil
        }()

        let rate = measuredRate ?? (100.0 / max(ratedHours, 1))
        let remaining = max(0, current) / rate
        // A fresh full charge can't realistically beat about 1.5x the rated life, so clamp out any wild
        // estimate from a near-flat measured run that still squeaked past the drop gate.
        let clamped = min(remaining, ratedHours * 1.5)
        return Estimate(remainingHours: clamped,
                        source: measuredRate != nil ? .measured : .rated,
                        currentSoc: current)
    }

    /// Side-effect-free diagnostic twin of `estimate`: returns the SAME `Estimate` plus a list of trace
    /// lines describing the full (t, soc) series, the detected charge step(s), the trailing discharge run
    /// start/span/drop, the fitted slope, and which gate (minSpanHours / minDropPct) decided source =
    /// measured vs rated. The Battery test mode gates this behind TestCentre.active(.battery) and feeds the
    /// lines to append(log:domain:.battery); when the mode is off it is never called, so there is zero
    /// cost. Pure: no clock, no I/O, so fixtures stay exact. The Kotlin twin is BatteryEstimator.estimateTrace.
    public static func estimateTrace(samples: [(ts: Int, soc: Double)], ratedHours: Double)
        -> (estimate: Estimate?, trace: [String]) {
        let sorted = samples.sorted { $0.ts < $1.ts }
        guard let last = sorted.last, let first0 = sorted.first else {
            return (nil, ["battery series=0 readings, no reading to anchor to"])
        }
        var lines: [String] = []
        lines.append("battery series=\(sorted.count) readings span \(first0.ts)..\(last.ts)s")
        for s in sorted { lines.append("battery read t=\(s.ts)s soc=\(socText(s.soc))") }

        // The most recent CHARGE step (same scan as estimate): a SoC rise larger than chargeStepPct.
        var startIdx = 0
        if sorted.count >= 2 {
            for i in stride(from: sorted.count - 1, through: 1, by: -1)
            where sorted[i].soc > sorted[i - 1].soc + chargeStepPct {
                startIdx = i
                let rise = sorted[i].soc - sorted[i - 1].soc
                lines.append("battery chargeStep at t=\(sorted[i].ts)s +\(socText(rise))pp "
                    + "(>chargeStepPct \(socText(chargeStepPct)))")
                break
            }
        }
        let run = Array(sorted[startIdx...])

        var spanPass = false
        var dropPass = false
        if run.count >= 2, let runFirst = run.first, let runLast = run.last {
            let spanHours = Double(runLast.ts - runFirst.ts) / 3600.0
            let drop = runFirst.soc - runLast.soc
            lines.append("battery dischargeRun start=\(runFirst.ts)s "
                + "span=\(hoursText(spanHours))h drop=\(socText(drop))pp")
            spanPass = spanHours >= minSpanHours
            dropPass = drop >= minDropPct
            if spanPass && dropPass && drop / spanHours > 0 {
                lines.append("battery slope=\(slopeText(drop / spanHours))pct/h fitted from run endpoints")
            }
        } else {
            lines.append("battery dischargeRun too short to fit (run=\(run.count) readings)")
        }

        let measured = spanPass && dropPass && run.count >= 2
            && (run.first!.soc - run.last!.soc) / (Double(run.last!.ts - run.first!.ts) / 3600.0) > 0
        lines.append("battery gate minSpanHours \(hoursText(minSpanHours)) "
            + "\(spanPass ? "PASS" : "FAIL"), minDropPct \(socText(minDropPct)) "
            + "\(dropPass ? "PASS" : "FAIL") -> source=\(measured ? "measured" : "rated")")

        return (estimate(samples: samples, ratedHours: ratedHours), lines)
    }

    private static func socText(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func hoursText(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func slopeText(_ v: Double) -> String { String(format: "%.1f", v) }

    /// Display rule from #713: show hours under 48h ("~14h"), days above ("~4.5 days"). Unit text only,
    /// the caller adds the "left" / "remaining" copy. Locale-free so the tests stay stable; the UI
    /// localises the number when it renders.
    public static func label(hours: Double) -> String {
        if hours < 48 { return "~\(Int(hours.rounded()))h" }
        return "~\(String(format: "%.1f", hours / 24)) days"
    }
}
