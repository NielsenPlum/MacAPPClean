import Foundation

struct OfficialUninstallerCandidate: Identifiable, Hashable {
    var url: URL
    var displayName: String
    var kind: Kind
    var source: Source
    var confidence: Confidence

    var id: String { url.standardizedFileURL.path }

    enum Kind: String, Hashable {
        case app
        case pkg

        var displayName: String {
            switch self {
            case .app: "应用程序"
            case .pkg: "安装器包"
            }
        }
    }

    enum Source: String, Hashable {
        case bundleSupport
        case siblingDirectory
        case applicationsFolder
        case applicationSupport

        var displayName: String {
            switch self {
            case .bundleSupport: "应用包内"
            case .siblingDirectory: "同级目录"
            case .applicationsFolder: "应用程序文件夹"
            case .applicationSupport: "Application Support"
            }
        }
    }

    enum Confidence: Int, Hashable, Comparable {
        case low = 1
        case medium = 2
        case high = 3

        static func < (lhs: Confidence, rhs: Confidence) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
