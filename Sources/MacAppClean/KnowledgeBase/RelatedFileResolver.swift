import Foundation

final class RelatedFileResolver {
    private let knowledgeBase: KnowledgeBaseSnapshot
    private let fileManager: FileManager

    init(knowledgeBase: KnowledgeBaseSnapshot, fileManager: FileManager = .default) {
        self.knowledgeBase = knowledgeBase
        self.fileManager = fileManager
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
            guard let url = expand(template: path.template, identity: identity),
                  fileManager.fileExists(atPath: url.path) else {
                continue
            }

            candidates.append(RelatedFileCandidate(
                url: url,
                category: path.category.fileCategory,
                matchedBy: ["knowledge-base:\(rule.id)", "template:\(path.template)"],
                risk: path.risk,
                defaultSelected: path.defaultSelected
            ))
        }
    }

    private func appendHeuristicCandidates(identity: AppIdentity, to candidates: inout [RelatedFileCandidate]) {
        guard let bundleID = identity.bundleID else { return }

        let appName = identity.appURL.deletingPathExtension().lastPathComponent
        let paths: [(String, ScannedFile.FileCategory)] = [
            ("$APP_SUPPORT/\(appName)", .support),
            ("$APP_SUPPORT/\(bundleID)", .support),
            ("$CACHES/\(bundleID)", .cache),
            ("$CACHES/\(appName)", .cache),
            ("$PREFERENCES/\(bundleID).plist", .preferences),
            ("$HOME/Library/Logs/\(appName)", .log),
            ("$HOME/Library/WebKit/\(bundleID)", .cache),
            ("$HOME/Library/Saved Application State/\(bundleID).savedState", .support),
            ("$HOME/Library/Containers/\(bundleID)", .support),
            ("$HOME/Library/Group Containers/\(bundleID)", .support),
        ]

        for (template, category) in paths {
            if identity.isSteam && template == "$APP_SUPPORT/Steam" {
                continue
            }

            guard let url = expand(template: template, identity: identity),
                  fileManager.fileExists(atPath: url.path) else {
                continue
            }

            candidates.append(RelatedFileCandidate(
                url: url,
                category: category,
                matchedBy: ["heuristic:\(template)"],
                risk: category.defaultRisk,
                defaultSelected: true
            ))
        }
    }

    private func appendSteamDynamicCandidates(identity: AppIdentity, to candidates: inout [RelatedFileCandidate]) {
        let home = fileManager.homeDirectoryForCurrentUser
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

    private func expand(template: String, identity: AppIdentity) -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser.path
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

        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
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
