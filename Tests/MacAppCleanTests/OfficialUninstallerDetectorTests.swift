import XCTest
@testable import MacAppClean

final class OfficialUninstallerDetectorTests: XCTestCase {
    private var rootURL: URL!
    private var homeURL: URL!
    private var applicationsURL: URL!
    private var systemApplicationSupportURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "MacAppCleanUninstallerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        homeURL = rootURL.appending(path: "Home", directoryHint: .isDirectory)
        applicationsURL = rootURL.appending(path: "Applications", directoryHint: .isDirectory)
        systemApplicationSupportURL = rootURL.appending(path: "Library/Application Support", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applicationsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemApplicationSupportURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
        homeURL = nil
        applicationsURL = nil
        systemApplicationSupportURL = nil
        try super.tearDownWithError()
    }

    func testDetectFindsBundleResourceUninstallerApp() throws {
        let appURL = try makeApp(named: "Sample", bundleID: "com.example.sample")
        let uninstallerURL = appURL.appending(path: "Contents/Resources/Uninstall Sample.app", directoryHint: .isDirectory)
        try makeDirectory(uninstallerURL)

        let candidates = detector().detect(for: AppIdentity(appURL: appURL))

        XCTAssertEqual(candidates.first?.url.resolvingSymlinksInPath().path, uninstallerURL.resolvingSymlinksInPath().path)
        XCTAssertEqual(candidates.first?.kind, .app)
        XCTAssertEqual(candidates.first?.source, .bundleSupport)
        XCTAssertEqual(candidates.first?.confidence, .high)
    }

    func testDetectFindsSiblingUninstallerApp() throws {
        let appURL = try makeApp(named: "Sample", bundleID: "com.example.sample")
        let uninstallerURL = applicationsURL.appending(path: "Sample Uninstaller.app", directoryHint: .isDirectory)
        try makeDirectory(uninstallerURL)

        let candidates = detector().detect(for: AppIdentity(appURL: appURL))

        XCTAssertTrue(candidates.contains { samePath($0.url, uninstallerURL) && $0.source == .siblingDirectory })
    }

    func testDetectIgnoresUnrelatedUninstaller() throws {
        let appURL = try makeApp(named: "Sample", bundleID: "com.example.sample")
        let unrelatedURL = applicationsURL.appending(path: "Other App Uninstaller.app", directoryHint: .isDirectory)
        try makeDirectory(unrelatedURL)

        let candidates = detector().detect(for: AppIdentity(appURL: appURL))

        XCTAssertFalse(candidates.contains { samePath($0.url, unrelatedURL) })
    }

    func testDetectFindsPackageUninstaller() throws {
        let appURL = try makeApp(named: "Sample", bundleID: "com.example.sample")
        let supportURL = homeURL.appending(path: "Library/Application Support/Sample", directoryHint: .isDirectory)
        let pkgURL = supportURL.appending(path: "Remove Sample.pkg", directoryHint: .isDirectory)
        try makeDirectory(pkgURL)

        let candidates = detector().detect(for: AppIdentity(appURL: appURL))

        XCTAssertTrue(candidates.contains { samePath($0.url, pkgURL) && $0.kind == .pkg && $0.source == .applicationSupport })
    }

    func testDetectIgnoresShellUninstallers() throws {
        let appURL = try makeApp(named: "Sample", bundleID: "com.example.sample")
        try makeFile(applicationsURL.appending(path: "Uninstall Sample.sh"))
        try makeFile(applicationsURL.appending(path: "Sample Uninstaller.command"))

        let candidates = detector().detect(for: AppIdentity(appURL: appURL))

        XCTAssertTrue(candidates.isEmpty)
    }

    func testSearchURLIncludesAppIdentityAndOfficialUninstallerTerms() throws {
        let appURL = try makeApp(named: "Sample", bundleID: "com.example.sample")

        let url = OfficialUninstallerSearch.searchURL(for: AppIdentity(appURL: appURL))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try XCTUnwrap(components.queryItems?.first { $0.name == "q" }?.value)

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "duckduckgo.com")
        XCTAssertTrue(query.contains("Sample"))
        XCTAssertTrue(query.contains("mac"))
        XCTAssertTrue(query.contains("official uninstaller"))
        XCTAssertTrue(query.contains("卸载程序"))
    }

    private func detector() -> OfficialUninstallerDetector {
        OfficialUninstallerDetector(
            homeDirectory: homeURL,
            applicationDirectories: [applicationsURL],
            systemApplicationSupportURL: systemApplicationSupportURL
        )
    }

    private func makeApp(named name: String, bundleID: String) throws -> URL {
        let appURL = applicationsURL.appending(path: "\(name).app", directoryHint: .isDirectory)
        let contentsURL = appURL.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleExecutable": name,
            "CFBundleShortVersionString": "1.0"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsURL.appending(path: "Info.plist"))
        return appURL
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func makeFile(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test".utf8).write(to: url)
    }

    private func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().path == rhs.resolvingSymlinksInPath().path
    }
}
