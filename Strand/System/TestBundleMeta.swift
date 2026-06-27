import Foundation

/// The machine-readable tie between a strap log and the test profile that produced it: meta.json,
/// schema v1 (spec section 5.1). Folds in build-provenance and the storage / DB-size block so a
/// maintainer sees the version, channel, signing and on-disk footprint without asking. snake_case
/// wire keys match the spec JSON sample; sortedKeys keeps the Swift and Kotlin output byte-aligned.
struct TestBundleMeta: Codable {
    let schema: Int                    // always 1
    let appVersion: String
    let platform: String               // "iOS" | "macOS" | "Android"
    let osVersion: String
    let strapModel: String?
    let source: [String]               // e.g. ["Live Bluetooth"]
    let testProfile: String            // TestDomain.id
    let profileStartedAt: String?      // ISO8601, from TestCentre.startedAt
    let questionnaire: [String: String]
    let build: Build
    let storage: Storage
    let redaction: String              // "v2"
    let truncated: Bool

    /// channel: one of AltStore / App Store / TestFlight / brew / GitHub / sideload. signed is false on
    /// the sideloaded iOS path; derived from IOSDiagnostics.isSideloaded on iOS, fixed per flavour else.
    struct Build: Codable { let channel: String; let signed: Bool }

    /// db_bytes plus per-table row counts plus the raw-capture footprint (#590 asked us to surface this).
    struct Storage: Codable {
        let dbBytes: Int; let rows: [String: Int]; let rawCaptureBytes: Int
        enum CodingKeys: String, CodingKey {
            case rows
            case dbBytes = "db_bytes", rawCaptureBytes = "raw_capture_bytes"
        }
    }

    enum CodingKeys: String, CodingKey {
        case schema, platform, source, questionnaire, build, storage, redaction, truncated
        case appVersion = "app_version", osVersion = "os_version", strapModel = "strap_model"
        case testProfile = "test_profile", profileStartedAt = "profile_started_at"
    }

    func encoded() -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? e.encode(self)) ?? Data()
    }
}
