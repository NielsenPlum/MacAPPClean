import Foundation

final class OfficialUninstallerDetector {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let applicationDirectories: [URL]
    private let systemApplicationSupportURL: URL

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        applicationDirectories: [URL]? = nil,
        systemApplicationSupportURL: URL = URL(fileURLWithPath: "/Library/Application Support", isDirectory: true)
    ) {
        self.fileManager = fileManager
        let resolvedHome = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.homeDirectory = resolvedHome
        self.applicationDirectories = applicationDirectories ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            resolvedHome.appending(path: "Applications", directoryHint: .isDirectory)
        ]
        self.systemApplicationSupportURL = systemApplicationSupportURL
    }

    func detect(for identity: AppIdentity) -> [OfficialUninstallerCandidate] {
        var candidates: [OfficialUninstallerCandidate] = []

        appendCandidates(
            in: bundleSupportDirectories(for: identity.appURL),
            source: .bundleSupport,
            confidence: .high,
            identity: identity,
            to: &candidates
        )

        appendCandidates(
            in: [identity.appURL.deletingLastPathComponent()],
            source: .siblingDirectory,
            confidence: .medium,
            identity: identity,
            to: &candidates
        )

        appendCandidates(
            in: applicationDirectories,
            source: .applicationsFolder,
            confidence: .medium,
            identity: identity,
            to: &candidates
        )

        appendCandidates(
            in: applicationSupportDirectories(for: identity),
            source: .applicationSupport,
            confidence: .low,
            identity: identity,
            to: &candidates
        )

        return deduplicate(candidates)
            .sorted {
                if $0.confidence != $1.confidence {
                    return $0.confidence > $1.confidence
                }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    private func bundleSupportDirectories(for appURL: URL) -> [URL] {
        let contents = appURL.appending(path: "Contents", directoryHint: .isDirectory)
        return [
            contents.appending(path: "Resources", directoryHint: .isDirectory),
            contents.appending(path: "SharedSupport", directoryHint: .isDirectory),
            contents.appending(path: "Helpers", directoryHint: .isDirectory)
        ]
    }

    private func applicationSupportDirectories(for identity: AppIdentity) -> [URL] {
        let userApplicationSupport = homeDirectory.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let roots = [userApplicationSupport, systemApplicationSupportURL]
        let names = identityTokens(for: identity)

        return roots.flatMap { root in
            names.map { root.appending(path: $0, directoryHint: .isDirectory) }
        }
    }

    private func appendCandidates(
        in directories: [URL],
        source: OfficialUninstallerCandidate.Source,
        confidence: OfficialUninstallerCandidate.Confidence,
        identity: AppIdentity,
        to candidates: inout [OfficialUninstallerCandidate]
    ) {
        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in contents {
                guard let kind = candidateKind(for: url),
                      matchesUninstallerName(url.deletingPathExtension().lastPathComponent, identity: identity) else {
                    continue
                }

                candidates.append(OfficialUninstallerCandidate(
                    url: url,
                    displayName: displayName(for: url),
                    kind: kind,
                    source: source,
                    confidence: confidence
                ))
            }
        }
    }

    private func candidateKind(for url: URL) -> OfficialUninstallerCandidate.Kind? {
        switch url.pathExtension.lowercased() {
        case "app": .app
        case "pkg": .pkg
        default: nil
        }
    }

    private func matchesUninstallerName(_ name: String, identity: AppIdentity) -> Bool {
        let normalizedName = normalize(name)
        let keywords = ["uninstall", "uninstaller", "remove", "卸载"]
        guard keywords.contains(where: { normalizedName.contains(normalize($0)) }) else {
            return false
        }

        return identityTokens(for: identity)
            .map(normalize)
            .filter { !$0.isEmpty }
            .contains { normalizedName.contains($0) }
    }

    private func identityTokens(for identity: AppIdentity) -> [String] {
        var tokens = [
            identity.appURL.deletingPathExtension().lastPathComponent,
            identity.name,
            identity.displayName,
            identity.executableName ?? ""
        ]

        if let bundleID = identity.bundleID {
            tokens.append(bundleID)
            tokens += bundleID
                .components(separatedBy: ".")
                .filter { $0.count >= 3 && $0.lowercased() != "com" }
        }

        return Array(Set(tokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
    }

    private func displayName(for url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
            ?? url.deletingPathExtension().lastPathComponent
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9\\p{Han}]+", with: "", options: .regularExpression)
    }

    private func deduplicate(_ candidates: [OfficialUninstallerCandidate]) -> [OfficialUninstallerCandidate] {
        var seen = Set<String>()
        var result: [OfficialUninstallerCandidate] = []

        for candidate in candidates {
            let path = candidate.url.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            result.append(candidate)
        }

        return result
    }
}
