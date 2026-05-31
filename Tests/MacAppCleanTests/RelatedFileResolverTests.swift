import XCTest
@testable import MacAppClean

final class RelatedFileResolverTests: XCTestCase {
    private var rootURL: URL!
    private var homeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "MacAppCleanTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        homeURL = rootURL.appending(path: "Home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
        homeURL = nil
        try super.tearDownWithError()
    }

    func testResolverCombinesKnowledgeBaseAndHeuristicMatchesWithRiskDefaults() throws {
        let appURL = try makeApp(
            named: "Sample",
            bundleID: "com.example.Sample",
            displayName: "Sample"
        )
        let supportURL = homeURL.appending(path: "Library/Application Support/Sample")
        let cacheURL = homeURL.appending(path: "Library/Caches/com.example.Sample")
        let containerURL = homeURL.appending(path: "Library/Containers/com.example.Sample")
        let preferencesURL = homeURL.appending(path: "Library/Preferences/com.example.Sample.plist")
        try makeDirectory(supportURL)
        try makeDirectory(cacheURL)
        try makeDirectory(containerURL)
        try makeFile(preferencesURL)

        let snapshot = KnowledgeBaseSnapshot(
            version: "test",
            source: .bundled,
            rules: [
                KnowledgeBaseRule(
                    id: "com.example.Sample",
                    name: "Sample",
                    match: .init(bundleIDs: ["com.example.Sample"], names: []),
                    paths: [
                        .init(template: "$APP_SUPPORT/Sample", category: .support, risk: .medium),
                        .init(template: "$PREFERENCES/com.example.Sample.plist", category: .preferences)
                    ]
                )
            ]
        )

        let candidates = RelatedFileResolver(
            knowledgeBase: snapshot,
            homeDirectory: homeURL
        ).resolveCandidates(for: AppIdentity(appURL: appURL))

        XCTAssertTrue(candidates.contains { $0.url.path == supportURL.path && $0.matchedBy.contains("knowledge-base:com.example.Sample") })
        XCTAssertTrue(candidates.contains { $0.url.path == cacheURL.path && $0.category == .cache && $0.risk == .low && $0.defaultSelected })
        XCTAssertTrue(candidates.contains { $0.url.path == containerURL.path && $0.category == .userData && $0.risk == .high && !$0.defaultSelected })
        XCTAssertTrue(candidates.contains { $0.url.path == preferencesURL.path && $0.category == .preferences })
    }

    func testResolverDeduplicatesNestedMatches() throws {
        let appURL = try makeApp(
            named: "Nested",
            bundleID: "com.example.Nested",
            displayName: "Nested"
        )
        let parentURL = homeURL.appending(path: "Library/Application Support/Nested")
        let childURL = parentURL.appending(path: "Cache")
        try makeDirectory(childURL)

        let snapshot = KnowledgeBaseSnapshot(
            version: "test",
            source: .bundled,
            rules: [
                KnowledgeBaseRule(
                    id: "com.example.Nested",
                    name: "Nested",
                    match: .init(bundleIDs: ["com.example.Nested"], names: []),
                    paths: [
                        .init(template: "$APP_SUPPORT/Nested", category: .support),
                        .init(template: "$APP_SUPPORT/Nested/Cache", category: .cache, risk: .low)
                    ]
                )
            ]
        )

        let candidates = RelatedFileResolver(
            knowledgeBase: snapshot,
            homeDirectory: homeURL
        ).resolveCandidates(for: AppIdentity(appURL: appURL))

        XCTAssertEqual(candidates.filter { $0.url.path == parentURL.path || $0.url.path == childURL.path }.count, 1)
        XCTAssertTrue(candidates.contains { $0.url.path == parentURL.path })
    }

    private func makeApp(named name: String, bundleID: String, displayName: String) throws -> URL {
        let appURL = homeURL.appending(path: "Applications/\(name).app", directoryHint: .isDirectory)
        let contentsURL = appURL.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleDisplayName": displayName,
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
}
