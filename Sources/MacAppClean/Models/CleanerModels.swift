import Foundation
import SwiftUI

enum CleanerSection: String, CaseIterable, Identifiable {
    case applications = "应用程序"
    case startupPrograms = "启动项"
    case extensions = "扩展"
    case remainingFiles = "残留文件"
    case largeFiles = "大文件"
    case updates = "更新"
    case security = "安全"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .applications: "square.grid.2x2"
        case .startupPrograms: "bolt.horizontal"
        case .extensions: "puzzlepiece.extension"
        case .remainingFiles: "folder.badge.questionmark"
        case .largeFiles: "doc.text.magnifyingglass"
        case .updates: "arrow.triangle.2.circlepath"
        case .security: "checkmark.shield"
        }
    }

    var summary: String {
        switch self {
        case .applications: "连同服务文件一起卸载"
        case .startupPrograms: "管理登录项和后台项目"
        case .extensions: "管理浏览器和系统插件"
        case .remainingFiles: "查找旧卸载留下的文件"
        case .largeFiles: "查找占用大量磁盘空间的文件"
        case .updates: "查看可用应用更新"
        case .security: "审计公证状态和权限"
        }
    }
}

enum AppHealth: String {
    case verified = "Apple 已验证"
    case warning = "需要检查"
    case unverified = "未验证"

    var tint: Color {
        switch self {
        case .verified: .green
        case .warning: .orange
        case .unverified: .red
        }
    }
}

struct ScannedFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var size: Int64
    let isDirectory: Bool
    let modDate: Date
    var category: FileCategory
    var matchedBy: [String] = []
    var risk: RelatedFileRisk = .medium
    var defaultSelected: Bool = true

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    enum FileCategory: String, CaseIterable {
        case app = "应用包"
        case support = "支持文件"
        case cache = "缓存"
        case preferences = "偏好设置"
        case log = "日志"
        case launchAgent = "启动代理"
        case extensionFile = "扩展"
        case gameContent = "游戏内容"
        case userData = "用户数据"
        case leftover = "残留"
        case largeFile = "大文件"
        case other = "其他"

        var detailTitle: String {
            switch self {
            case .app: "可执行文件"
            case .support: "应用程序支持"
            case .cache: "缓存"
            case .preferences: "偏好设置"
            case .log: "日志"
            case .launchAgent: "启动代理"
            case .extensionFile: "扩展"
            case .gameContent: "游戏库内容"
            case .userData: "用户数据与截图"
            case .leftover: "残留文件"
            case .largeFile: "大文件"
            case .other: "其他"
            }
        }

        static var uninstallOrder: [ScannedFile.FileCategory] {
            [.app, .gameContent, .userData, .support, .cache, .preferences, .log, .launchAgent, .extensionFile, .leftover, .largeFile, .other]
        }
    }
}

struct CleanerItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var developer: String
    var section: CleanerSection
    var icon: String
    var size: Int64
    var lastUsed: String
    var version: String
    var latestVersion: String?
    var health: AppHealth
    var description: String
    var permissions: [String]
    var files: [ScannedFile]
    var officialUninstallers: [OfficialUninstallerCandidate] = []
    var isSelected: Bool
    var appURL: URL?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var fileCount: Int {
        files.count
    }

    var hasUpdate: Bool {
        latestVersion != nil && latestVersion != version
    }

    static func placeholder(name: String, developer: String, section: CleanerSection, icon: String) -> CleanerItem {
        CleanerItem(
            id: UUID(),
            name: name,
            developer: developer,
            section: section,
            icon: icon,
            size: 0,
            lastUsed: "",
            version: "",
            latestVersion: nil,
            health: .verified,
            description: "",
            permissions: [],
            files: [],
            officialUninstallers: [],
            isSelected: false,
            appURL: nil
        )
    }
}

struct Metric: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var caption: String
    var icon: String
    var tint: Color
}
