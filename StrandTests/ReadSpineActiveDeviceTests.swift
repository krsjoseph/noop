import XCTest
import Foundation
import WhoopStore
import WhoopProtocol
@testable import Strand

/// #814 READ SPINE: after a remove+re-add the strap gets a FRESH registry id ("whoop-<uuid>"), so the
/// Collector writes today's raw under THAT id. The read side must follow the registry's active id rather
/// than the hardcoded "my-whoop", or the dashboard reads an empty stale namespace and Today snaps onto an
/// old day. These tests pin the contract: after `adoptActiveDeviceId`, the read deviceId == the write
/// deviceId, and the data written under the new id is the data the read facades return, not the old id's.
final class ReadSpineActiveDeviceTests: XCTestCase {

    private let oldId = "my-whoop"
    private let newId = "whoop-ABC123"   // the id a re-added strap gets (AddDeviceWizard: "whoop-<uuid>")

    /// The core regression: re-point the read model to the re-added strap's id, then the read deviceId
    /// equals the WRITE id, and a latest-data lookup finds the data written under the NEW id, never the
    /// stale "my-whoop" day. Before the fix the read stayed on "my-whoop" and `latestDataDayStart`
    /// returned the old day (or nil), snapping Today onto stale/empty data.
    @MainActor
    func testReadFollowsActiveIdAfterReAdd() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: oldId, mac: nil, name: "WHOOP")
        try await store.upsertDevice(id: newId, mac: nil, name: "WHOOP")

        // Stale "my-whoop" data sits months in the past; the re-added strap's data is TODAY, under newId.
        let now = Int(Date().timeIntervalSince1970)
        let staleBase = now - 120 * 86_400
        let freshBase = now - 2 * 3_600   // a couple of hours ago (squarely "today")
        try await store.insert(Streams(hr: (0..<300).map { HRSample(ts: staleBase + $0, bpm: 50) }), deviceId: oldId)
        try await store.insert(Streams(hr: (0..<300).map { HRSample(ts: freshBase + $0, bpm: 70) }), deviceId: newId)

        let repo = Repository(deviceId: oldId)
        repo.setStoreForTesting(store)

        // Seeded with the old id, the latest data is the STALE day.
        let staleLatest = await repo.latestDataDayStart()
        XCTAssertEqual(staleLatest, Repository.logicalDayStart(Date(timeIntervalSince1970: TimeInterval(staleBase))),
                       "before re-point the read model sees only the old namespace")

        // Re-add → re-point. Read deviceId now equals the write id.
        let moved = repo.adoptActiveDeviceId(newId)
        XCTAssertTrue(moved, "adopting a different active id must move the read deviceId")
        XCTAssertEqual(repo.deviceId, newId, "read deviceId must equal the write (Collector) deviceId after re-add")

        // The latest data is now TODAY's, written under the new id, not the stale day.
        let freshLatest = await repo.latestDataDayStart()
        XCTAssertEqual(freshLatest, Repository.logicalDayStart(Date(timeIntervalSince1970: TimeInterval(freshBase))),
                       "after re-point the dashboard reads today's data under the new id, not the stale day")
        XCTAssertNotEqual(freshLatest, staleLatest, "Today must not snap back to the stale namespace's day")
    }

    /// The HR read facades (`hrSamples` / `hrBuckets`) follow the re-pointed id, so the Today HR trend (and
    /// the auto-land lookup, which goes through these) charts the re-added strap's data, purely the new
    /// id's samples, never the old id's.
    @MainActor
    func testHrFacadesReadOnlyTheActiveIdAfterReAdd() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: oldId, mac: nil, name: "WHOOP")
        try await store.upsertDevice(id: newId, mac: nil, name: "WHOOP")

        let base = 1_780_000_000
        // Distinguishable bpm per id so a leak is unambiguous: old @ 50, new @ 88.
        try await store.insert(Streams(hr: (0..<300).map { HRSample(ts: base + $0, bpm: 50) }), deviceId: oldId)
        try await store.insert(Streams(hr: (0..<300).map { HRSample(ts: base + $0, bpm: 88) }), deviceId: newId)

        let repo = Repository(deviceId: oldId)
        repo.setStoreForTesting(store)
        repo.adoptActiveDeviceId(newId)

        let samples = await repo.hrSamples(from: base, to: base + 300)
        XCTAssertEqual(samples.count, 300)
        XCTAssertTrue(samples.allSatisfy { $0.bpm == 88 }, "read must return only the active (re-added) id's samples")
        XCTAssertFalse(samples.contains { $0.bpm == 50 }, "the stale id's samples must never leak after re-point")
    }

    /// Adopting an EMPTY or UNCHANGED id is a no-op (single-device install: active id stays "my-whoop"),
    /// so the default path is byte-identical to the pre-#814 behaviour.
    @MainActor
    func testAdoptIsNoOpForEmptyOrUnchangedId() async throws {
        let repo = Repository(deviceId: oldId)
        XCTAssertFalse(repo.adoptActiveDeviceId(oldId), "same id must not move")
        XCTAssertFalse(repo.adoptActiveDeviceId(""), "empty id must not move")
        XCTAssertFalse(repo.adoptActiveDeviceId("   "), "whitespace-only id must not move")
        XCTAssertEqual(repo.deviceId, oldId)
    }

    /// The computed ("-noop") sibling id tracks the re-pointed strap id automatically, so the dashboard
    /// merge reads the engine's computed rows under "<newId>-noop" after a re-add, the read and write
    /// sides of the computed namespace stay aligned.
    @MainActor
    func testComputedRowsReadUnderNewIdAfterReAdd() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: newId, mac: nil, name: "WHOOP")

        // The engine would persist computed daily rows under "<active>-noop". Seed one under the NEW id's
        // computed sibling on TODAY so it lands in the refresh window.
        let todayKey = Repository.localDayKey(Date())
        let computed = DailyMetric(day: todayKey, totalSleepMin: 420, efficiency: 0.9, deepMin: 90,
                                   remMin: 100, lightMin: 230, disturbances: 2, restingHr: 52, avgHrv: 70,
                                   recovery: 66, strain: 8, exerciseCount: 0, spo2Pct: nil, skinTempDevC: nil,
                                   respRateBpm: 14, steps: nil, activeKcalEst: nil)
        _ = try await store.upsertDailyMetrics([computed], deviceId: newId + "-noop")

        let repo = Repository(deviceId: oldId)
        repo.setStoreForTesting(store)

        // Before re-point the dashboard reads "my-whoop-noop", empty, so today has no row.
        await repo.refresh()
        XCTAssertNil(repo.days.first(where: { $0.day == todayKey }),
                     "stale computed namespace must not surface the new strap's day")

        repo.adoptActiveDeviceId(newId)
        await repo.refresh()
        XCTAssertNotNil(repo.days.first(where: { $0.day == todayKey }),
                        "after re-point the dashboard reads computed rows under the new strap's -noop id")
    }
}
