import Foundation
import StrandAnalytics

/// Builds the prefilled GitHub new-issue URL for a Test Centre report (spec section 5.2). It binds
/// the bug form's existing id fields (version, platform, os_version, test_profile, title) and
/// self-applies the "bug,test:<id>" labels so a submission lands pre-labelled on the right cluster.
/// No network, no cloud: this only composes a URL the caller opens in the browser. Repo is
/// NoopApp/noop (confirmed in bug_report.yml).
enum TestReportLink {

    /// Percent-encodes a query value with a strict allowed set: alphanumerics plus the few chars we
    /// want to stay literal (colon, dot, hyphen, underscore). Crucially the comma in "bug,test:id" is
    /// NOT in the set so it encodes to %2C, byte-matching the Kotlin twin (URLComponents would leave
    /// the comma literal and diverge). Spaces and brackets in the title encode to %20 / %5B / %5D.
    private static func enc(_ v: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: ":.-_")
        return v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
    }

    /// The prefilled new-issue URL, or nil if it cannot form. `profile.id` is the wire id
    /// (dataImport -> "import"); `profile.githubLabel` is "test:<id>" (master -> "test:all").
    static func reportURL(profile: TestDomain, title: String,
                          version: String, platform: String, osVersion: String) -> URL? {
        let query = [
            "template=bug_report.yml",
            "labels=" + enc("bug,\(profile.githubLabel)"),
            "version=" + enc(version),
            "platform=" + enc(platform),
            "os_version=" + enc(osVersion),
            "test_profile=" + enc(profile.id),
            "title=" + enc("[\(profile.id)] \(title)"),
        ].joined(separator: "&")
        return URL(string: "https://github.com/NoopApp/noop/issues/new?" + query)
    }
}
