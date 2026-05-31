import Foundation

enum RuleSource: Hashable {
    case bundled
    case cache
    case remote(URL)
}

enum RelatedFileRisk: String, Codable, CaseIterable, Hashable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: "低风险"
        case .medium: "中风险"
        case .high: "高风险"
        }
    }
}

struct KnowledgeBaseDocument: Codable, Hashable {
    var version: String
    var rules: [KnowledgeBaseRule]
}

struct KnowledgeBaseSnapshot: Hashable {
    var version: String
    var source: RuleSource
    var rules: [KnowledgeBaseRule]

    static let empty = KnowledgeBaseSnapshot(version: "0", source: .bundled, rules: [])
}

struct KnowledgeBaseRule: Codable, Identifiable, Hashable {
    var id: String
    var name: String?
    var match: RuleMatch
    var paths: [RulePath]
    var update: RuleUpdate?

    struct RuleMatch: Codable, Hashable {
        var bundleIDs: [String]
        var names: [String]

        init(bundleIDs: [String] = [], names: [String] = []) {
            self.bundleIDs = bundleIDs
            self.names = names
        }
    }

    struct RulePath: Codable, Hashable {
        var template: String
        var category: RulePathCategory
        var risk: RelatedFileRisk
        var defaultSelected: Bool

        init(template: String, category: RulePathCategory, risk: RelatedFileRisk = .medium, defaultSelected: Bool = true) {
            self.template = template
            self.category = category
            self.risk = risk
            self.defaultSelected = defaultSelected
        }
    }

    struct RuleUpdate: Codable, Hashable {
        var homebrewCaskToken: String?
        var appStoreCountry: String?

        init(homebrewCaskToken: String? = nil, appStoreCountry: String? = nil) {
            self.homebrewCaskToken = homebrewCaskToken
            self.appStoreCountry = appStoreCountry
        }
    }
}

enum RulePathCategory: String, Codable, Hashable {
    case app
    case support
    case cache
    case preferences
    case log
    case launchAgent
    case extensionFile
    case gameContent
    case userData
    case leftover
    case largeFile
    case other

    var fileCategory: ScannedFile.FileCategory {
        switch self {
        case .app: .app
        case .support: .support
        case .cache: .cache
        case .preferences: .preferences
        case .log: .log
        case .launchAgent: .launchAgent
        case .extensionFile: .extensionFile
        case .gameContent: .gameContent
        case .userData: .userData
        case .leftover: .leftover
        case .largeFile: .largeFile
        case .other: .other
        }
    }
}

struct AppIdentity: Hashable {
    var appURL: URL
    var bundleID: String?
    var name: String
    var displayName: String
    var executableName: String?
    var version: String
    var developer: String

    init(appURL: URL) {
        self.appURL = appURL
        let bundle = Bundle(url: appURL)
        let info = bundle?.infoDictionary ?? [:]
        let fallbackName = appURL.deletingPathExtension().lastPathComponent

        bundleID = bundle?.bundleIdentifier
        name = info["CFBundleName"] as? String ?? fallbackName
        displayName = info["CFBundleDisplayName"] as? String ?? name
        executableName = info["CFBundleExecutable"] as? String
        version = info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? "未知"
        developer = info["NSHumanReadableCopyright"] as? String
            ?? info["CFBundleDevelopmentRegion"] as? String
            ?? "未知开发者"
    }
}

struct RelatedFileCandidate: Hashable {
    var url: URL
    var category: ScannedFile.FileCategory
    var matchedBy: [String]
    var risk: RelatedFileRisk
    var defaultSelected: Bool
}
