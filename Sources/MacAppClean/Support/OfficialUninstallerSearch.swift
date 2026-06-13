import Foundation

enum OfficialUninstallerSearch {
    static func searchURL(for identity: AppIdentity) -> URL {
        let query = searchQuery(for: identity)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "duckduckgo.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        return components.url ?? URL(string: "https://duckduckgo.com/")!
    }

    static func searchQuery(for identity: AppIdentity) -> String {
        var terms = [identity.displayName, identity.name]

        if let bundleID = identity.bundleID {
            terms.append(bundleID)
        }

        let appTerms = Array(Set(terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
            .prefix(2)

        return (appTerms + ["mac", "official uninstaller", "卸载程序"]).joined(separator: " ")
    }
}
