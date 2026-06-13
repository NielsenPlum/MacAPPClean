import XCTest
@testable import MacAppClean

final class KnowledgeBaseProviderTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "MacAppCleanTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testConfiguredRemoteURLAcceptsOnlyTrimmedHTTPSURL() {
        defaults.set("  https://example.com/rules.json  ", forKey: KnowledgeBaseProvider.remoteRulesURLKey)

        let provider = KnowledgeBaseProvider(defaults: defaults)

        XCTAssertEqual(provider.configuredRemoteURL()?.absoluteString, "https://example.com/rules.json")
    }

    func testConfiguredRemoteURLRejectsNonHTTPSURL() {
        defaults.set("http://example.com/rules.json", forKey: KnowledgeBaseProvider.remoteRulesURLKey)

        let provider = KnowledgeBaseProvider(defaults: defaults)

        XCTAssertNil(provider.configuredRemoteURL())
    }

    func testLoadKnowledgeBaseReturnsBundledRulesWithoutRemoteURL() async {
        let provider = KnowledgeBaseProvider(defaults: defaults)

        let snapshot = await provider.loadKnowledgeBase()

        XCTAssertEqual(snapshot.version, "bundled-2")
        XCTAssertTrue(snapshot.rules.contains { $0.id == "com.google.chrome" })
    }
}
