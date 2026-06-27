import XCTest
@testable import Strand
import StrandAnalytics

/// Locks the prefilled new-issue URL (spec section 5.2): it must bind bug_report.yml's existing
/// id fields (version/platform/os_version/test_profile/title) and self-apply the "bug,test:<id>"
/// labels, with every component percent-encoded. The repo is NoopApp/noop (bug_report.yml line 10).
final class TestReportLinkTests: XCTestCase {

    func testSleepProfileURLEncodesEveryFieldAndLabel() {
        let url = TestReportLink.reportURL(
            profile: .sleep, title: "no score last night",
            version: "7.3.0", platform: "iOS", osVersion: "18.5")
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        XCTAssertTrue(s.hasPrefix("https://github.com/NoopApp/noop/issues/new?"))
        XCTAssertTrue(s.contains("template=bug_report.yml"))
        // Label component: "bug,test:sleep" with the comma percent-encoded.
        XCTAssertTrue(s.contains("labels=bug%2Ctest:sleep"))
        XCTAssertTrue(s.contains("version=7.3.0"))
        XCTAssertTrue(s.contains("platform=iOS"))
        XCTAssertTrue(s.contains("os_version=18.5"))
        XCTAssertTrue(s.contains("test_profile=sleep"))
        // Title is "[sleep] no score last night", brackets and spaces percent-encoded.
        XCTAssertTrue(s.contains("title=%5Bsleep%5D%20no%20score%20last%20night"))
    }

    func testDataImportProfileUsesImportWireIdNotRawValue() {
        // The dataImport case maps to the wire id "import" (TestDomain contract); the URL must
        // carry test_profile=import and labels=bug,test:import, never "dataImport".
        let url = TestReportLink.reportURL(
            profile: .dataImport, title: "x", version: "7.3.0", platform: "Android", osVersion: "15")
        let s = url!.absoluteString
        XCTAssertTrue(s.contains("test_profile=import"))
        XCTAssertTrue(s.contains("labels=bug%2Ctest:import"))
    }

    func testMasterProfileLabelIsTestAll() {
        let url = TestReportLink.reportURL(
            profile: .master, title: "x", version: "7.3.0", platform: "macOS", osVersion: "14.5")
        XCTAssertTrue(url!.absoluteString.contains("labels=bug%2Ctest:all"))
    }
}
