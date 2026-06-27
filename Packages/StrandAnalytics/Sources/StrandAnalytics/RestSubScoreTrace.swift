import Foundation

// RestSubScoreTrace.swift - the Sleep & Rest test-mode diagnostic for the Rest composite.
//
// Recomputes the four weighted sub-scores from the SAME inputs AnalyticsEngine.Rest.composite
// reads, and reuses Rest.composite for the final value so the trace can never disagree with the
// score. Pure and side-effect-free. No em-dashes. Counts and ratios only.

extension AnalyticsEngine.Rest {

    /// One Rest sub-score diagnostic line. `groupFragments` / `groupInBedSeconds` describe the
    /// main-night GROUP composition (#525/#561): how many detected blocks were bridged into the
    /// scored night and their summed in-bed span. The four term scores mirror `composite`'s own
    /// math; the final `composite=` value is `Rest.composite` verbatim so they cannot diverge.
    public static func subScoreLine(tstSeconds: Double, inBedSeconds: Double, efficiency: Double,
                                    restorativeSeconds: Double, needHours: Double,
                                    consistency: Double?, deepSeconds: Double?,
                                    groupFragments: Int, groupInBedSeconds: Double) -> String {
        func clamp01(_ x: Double) -> Double { max(0.0, min(1.0, x)) }
        func r2(_ x: Double) -> Double { (x * 100.0).rounded() / 100.0 }

        let needSeconds = max(needHours, 0.1) * 3600.0
        let durationScore = clamp01(tstSeconds / needSeconds)
        let efficiencyScore = clamp01(efficiency)
        let deepFactor: Double = {
            guard let deep = deepSeconds, tstSeconds > 0, deepShareTarget > 0 else { return 1.0 }
            let adequacy = clamp01((deep / tstSeconds) / deepShareTarget)
            return deepFloorFactor + (1.0 - deepFloorFactor) * adequacy
        }()
        let restorativeScore = tstSeconds > 0
            ? clamp01((restorativeSeconds / tstSeconds) / restorativeTarget) * deepFactor
            : 0.0
        let consistencyScore = clamp01(consistency ?? neutralConsistency)
        let composite = AnalyticsEngine.Rest.composite(
            tstSeconds: tstSeconds, inBedSeconds: inBedSeconds, efficiency: efficiency,
            restorativeSeconds: restorativeSeconds, needHours: needHours,
            consistency: consistency, deepSeconds: deepSeconds)

        return "rest composite=\(r2(composite)) "
            + "dur=\(r2(durationScore))*wDur=\(wDuration) "
            + "eff=\(r2(efficiencyScore))*wEff=\(wEfficiency) "
            + "restor=\(r2(restorativeScore))*wRestor=\(wRestorative) deepFactor=\(r2(deepFactor)) "
            + "consist=\(r2(consistencyScore))*wConsist=\(wConsistency) "
            + "group=\(groupFragments) groupInBedMin=\(Int(groupInBedSeconds / 60))"
    }
}
