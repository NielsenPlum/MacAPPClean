import Foundation

final class RelatedFileResolver {
    private let knowledgeBase: KnowledgeBaseSnapshot
    private let fileManager: FileManager
    private let homeDirectory: URL

    init(
        knowledgeBase: KnowledgeBaseSnapshot,
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) {
        self.knowledgeBase = knowledgeBase
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
    }

    func resolveCandidates(for identity: AppIdentity) -> [RelatedFileCandidate] {
        var candidates: [RelatedFileCandidate] = []

        for rule in knowledgeBase.rules where rule.matches(identity) {
            appendRuleCandidates(rule, identity: identity, to: &candidates)
        }

        appendHeuristicCandidates(identity: identity, to: &candidates)

        if identity.isSteam {
            appendSteamDynamicCandidates(identity: identity, to: &candidates)
        }

        return deduplicate(candidates)
    }

    private func appendRuleCandidates(_ rule: KnowledgeBaseRule, identity: AppIdentity, to candidates: inout [RelatedFileCandidate]) {
        for path in rule.paths {
            for url in existingURLs(matching: path.template, identity: identity) {
                candidates.append(RelatedFileCandidate(
                    url: url,
                    category: path.category.fileCategory,
                    matchedBy: ["knowledge-base:\(rule.id)", "template:\(path.template)"],
                    risk: path.risk,
                    defaultSelected: path.defaultSelected
                ))
            }
        }
    }

    private func appendHeuristicCandidates(identity: AppIdentity, to candidates: inout [RelatedFileCandidate]) {
        guard let bundleID = identity.bundleID else { return }

        let appName = identity.appURL.deletingPathExtension().lastPathComponent
        let paths: [HeuristicPath] = [
            .init("$APP_SUPPORT/\(appName)", .support),
            .init("$APP_SUPPORT/\(bundleID)", .support),
            .init("$CACHES/\(bundleID)", .cache, risk: .low),
            .init("$CACHES/\(appName)", .cache, risk: .low),
            .init("$PREFERENCES/\(bundleID).plist", .preferences),
            .init("$PREFERENCES/ByHost/\(bundleID).*", .preferences),
            .init("$LOGS/\(appName)", .log, risk: .low),
            .init("$LOGS/DiagnosticReports/\(appName)*", .log, risk: .low),
            .init("$APP_SUPPORT/CrashReporter/\(appName)*", .log, risk: .low),
            .init("$HTTP_STORAGES/\(bundleID)", .cache, risk: .low),
            .init("$HTTP_STORAGES/\(bundleID).binarycookies", .cache, risk: .low),
            .init("$WEBKIT/\(bundleID)", .cache, risk: .low),
            .init("$SAVED_STATE/\(bundleID).savedState", .support),
            .init("$APPLICATION_SCRIPTS/\(bundleID)", .support),
            .init("$CONTAINERS/\(bundleID)", .userData, risk: .high, defaultSelected: false),
            .init("$GROUP_CONTAINERS/\(bundleID)", .userData, risk: .high, defaultSelected: false),
            .init("$SYSTEM_APP_SUPPORT/\(appName)", .support, risk: .medium, defaultSelected: false),
            .init("$SYSTEM_APP_SUPPORT/\(bundleID)", .support, risk: .medium, defaultSelected: false),
            .init("$SYSTEM_APP_SUPPORT/CrashReporter/\(appName)*", .log, risk: .low, defaultSelected: false),
            .init("$SYSTEM_CACHES/\(bundleID)", .cache, risk: .low, defaultSelected: false),
            .init("$SYSTEM_PREFERENCES/\(bundleID).plist", .preferences, risk: .medium, defaultSelected: false),
            .init("$SYSTEM_LAUNCH_AGENTS/\(bundleID)*.plist", .launchAgent, risk: .medium, defaultSelected: false),
            .init("$SYSTEM_LAUNCH_DAEMONS/\(bundleID)*.plist", .launchAgent, risk: .high, defaultSelected: false),
            .init("$PRIVILEGED_HELPER_TOOLS/\(bundleID)*", .launchAgent, risk: .high, defaultSelected: false),
            .init("$PKG_RECEIPTS/\(bundleID)*.bom", .leftover, risk: .medium, defaultSelected: false),
            .init("$PKG_RECEIPTS/\(bundleID)*.plist", .leftover, risk: .medium, defaultSelected: false),
        ]

        for path in paths {
            if identity.isSteam && path.template == "$APP_SUPPORT/\(appName)" {
                continue
            }

            for url in existingURLs(matching: path.template, identity: identity) {
                candidates.append(RelatedFileCandidate(
                    url: url,
                    category: path.category,
                    matchedBy: ["heuristic:\(path.template)"],
                    risk: path.risk,
                    defaultSelected: path.defaultSelected
                ))
            }
        }
    }

