import Foundation

final class AppUpdateChecker {
    private let knowledgeBase: KnowledgeBaseSnapshot
    private let session: URLSession

    init(knowledgeBase: KnowledgeBaseSnapshot) {
        self.knowledgeBase = knowledgeBase

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: configuration)
    }

    func checkUpdates(for items: [CleanerItem]) async -> [CleanerItem] {
        await withTaskGroup(of: (CleanerItem.ID, String?).self) { group in
            let applicationItems = items.filter { $0.section == .applications }

            for item in applicationItems {
                group.addTask { [knowledgeBase, session] in
                    let checker = AppUpdateChecker(knowledgeBase: knowledgeBase, session: session)
                    return (item.id, await checker.latestVersion(for: item))
                }
            }

            var versionsByID: [CleanerItem.ID: String] = [:]
            for await (id, latestVersion) in group {
                if let latestVersion {
                    versionsByID[id] = latestVersion
                }
            }

            return items.map { item in
                var updated = item
                if let latestVersion = versionsByID[item.id],
                   !Self.versionsAreEquivalent(item.version, latestVersion) {
                    updated.latestVersion = latestVersion
                }
                return updated
            }
        }
    }

    private init(knowledgeBase: KnowledgeBaseSnapshot, session: URLSession) {
        self.knowledgeBase = knowledgeBase
        self.session = session
    }

    private func latestVersion(for item: CleanerItem) async -> String? {
        guard let appURL = item.appURL else { return nil }
        let identity = AppIdentity(appURL: appURL)

        if let caskToken = homebrewCaskToken(for: identity),
           let version = await latestHomebrewCaskVersion(token: caskToken) {
            return version
        }

        if let bundleID = identity.bundleID,
           let version = await latestAppStoreVersion(bundleID: bundleID, country: appStoreCountry(for: identity)) {
            return version
        }

        return nil
    }

    private func homebrewCaskToken(for identity: AppIdentity) -> String? {
        if let rule = knowledgeBase.rules.first(where: { matches(rule: $0, identity: identity) }),
           let token = rule.update?.homebrewCaskToken,
           !token.isEmpty {
            return token
        }

        let candidates = [
            identity.name,
            identity.displayName,
            identity.appURL.deletingPathExtension().lastPathComponent
        ].map(Self.normalizedName)

        for candidate in candidates {
            if let token = Self.knownCaskTokens[candidate] {
                return token
            }
        }

        return nil
    }

    private func appStoreCountry(for identity: AppIdentity) -> String {
        if let rule = knowledgeBase.rules.first(where: { matches(rule: $0, identity: identity) }),
           let country = rule.update?.appStoreCountry,
           !country.isEmpty {
            return country
        }
        return Locale.current.region?.identifier ?? "US"
    }

    private func latestHomebrewCaskVersion(token: String) async -> String? {
        guard let url = URL(string: "https://formulae.brew.sh/api/cask/\(token).json") else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true else {
                return nil
            }
            let cask = try JSONDecoder().decode(HomebrewCask.self, from: data)
            let version = cask.version.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !version.isEmpty, version.lowercased() != "latest" else { return nil }
            return version.components(separatedBy: ",").first
        } catch {
            return nil
        }
    }

    private func latestAppStoreVersion(bundleID: String, country: String) async -> String? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "entity", value: "desktopSoftware"),
            URLQueryItem(name: "country", value: country),
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true else {
                return nil
            }
            let lookup = try JSONDecoder().decode(AppStoreLookup.self, from: data)
            return lookup.results.first?.version
        } catch {
            return nil
        }
    }

    private func matches(rule: KnowledgeBaseRule, identity: AppIdentity) -> Bool {
        if let bundleID = identity.bundleID?.lowercased(),
           rule.match.bundleIDs.contains(where: { $0.lowercased() == bundleID }) {
            return true
        }

        let names = [
            identity.name,
            identity.displayName,
            identity.appURL.deletingPathExtension().lastPathComponent,
            identity.executableName ?? ""
        ].map(Self.normalizedName)

        return rule.match.names.map(Self.normalizedName).contains { names.contains($0) }
    }

    private static func versionsAreEquivalent(_ current: String, _ latest: String) -> Bool {
        normalizedVersion(current) == normalizedVersion(latest)
    }

    private static func normalizedVersion(_ version: String) -> String {
        version
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? version.lowercased()
    }

    private static func normalizedName(_ name: String) -> String {
        name
            .replacingOccurrences(of: ".app", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private static let knownCaskTokens: [String: String] = [
        "docker": "docker-desktop",
        "dockerdesktop": "docker-desktop",
        "googlechrome": "google-chrome",
        "chrome": "google-chrome",
        "visualstudiocode": "visual-studio-code",
        "vscode": "visual-studio-code",
        "code": "visual-studio-code",
        "cursor": "cursor",
        "steam": "steam",
        "zoom": "zoom",
        "zoomus": "zoom",
        "slack": "slack",
        "firefox": "firefox",
        "spotify": "spotify",
        "discord": "discord",
        "notion": "notion",
        "figma": "figma",
    ]
}

private struct HomebrewCask: Decodable {
    var version: String
}

private struct AppStoreLookup: Decodable {
    var results: [Result]

    struct Result: Decodable {
        var version: String?
    }
}
