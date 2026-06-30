import XCTest
@testable import NoopLocalAccessCore

final class DatabasePathResolverTests: XCTestCase {
    func testPersonalBundleIsNotADefaultCandidate() {
        let candidates = DatabasePathResolver.candidates(home: "/Users/example")

        XCTAssertTrue(candidates.contains("/Users/example/Library/Containers/com.aretetechnologies.kineva/Data/Library/Application Support/OpenWhoop/whoop.sqlite"))
        XCTAssertFalse(candidates.contains { $0.contains("com.aretetechnologies.kineva.personal") })
    }

    func testCustomBundleIDIsExplicitOptIn() {
        let candidates = DatabasePathResolver.candidates(bundleID: "com.example.noop", home: "/Users/example")

        XCTAssertEqual(
            candidates.first,
            "/Users/example/Library/Containers/com.example.noop/Data/Library/Application Support/OpenWhoop/whoop.sqlite"
        )
        XCTAssertTrue(candidates.contains("/Users/example/Library/Containers/com.aretetechnologies.kineva/Data/Library/Application Support/OpenWhoop/whoop.sqlite"))
    }

    func testExplicitPathMustExist() throws {
        let url = try TemporaryDatabase.emptyFileURL()
        let config = LocalAccessConfiguration(databasePath: url.path)

        XCTAssertEqual(try DatabasePathResolver.resolve(configuration: config), url.path)
    }

    func testExplicitPathFailureDoesNotFallBack() {
        let config = LocalAccessConfiguration(databasePath: "/definitely/not/noop/whoop.sqlite")

        XCTAssertThrowsError(try DatabasePathResolver.resolve(configuration: config)) { error in
            XCTAssertEqual(error as? LocalAccessError, .databaseUnavailable("Kineva database not found at KINEVA_DB_PATH."))
        }
    }
}
