import XCTest
@testable import StrandAnalytics

final class RestSubScoreTraceTests: XCTestCase {
    func testRestSubScoreLine() {
        // 8 h TST, 0.92 efficiency, 50% restorative, neutral consistency, 1 night-group fragment.
        let line = AnalyticsEngine.Rest.subScoreLine(
            tstSeconds: 8 * 3600, inBedSeconds: 8 * 3600 / 0.92, efficiency: 0.92,
            restorativeSeconds: 4 * 3600, needHours: 8.0, consistency: nil,
            deepSeconds: 1 * 3600, groupFragments: 1, groupInBedSeconds: 8 * 3600 / 0.92)
        XCTAssertTrue(line.hasPrefix("rest "), line)
        XCTAssertTrue(line.contains("wDur=0.5"))
        XCTAssertTrue(line.contains("wEff=0.2"))
        XCTAssertTrue(line.contains("wRestor=0.2"))
        XCTAssertTrue(line.contains("wConsist=0.1"))
        XCTAssertTrue(line.contains("group=1"))
        XCTAssertFalse(line.contains("\u{2014}"))
    }

    func testCompositeMatchesRestComposite() {
        // The line's composite= value must equal Rest.composite from the same inputs (cannot diverge).
        let tst = 7.5 * 3600.0, inBed = 8.0 * 3600.0, eff = 0.9
        let restorative = 3.0 * 3600.0, need = 8.0, deep = 1.2 * 3600.0
        let line = AnalyticsEngine.Rest.subScoreLine(
            tstSeconds: tst, inBedSeconds: inBed, efficiency: eff,
            restorativeSeconds: restorative, needHours: need, consistency: 0.7,
            deepSeconds: deep, groupFragments: 2, groupInBedSeconds: inBed)
        let composite = AnalyticsEngine.Rest.composite(
            tstSeconds: tst, inBedSeconds: inBed, efficiency: eff,
            restorativeSeconds: restorative, needHours: need, consistency: 0.7, deepSeconds: deep)
        let r2 = (composite * 100.0).rounded() / 100.0
        XCTAssertTrue(line.contains("composite=\(r2)"), line)
    }
}