    private func appendSteamDynamicCandidates(identity: AppIdentity, to candidates: inout [RelatedFileCandidate]) {
        let home = homeDirectory
        let defaultSteamApps = home.appending(path: "Library/Application Support/Steam/steamapps")

        for library in steamLibraryFolders(defaultSteamApps: defaultSteamApps) {
            let steamAppsURL = library.appending(path: "steamapps")
            if fileManager.fileExists(atPath: steamAppsURL.path) {
                candidates.append(RelatedFileCandidate(
                    url: steamAppsURL,
                    category: .gameContent,
                    matchedBy: ["steam-libraryfolders.vdf"],
                    risk: .high,
                    defaultSelected: true
                ))
            }
        }

        for launcher in steamGameLaunchers(in: home.appending(path: "Applications")) {
            candidates.append(RelatedFileCandidate(
                url: launcher,
                category: .gameContent,
                matchedBy: ["steam-game-launcher"],
                risk: .high,
                defaultSelected: true
            ))
        }
    }

    private func steamLibraryFolders(defaultSteamApps: URL) -> [URL] {
        let libraryFile = defaultSteamApps.appending(path: "libraryfolders.vdf")
        guard let contents = try? String(contentsOf: libraryFile) else { return [] }

        var folders: [URL] = []
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\"path\"") else { continue }
            let parts = trimmed.components(separatedBy: "\"").filter { !$0.isEmpty && $0 != "path" }
            guard let path = parts.last else { continue }
            folders.append(URL(fileURLWithPath: path.replacingOccurrences(of: "\\\\", with: "\\")))
        }
        return folders
    }

    private func steamGameLaunchers(in applicationsFolder: URL) -> [URL] {
        guard fileManager.fileExists(atPath: applicationsFolder.path),
              let enumerator = fileManager.enumerator(at: applicationsFolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var launchers: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            enumerator.skipDescendants()

            let runScript = url.appending(path: "Contents/MacOS/run.sh")
            guard let script = try? String(contentsOf: runScript),
                  script.localizedCaseInsensitiveContains("steam://run") || script.localizedCaseInsensitiveContains("steam://rungameid") else {
                continue
            }
            launchers.append(url)
        }
        return launchers
    }

    private func existingURLs(matching template: String, identity: AppIdentity) -> [URL] {
        guard let expanded = expand(template: template, identity: identity) else { return [] }

        if !template.contains("*") && !template.contains("?") {
            return fileManager.fileExists(atPath: expanded.path) ? [expanded] : []
        }

        let parentURL = expanded.deletingLastPathComponent()
        let pattern = expanded.lastPathComponent
        guard fileManager.fileExists(atPath: parentURL.path),
              let urls = try? fileManager.contentsOfDirectory(
                at: parentURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return urls.filter { glob(pattern, matches: $0.lastPathComponent) }
    }

    private func expand(template: String, identity: AppIdentity) -> URL? {
        let home = homeDirectory.path
        let bundleID = identity.bundleID ?? ""
        let appName = identity.appURL.deletingPathExtension().lastPathComponent

        var path = template
        if path == "~" {
            path = home
        } else if path.hasPrefix("~/") {
            path = home + String(path.dropFirst())
        }

        path = path
            .replacingOccurrences(of: "$HOME", with: home)
            .replacingOccurrences(of: "$APP_NAME", with: appName)
            .replacingOccurrences(of: "$BUNDLE_ID", with: bundleID)
            .replacingOccurrences(of: "$APP_SUPPORT", with: "\(home)/Library/Application Support")
            .replacingOccurrences(of: "$CACHES", with: "\(home)/Library/Caches")
            .replacingOccurrences(of: "$PREFERENCES", with: "\(home)/Library/Preferences")
            .replacingOccurrences(of: "$LOGS", with: "\(home)/Library/Logs")
            .replacingOccurrences(of: "$CONTAINERS", with: "\(home)/Library/Containers")
            .replacingOccurrences(of: "$GROUP_CONTAINERS", with: "\(home)/Library/Group Containers")
            .replacingOccurrences(of: "$HTTP_STORAGES", with: "\(home)/Library/HTTPStorages")
            .replacingOccurrences(of: "$WEBKIT", with: "\(home)/Library/WebKit")
            .replacingOccurrences(of: "$SAVED_STATE", with: "\(home)/Library/Saved Application State")
            .replacingOccurrences(of: "$APPLICATION_SCRIPTS", with: "\(home)/Library/Application Scripts")
            .replacingOccurrences(of: "$SYSTEM_LIBRARY", with: "/Library")
            .replacingOccurrences(of: "$SYSTEM_APP_SUPPORT", with: "/Library/Application Support")
            .replacingOccurrences(of: "$SYSTEM_CACHES", with: "/Library/Caches")
            .replacingOccurrences(of: "$SYSTEM_PREFERENCES", with: "/Library/Preferences")
            .replacingOccurrences(of: "$SYSTEM_LAUNCH_AGENTS", with: "/Library/LaunchAgents")
            .replacingOccurrences(of: "$SYSTEM_LAUNCH_DAEMONS", with: "/Library/LaunchDaemons")
            .replacingOccurrences(of: "$PRIVILEGED_HELPER_TOOLS", with: "/Library/PrivilegedHelperTools")
            .replacingOccurrences(of: "$PKG_RECEIPTS", with: "/private/var/db/receipts")

        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private func glob(_ pattern: String, matches value: String) -> Bool {
        var regex = "^"
        for scalar in pattern.unicodeScalars {
            switch scalar {
            case "*":
                regex += ".*"
            case "?":
                regex += "."
            case ".", "\\", "+", "(", ")", "[", "]", "{", "}", "^", "$", "|":
                regex += "\\\(scalar)"
            default:
                regex.unicodeScalars.append(scalar)
            }
        }
        regex += "$"

        return value.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func deduplicate(_ candidates: [RelatedFileCandidate]) -> [RelatedFileCandidate] {
        var result: [RelatedFileCandidate] = []

        for candidate in candidates {
            let path = candidate.url.standardizedFileURL.path
            if result.contains(where: { existing in
                let existingPath = existing.url.standardizedFileURL.path
                return path == existingPath ||
                    path.hasPrefix(existingPath + "/") ||
                    existingPath.hasPrefix(path + "/")
            }) {
                continue
            }
            result.append(candidate)
        }

        return result
    }
}

private struct HeuristicPath {
    var template: String
    var category: ScannedFile.FileCategory
    var risk: RelatedFileRisk
    var defaultSelected: Bool

    init(
        _ template: String,
        _ category: ScannedFile.FileCategory,
        risk: RelatedFileRisk? = nil,
        defaultSelected: Bool? = nil
    ) {
        self.template = template
        self.category = category
        self.risk = risk ?? category.defaultRisk
        self.defaultSelected = defaultSelected ?? (self.risk != .high)
    }
}

private extension KnowledgeBaseRule {
    func matches(_ identity: AppIdentity) -> Bool {
        if let bundleID = identity.bundleID?.lowercased(),
           match.bundleIDs.contains(where: { $0.lowercased() == bundleID }) {
            return true
        }

        let names = [
            identity.name,
            identity.displayName,
            identity.appURL.deletingPathExtension().lastPathComponent,
            identity.executableName ?? ""
        ].map { $0.lowercased() }

        return match.names.contains { ruleName in
            let normalizedRuleName = ruleName.lowercased()
            return names.contains(normalizedRuleName)
        }
    }
}

private extension AppIdentity {
    var isSteam: Bool {
        bundleID?.lowercased() == "com.valvesoftware.steam" ||
            name.localizedCaseInsensitiveContains("steam") ||
            displayName.localizedCaseInsensitiveContains("steam")
    }
}

private extension ScannedFile.FileCategory {
    var defaultRisk: RelatedFileRisk {
        switch self {
        case .cache, .log:
            .low
        case .gameContent, .userData, .largeFile:
            .high
        default:
            .medium
        }
    }
}
