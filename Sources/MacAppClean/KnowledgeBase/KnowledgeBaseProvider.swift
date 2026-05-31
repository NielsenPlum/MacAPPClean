import Foundation

struct KnowledgeBaseMetadata: Codable, Hashable {
    var sourceURL: URL
    var version: String
    var updatedAt: Date
}

final class KnowledgeBaseProvider {
    static let remoteRulesURLKey = "MacAppClean.knowledgeBase.remoteRulesURL"
    static let localOnlyKey = "MacAppClean.knowledgeBase.localOnly"

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let session: URLSession

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.session = session
    }

    func loadKnowledgeBase() async -> KnowledgeBaseSnapshot {
        let bundled = bundledKnowledgeBase()

        if !defaults.bool(forKey: Self.localOnlyKey),
           let remoteURL = configuredRemoteURL() {
            do {
                return merge(base: bundled, overlay: try await refreshRemoteCache(from: remoteURL))
            } catch {
                if let cached = loadCachedKnowledgeBase() {
                    return merge(base: bundled, overlay: cached)
                }
            }
        }

        if let cached = loadCachedKnowledgeBase() {
            return merge(base: bundled, overlay: cached)
        }

        return bundled
    }

    @discardableResult
    func refreshConfiguredRemoteCache() async throws -> KnowledgeBaseSnapshot {
        guard let remoteURL = configuredRemoteURL() else {
            throw KnowledgeBaseError.missingRemoteURL
        }
        return try await refreshRemoteCache(from: remoteURL)
    }

    func configuredRemoteURL() -> URL? {
        guard let rawValue = defaults.string(forKey: Self.remoteRulesURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty,
              let url = URL(string: rawValue),
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }

    func cachedMetadata() -> KnowledgeBaseMetadata? {
        guard fileManager.fileExists(atPath: cacheMetadataURL.path),
              let data = try? Data(contentsOf: cacheMetadataURL),
              let metadata = try? JSONDecoder.macAppClean.decode(KnowledgeBaseMetadata.self, from: data) else {
            return nil
        }
        return metadata
    }

    private func refreshRemoteCache(from url: URL) async throws -> KnowledgeBaseSnapshot {
        guard url.scheme?.lowercased() == "https" else {
            throw KnowledgeBaseError.remoteURLMustUseHTTPS
        }

        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw KnowledgeBaseError.badHTTPStatus(httpResponse.statusCode)
        }

        let document = try Self.decodeDocument(from: data)
        try writeCache(document: document, sourceURL: url, originalData: data)
        return KnowledgeBaseSnapshot(version: document.version, source: .remote(url), rules: document.rules)
    }

    private func loadCachedKnowledgeBase() -> KnowledgeBaseSnapshot? {
        guard fileManager.fileExists(atPath: cacheDocumentURL.path),
              let data = try? Data(contentsOf: cacheDocumentURL),
              let document = try? Self.decodeDocument(from: data) else {
            return nil
        }
        return KnowledgeBaseSnapshot(version: document.version, source: .cache, rules: document.rules)
    }

    private func writeCache(document: KnowledgeBaseDocument, sourceURL: URL, originalData: Data) throws {
        try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        try originalData.write(to: cacheDocumentURL, options: .atomic)

        let metadata = KnowledgeBaseMetadata(sourceURL: sourceURL, version: document.version, updatedAt: Date())
        let metadataData = try JSONEncoder.macAppClean.encode(metadata)
        try metadataData.write(to: cacheMetadataURL, options: .atomic)
    }

    private static func decodeDocument(from data: Data) throws -> KnowledgeBaseDocument {
        let document = try JSONDecoder.macAppClean.decode(KnowledgeBaseDocument.self, from: data)
        guard !document.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KnowledgeBaseError.invalidDocument
        }
        return document
    }

    private func bundledKnowledgeBase() -> KnowledgeBaseSnapshot {
        let rules: [KnowledgeBaseRule] = [
            KnowledgeBaseRule(
                id: "com.valvesoftware.steam",
                name: "Steam",
                match: .init(bundleIDs: ["com.valvesoftware.steam"], names: ["Steam"]),
                paths: [
                    .init(template: "$APP_SUPPORT/Steam/steamapps", category: .gameContent, risk: .high, defaultSelected: false),
                    .init(template: "$APP_SUPPORT/Steam/userdata", category: .userData, risk: .high, defaultSelected: false),
                    .init(template: "$APP_SUPPORT/Steam/config", category: .support),
                    .init(template: "$APP_SUPPORT/Steam/appcache", category: .cache, risk: .low),
                    .init(template: "$APP_SUPPORT/Steam/logs", category: .log, risk: .low),
                    .init(template: "$HOME/Library/HTTPStorages/com.valvesoftware.steam", category: .cache, risk: .low),
                    .init(template: "$HOME/Library/HTTPStorages/com.valvesoftware.steam.helper", category: .cache, risk: .low),
                    .init(template: "$CACHES/com.valvesoftware.steam.helper", category: .cache, risk: .low),
                    .init(template: "$HOME/Library/Saved Application State/com.valvesoftware.steam.savedState", category: .support),
                    .init(template: "$HOME/Library/Saved Application State/com.valvesoftware.steam.helper.savedState", category: .support),
                    .init(template: "$HOME/Library/LaunchAgents/com.valvesoftware.steamclean.plist", category: .launchAgent),
                ],
                update: .init(homebrewCaskToken: "steam")
            ),
            KnowledgeBaseRule(
                id: "com.docker.docker",
                name: "Docker Desktop",
                match: .init(bundleIDs: ["com.docker.docker", "com.electron.dockerdesktop"], names: ["Docker", "Docker Desktop"]),
                paths: [
                    .init(template: "$HOME/.docker", category: .support, risk: .high, defaultSelected: false),
                    .init(template: "$APP_SUPPORT/Docker Desktop", category: .support),
                    .init(template: "$APP_SUPPORT/com.docker.docker", category: .support),
                    .init(template: "$CACHES/com.docker.docker", category: .cache, risk: .low),
                    .init(template: "$PREFERENCES/com.docker.docker.plist", category: .preferences),
                    .init(template: "$HOME/Library/Group Containers/group.com.docker", category: .support, risk: .high, defaultSelected: false),
                    .init(template: "$HOME/Library/Containers/com.docker.docker", category: .support),
                ],
                update: .init(homebrewCaskToken: "docker-desktop")
            ),
            KnowledgeBaseRule(
                id: "com.google.chrome",
                name: "Google Chrome",
                match: .init(bundleIDs: ["com.google.chrome"], names: ["Google Chrome", "Chrome"]),
                paths: [
                    .init(template: "$APP_SUPPORT/Google/Chrome", category: .userData, risk: .high, defaultSelected: false),
                    .init(template: "$CACHES/Google/Chrome", category: .cache, risk: .low),
                    .init(template: "$CACHES/com.google.Chrome", category: .cache, risk: .low),
                    .init(template: "$PREFERENCES/com.google.Chrome.plist", category: .preferences),
                    .init(template: "$HOME/Library/Saved Application State/com.google.Chrome.savedState", category: .support),
                ],
                update: .init(homebrewCaskToken: "google-chrome")
            ),
            KnowledgeBaseRule(
                id: "com.microsoft.vscode",
                name: "Visual Studio Code",
                match: .init(bundleIDs: ["com.microsoft.vscode"], names: ["Visual Studio Code", "Code"]),
                paths: [
                    .init(template: "$APP_SUPPORT/Code", category: .userData, risk: .high, defaultSelected: false),
                    .init(template: "$HOME/.vscode", category: .userData, risk: .high, defaultSelected: false),
                    .init(template: "$CACHES/com.microsoft.VSCode", category: .cache, risk: .low),
                    .init(template: "$PREFERENCES/com.microsoft.VSCode.plist", category: .preferences),
                ],
                update: .init(homebrewCaskToken: "visual-studio-code")
            ),
            KnowledgeBaseRule(
                id: "com.todesktop.230313mzl4w4u92",
                name: "Cursor",
                match: .init(bundleIDs: ["com.todesktop.230313mzl4w4u92"], names: ["Cursor"]),
                paths: [
                    .init(template: "$APP_SUPPORT/Cursor", category: .userData, risk: .high, defaultSelected: false),
                    .init(template: "$HOME/.cursor", category: .userData, risk: .high, defaultSelected: false),
                    .init(template: "$CACHES/com.todesktop.230313mzl4w4u92", category: .cache, risk: .low),
                    .init(template: "$PREFERENCES/com.todesktop.230313mzl4w4u92.plist", category: .preferences),
                ],
                update: .init(homebrewCaskToken: "cursor")
            ),
            KnowledgeBaseRule(
                id: "us.zoom.xos",
                name: "Zoom",
                match: .init(bundleIDs: ["us.zoom.xos"], names: ["zoom.us", "Zoom"]),
                paths: [
                    .init(template: "$APP_SUPPORT/zoom.us", category: .support),
                    .init(template: "$CACHES/us.zoom.xos", category: .cache, risk: .low),
                    .init(template: "$PREFERENCES/us.zoom.xos.plist", category: .preferences),
                    .init(template: "$HOME/Library/Logs/zoom.us", category: .log, risk: .low),
                ],
                update: .init(homebrewCaskToken: "zoom")
            ),
        ]
        return KnowledgeBaseSnapshot(version: "bundled-2", source: .bundled, rules: rules)
    }

    private func merge(base: KnowledgeBaseSnapshot, overlay: KnowledgeBaseSnapshot) -> KnowledgeBaseSnapshot {
        var mergedRulesByID = Dictionary(uniqueKeysWithValues: base.rules.map { ($0.id, $0) })
        for rule in overlay.rules {
            mergedRulesByID[rule.id] = rule
        }

        return KnowledgeBaseSnapshot(
            version: "\(base.version)+\(overlay.version)",
            source: overlay.source,
            rules: Array(mergedRulesByID.values).sorted { $0.id < $1.id }
        )
    }

    private var cacheDirectoryURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return base.appending(path: "MacAppClean/KnowledgeBase", directoryHint: .isDirectory)
    }

    private var cacheDocumentURL: URL {
        cacheDirectoryURL.appending(path: "rules.json")
    }

    private var cacheMetadataURL: URL {
        cacheDirectoryURL.appending(path: "metadata.json")
    }

    enum KnowledgeBaseError: LocalizedError {
        case missingRemoteURL
        case remoteURLMustUseHTTPS
        case badHTTPStatus(Int)
        case invalidDocument

        var errorDescription: String? {
            switch self {
            case .missingRemoteURL: "请先填写远端规则源 URL。"
            case .remoteURLMustUseHTTPS: "远端规则源必须使用 HTTPS。"
            case .badHTTPStatus(let status): "远端规则源返回 HTTP \(status)。"
            case .invalidDocument: "规则文件缺少有效版本号。"
            }
        }
    }
}

private extension JSONDecoder {
    static var macAppClean: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var macAppClean: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
