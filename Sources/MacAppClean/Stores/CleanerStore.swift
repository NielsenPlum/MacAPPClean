import AppKit
import Foundation
import Observation

@Observable
final class CleanerStore {
    private struct TrashRecord: Codable, Identifiable, Hashable {
        var id = UUID()
        var batchID = UUID()
        var batchName = "已移除项目"
        var originalURL: URL
        var trashURL: URL
        var removedAt: Date
        var restoredAt: Date?
        var size: Int64 = 0

        init(batchID: UUID, batchName: String, originalURL: URL, trashURL: URL, removedAt: Date, size: Int64) {
            self.batchID = batchID
            self.batchName = batchName
            self.originalURL = originalURL
            self.trashURL = trashURL
            self.removedAt = removedAt
            self.size = size
        }

        private enum CodingKeys: String, CodingKey {
            case id, batchID, batchName, originalURL, trashURL, removedAt, restoredAt, size
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            batchID = try container.decodeIfPresent(UUID.self, forKey: .batchID) ?? UUID()
            batchName = try container.decodeIfPresent(String.self, forKey: .batchName) ?? "已移除项目"
            originalURL = try container.decode(URL.self, forKey: .originalURL)
            trashURL = try container.decode(URL.self, forKey: .trashURL)
            removedAt = try container.decodeIfPresent(Date.self, forKey: .removedAt) ?? Date()
            restoredAt = try container.decodeIfPresent(Date.self, forKey: .restoredAt)
            size = try container.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        }

        var isRestorable: Bool {
            let fm = FileManager.default
            return restoredAt == nil &&
                fm.fileExists(atPath: trashURL.path) &&
                !fm.fileExists(atPath: originalURL.path)
        }
    }

    struct DeletedTrashBatch: Identifiable, Hashable {
        var id: UUID
        var name: String
        var removedAt: Date
        var itemCount: Int
        var restorableItemCount: Int
        var restoredItemCount: Int
        var blockedByExistingOriginalCount: Int
        var size: Int64
        var previewPaths: [String]

        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }

        var canRestore: Bool {
            restorableItemCount > 0
        }

        var statusText: String {
            if restorableItemCount == itemCount {
                return "可恢复"
            }
            if restorableItemCount > 0 {
                return "\(restorableItemCount) 项可恢复"
            }
            if restoredItemCount == itemCount {
                return "已恢复"
            }
            if blockedByExistingOriginalCount == itemCount {
                return "原位置已有项目"
            }
            return "仅保留记录"
        }
    }

    private struct InstalledAppIndex {
        var bundleIDs: Set<String> = []
        var names: Set<String> = []
        var vendorTokens: Set<String> = []
    }

    enum SortMode: String, CaseIterable {
        case sizeDesc = "按大小从大到小"
        case sizeAsc = "按大小从小到大"
        case name = "按名称"
        
        var icon: String {
            switch self {
            case .sizeDesc: "arrow.down.to.line.compact"
            case .sizeAsc: "arrow.up.to.line.compact"
            case .name: "textformat.abc"
            }
        }
        
        var next: SortMode {
            switch self {
            case .sizeDesc: .sizeAsc
            case .sizeAsc: .name
            case .name: .sizeDesc
            }
        }
    }
    
    var sortMode: SortMode = .sizeDesc
    var selectedSection: CleanerSection = .applications
    var selectedItemID: CleanerItem.ID?
    var query = ""
    var items: [CleanerItem] = []
    var isScanning = false
    var lastScanSummary = "准备扫描应用程序、资源库、登录项和扩展文件夹。"
    var scanProgress: String = ""
    var cleanupErrorMessage: String?
    var scanAccessMessage: String?
    var restoreErrorMessage: String?
    private var recentTrashRecords: [TrashRecord] = []
    private static let trashRecordsKey = "MacAppClean.recentTrashRecords"

    init() {
        recentTrashRecords = Self.loadRecentTrashRecords()
    }

    var restorableTrashCount: Int {
        recentTrashRecords.filter(\.isRestorable).count
    }

    var deletionHistoryCount: Int {
        recentTrashRecords.count
    }

    var deletedTrashBatches: [DeletedTrashBatch] {
        let grouped = Dictionary(grouping: recentTrashRecords, by: \.batchID)
        return grouped.map { batchID, records in
            let sortedRecords = records.sorted { $0.removedAt < $1.removedAt }
            let restorableCount = records.filter(\.isRestorable).count
            let restoredCount = records.filter { $0.restoredAt != nil }.count
            let blockedCount = records.filter {
                $0.restoredAt == nil &&
                    FileManager.default.fileExists(atPath: $0.trashURL.path) &&
                    FileManager.default.fileExists(atPath: $0.originalURL.path)
            }.count
            return DeletedTrashBatch(
                id: batchID,
                name: sortedRecords.first?.batchName ?? "已移除项目",
                removedAt: sortedRecords.map(\.removedAt).max() ?? Date(),
                itemCount: sortedRecords.count,
                restorableItemCount: restorableCount,
                restoredItemCount: restoredCount,
                blockedByExistingOriginalCount: blockedCount,
                size: sortedRecords.map(\.size).reduce(0, +),
                previewPaths: Array(sortedRecords.map(\.originalURL.path).prefix(3))
            )
        }
        .sorted { $0.removedAt > $1.removedAt }
    }

    var visibleItems: [CleanerItem] {
        items
            .filter { $0.section == selectedSection }
            .filter { item in
                query.isEmpty ||
                item.name.localizedCaseInsensitiveContains(query) ||
                item.developer.localizedCaseInsensitiveContains(query)
            }
            .sorted { a, b in
                switch sortMode {
                case .sizeDesc: a.size > b.size
                case .sizeAsc: a.size < b.size
                case .name: a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            }
    }

    var selectedItem: CleanerItem? {
        guard let selectedItemID else { return visibleItems.first }
        return items.first { $0.id == selectedItemID }
    }

    var selectedSize: Int64 {
        items.filter(\.isSelected).map(\.size).reduce(0, +)
    }

    var selectedCount: Int {
        items.filter(\.isSelected).count
    }

    var totalRecoverable: Int64 {
        items.map(\.size).reduce(0, +)
    }

    var metrics: [Metric] {
        let appCount = items.filter { $0.section == .applications }.count
        let startupCount = items.filter { $0.section == .startupPrograms }.count
        let leftoverCount = items.filter { $0.section == .remainingFiles }.count
        let updateCount = items.filter(\.hasUpdate).count
        return [
            Metric(title: "可释放空间", value: ByteCountFormatter.string(fromByteCount: totalRecoverable, countStyle: .file), caption: "服务文件和残留项", icon: "externaldrive.badge.minus", tint: .blue),
            Metric(title: "已安装应用", value: "\(appCount)", caption: "可执行完整清理", icon: "square.grid.2x2", tint: .indigo),
            Metric(title: "启动负担", value: "\(startupCount)", caption: "发现后台项目", icon: "speedometer", tint: .orange),
            Metric(title: "残留文件", value: "\(leftoverCount)", caption: "来自已卸载应用", icon: "folder.badge.questionmark", tint: .red),
            Metric(title: "可用更新", value: "\(updateCount)", caption: "需要处理的应用", icon: "arrow.down.circle", tint: .purple),
        ]
    }

    // MARK: - Scanning

    func scan() {
        isScanning = true
        items = []
        selectedItemID = nil
        scanProgress = "正在申请文件夹访问权限..."
        lastScanSummary = "正在扫描应用包、缓存、偏好设置、启动代理和浏览器扩展..."

        Task { @MainActor in
            var scanned: [CleanerItem] = []
            let folderAccess = requestProtectedFolderAccessForScan()
            let knowledgeBase = await KnowledgeBaseProvider().loadKnowledgeBase()

            scanProgress = "正在扫描 /Applications..."
            var seenAppPaths = Set<String>()
            scanned += await scanApplicationsDirectory(url: URL(fileURLWithPath: "/Applications"), seenPaths: &seenAppPaths, knowledgeBase: knowledgeBase)
            scanned += await scanApplicationsDirectory(url: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"), seenPaths: &seenAppPaths, knowledgeBase: knowledgeBase)

            scanProgress = "正在扫描启动项..."
            scanned += await scanStartupPrograms()

            scanProgress = "正在扫描扩展..."
            scanned += await scanExtensions()

            scanProgress = "正在扫描残留文件..."
            scanned += await scanLeftovers()

            scanProgress = "正在扫描大文件..."
            scanned += await scanLargeFiles(accessibleDirectoryPaths: folderAccess.accessiblePaths)

            scanProgress = "正在检查安全状态..."
            scanned = await scanSecurity(items: scanned)

            scanProgress = "正在检查更新..."
            scanned = await checkUpdates(items: scanned, knowledgeBase: knowledgeBase)

            scanned = deduplicatedItems(scanned)

            try? await Task.sleep(for: .milliseconds(200))
            self.items = scanned
            self.isScanning = false
            self.scanProgress = ""
            self.lastScanSummary = "扫描完成。在 \(CleanerSection.allCases.count) 个分类中共发现 \(scanned.count) 个项目，预估可释放 \(ByteCountFormatter.string(fromByteCount: totalRecoverable, countStyle: .file))。"
            if !folderAccess.deniedNames.isEmpty {
                self.scanAccessMessage = "以下文件夹没有授权，本次已跳过对应的大文件扫描：\(folderAccess.deniedNames.joined(separator: "、"))。\n\n如需以后不再反复确认，请在系统设置 > 隐私与安全性 > 文件和文件夹中允许 MacAppClean 访问这些目录；本地开发构建还需要保持稳定签名。"
            }
        }
    }

    private func requestProtectedFolderAccessForScan() -> (accessiblePaths: Set<String>, deniedNames: [String]) {
        let fm = FileManager.default
        var accessiblePaths = Set<String>()
        var deniedNames: [String] = []

        for folder in protectedScanFolders() {
            guard fm.fileExists(atPath: folder.url.path) else { continue }

            do {
                _ = try fm.contentsOfDirectory(
                    at: folder.url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                accessiblePaths.insert(folder.url.path)
            } catch {
                deniedNames.append(folder.name)
            }
        }

        return (accessiblePaths, deniedNames)
    }

    private func protectedScanFolders() -> [(name: String, url: URL)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ("下载", home.appending(path: "Downloads")),
            ("桌面", home.appending(path: "Desktop")),
            ("文稿", home.appending(path: "Documents")),
        ]
    }

    // MARK: - Directory Size Calculator

    /// Recursively calculate real disk usage for a URL (works for both files and directories).
    /// Sparse files can report a very large logical size, so prefer allocated bytes.
    private func directoryTotalSize(url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            return fileDiskUsage(url: url)
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey,
            .totalFileSizeKey,
        ]
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants, .skipsHiddenFiles]) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += fileDiskUsage(url: fileURL)
        }
        return total
    }

    private func fileDiskUsage(url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey,
            .totalFileSizeKey,
        ]

        if let values = try? url.resourceValues(forKeys: keys) {
            if let allocatedSize = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
                return Int64(allocatedSize)
            }
            if let logicalSize = values.totalFileSize ?? values.fileSize {
                return Int64(logicalSize)
            }
        }

        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    // MARK: - App Info Cache

    private var appInfoCache: [String: (version: String?, lastUsed: Date?, developer: String?)] = [:]

    private func getAppInfo(at url: URL) -> (version: String, lastUsed: String, developer: String) {
        let key = url.path
        if let cached = appInfoCache[key] {
            return (cached.version ?? "未知", cached.lastUsed?.relativeFormatted ?? "未知", cached.developer ?? "未知开发者")
        }

        var version = "未知"
        var developer = "未知开发者"
        var lastUsed: Date? = nil

        if let bundle = Bundle(url: url) {
            version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? bundle.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
            developer = bundle.infoDictionary?["NSHumanReadableCopyright"] as? String
                ?? bundle.infoDictionary?["CFBundleDevelopmentRegion"] as? String
                ?? "未知开发者"
        }

        if let bundleID = Bundle(url: url)?.bundleIdentifier {
            let prefsURL = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Preferences")
                .appending(path: "\(bundleID).plist")
            if let attrs = try? FileManager.default.attributesOfItem(atPath: prefsURL.path),
               let modDate = attrs[.modificationDate] as? Date {
                lastUsed = modDate
            }
        }

        appInfoCache[key] = (version, lastUsed, developer)
        return (version, lastUsed?.relativeFormatted ?? "未知", developer)
    }

    // MARK: - Application Scanner

    private func scanApplicationsDirectory(url: URL, seenPaths: inout Set<String>, knowledgeBase: KnowledgeBaseSnapshot) async -> [CleanerItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [] }

        // seenPaths is shared via inout
        var results: [CleanerItem] = []

        // BFS-style recursive scan using contentsOfDirectory (not enumerator)
        var dirsToScan = [url]
        while !dirsToScan.isEmpty {
            let dir = dirsToScan.removeFirst()
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isApplicationKey], options: .skipsHiddenFiles) else {
                continue
            }
            for itemURL in contents {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDir) else { continue }

                if isDir.boolValue {
                    if itemURL.pathExtension == "app" {
                        // Resolve symlinks and deduplicate
                        let resolved = itemURL.resolvingSymlinksInPath()
                        guard seenPaths.insert(resolved.path).inserted else { continue }

                        let name = (try? resolved.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? resolved.deletingPathExtension().lastPathComponent
                        let (version, lastUsed, developer) = getAppInfo(at: resolved)
                        let relatedFiles = findRelatedFiles(for: resolved, knowledgeBase: knowledgeBase)
                        let appSize = directoryTotalSize(url: resolved)
                        let totalSize = appSize + relatedFiles.map(\.size).reduce(0, +)

                        results.append(CleanerItem(
                            id: UUID(),
                            name: name,
                            developer: developer,
                            section: .applications,
                            icon: appIcon(for: resolved),
                            size: totalSize,
                            lastUsed: lastUsed,
                            version: version,
                            latestVersion: nil,
                            health: checkCodeSignature(url: resolved),
                            description: "完整的应用包及其支持文件。",
                            permissions: extractPermissions(from: resolved),
                            files: relatedFiles,
                            isSelected: false,
                            appURL: resolved
                        ))
                    } else {
                        // Regular directory - add to scan queue
                        dirsToScan.append(itemURL)
                    }
                }
            }
        }

        return results
    }

    private func findRelatedFiles(for appURL: URL, knowledgeBase: KnowledgeBaseSnapshot) -> [ScannedFile] {
        var files: [ScannedFile] = []
        let identity = AppIdentity(appURL: appURL)
        let resolver = RelatedFileResolver(knowledgeBase: knowledgeBase)

        for candidate in resolver.resolveCandidates(for: identity) {
            appendRelatedFile(candidate, to: &files)
        }

        return files
    }

    private func appendRelatedFile(_ candidate: RelatedFileCandidate, to files: inout [ScannedFile]) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: candidate.url.path) else { return }

        var isDir: ObjCBool = false
        fm.fileExists(atPath: candidate.url.path, isDirectory: &isDir)
        let size = directoryTotalSize(url: candidate.url)
        let modDate = (try? candidate.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        files.append(ScannedFile(
            url: candidate.url,
            size: size,
            isDirectory: isDir.boolValue,
            modDate: modDate,
            category: candidate.category,
            matchedBy: candidate.matchedBy,
            risk: candidate.risk,
            defaultSelected: candidate.defaultSelected
        ))
    }

    // MARK: - Startup Programs Scanner

    private func scanStartupPrograms() async -> [CleanerItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var results: [CleanerItem] = []

        let launchAgentURL = home.appending(path: "Library/LaunchAgents")
        guard fm.fileExists(atPath: launchAgentURL.path),
              let files = try? fm.contentsOfDirectory(at: launchAgentURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return results
        }

        for file in files where file.pathExtension == "plist" {
            guard let dict = NSDictionary(contentsOf: file) as? [String: Any] else { continue }

            let label = dict["Label"] as? String ?? file.deletingPathExtension().lastPathComponent
            let program = dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first ?? label

            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: program, isDirectory: &isDir)
            let fileSize = directoryTotalSize(url: file)

            let scannedFiles: [ScannedFile] = [
                ScannedFile(url: file, size: fileSize, isDirectory: false, modDate: (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date(), category: .launchAgent)
            ]

            let item = CleanerItem(
                id: UUID(),
                name: label,
                developer: exists ? (program as NSString).lastPathComponent : "已移除",
                section: .startupPrograms,
                icon: "bolt.circle",
                size: fileSize,
                lastUsed: "登录时运行",
                version: "-",
                latestVersion: nil,
                health: exists ? .verified : .warning,
                description: "启动代理：\(program)",
                permissions: ["后台运行"],
                files: scannedFiles,
                isSelected: false,
                appURL: file
            )
            results.append(item)
        }

        return results
    }

    // MARK: - Extensions Scanner

    private func scanExtensions() async -> [CleanerItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var results: [CleanerItem] = []

        // Safari Extensions
        let safariExtPath = home.appending(path: "Library/Safari/Extensions")
        if fm.fileExists(atPath: safariExtPath.path),
           let extFiles = try? fm.contentsOfDirectory(at: safariExtPath, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for ext in extFiles where ext.pathExtension == "safariextz" {
                let name = ext.deletingPathExtension().lastPathComponent
                let extSize = directoryTotalSize(url: ext)
                let modDate = (try? ext.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                results.append(CleanerItem(
                    id: UUID(), name: name, developer: "Safari", section: .extensions,
                    icon: "safari", size: extSize, lastUsed: modDate.relativeFormatted,
                    version: "-", health: .verified, description: "Safari 浏览器扩展",
                    permissions: ["网页内容"], files: [ScannedFile(url: ext, size: extSize, isDirectory: false, modDate: modDate, category: .extensionFile)],
                    isSelected: false, appURL: ext
                ))
            }
        }

        // System Extensions
        let sysExtPath = URL(fileURLWithPath: "/Library/Extensions")
        if fm.fileExists(atPath: sysExtPath.path),
           let kextFiles = try? fm.contentsOfDirectory(at: sysExtPath, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for kext in kextFiles where kext.pathExtension == "kext" {
                let name = kext.deletingPathExtension().lastPathComponent
                let kextSize = directoryTotalSize(url: kext)
                results.append(CleanerItem(
                    id: UUID(), name: name, developer: "系统", section: .extensions,
                    icon: "puzzlepiece.extension", size: kextSize, lastUsed: "-",
                    version: "-", health: .verified, description: "系统扩展 / 内核扩展",
                    permissions: ["系统"], files: [],
                    isSelected: false, appURL: kext
                ))
            }
        }

        return results
    }

    // MARK: - Leftovers Scanner

    private func scanLeftovers() async -> [CleanerItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var results: [CleanerItem] = []

        let installedApps = installedAppIndex()

        let libraryDirs = [
            home.appending(path: "Library/Application Support"),
            home.appending(path: "Library/Caches"),
            home.appending(path: "Library/Preferences"),
            home.appending(path: "Library/Logs"),
            home.appending(path: "Library/Containers"),
            home.appending(path: "Library/WebKit"),
            home.appending(path: "Library/Saved Application State"),
        ]

        for libDir in libraryDirs {
            guard fm.fileExists(atPath: libDir.path),
                  let contents = try? fm.contentsOfDirectory(at: libDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
                continue
            }

            for item in contents {
                let itemName = item.lastPathComponent
                let possibleBundleID = itemName.replacingOccurrences(of: ".plist", with: "")
                    .replacingOccurrences(of: ".savedState", with: "")
                if shouldIgnoreLeftoverArtifact(possibleBundleID, installedApps: installedApps) { continue }
                if possibleBundleID.hasPrefix("com.apple.") { continue }

                let itemSize = directoryTotalSize(url: item)
                if itemSize < 1024 * 10 { continue } // Skip tiny files

                let modDate = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                var isDir: ObjCBool = false
                fm.fileExists(atPath: item.path, isDirectory: &isDir)

                let appName = possibleBundleID
                    .replacingOccurrences(of: "^com\\.", with: "", options: .regularExpression)
                    .components(separatedBy: ".").last ?? possibleBundleID

                results.append(CleanerItem(
                    id: UUID(), name: appName, developer: "未知开发者", section: .remainingFiles,
                    icon: "folder.badge.minus", size: itemSize, lastUsed: modDate.relativeFormatted,
                    version: "-", health: .warning,
                    description: "来自已移除应用的残留文件。原始应用已不存在，建议清理以释放空间。",
                    permissions: [],
                    files: [ScannedFile(url: item, size: itemSize, isDirectory: isDir.boolValue, modDate: modDate, category: .leftover)],
                    isSelected: false, appURL: item
                ))
            }
        }

        return results
    }

    // MARK: - Large Files Scanner

    private func scanLargeFiles(accessibleDirectoryPaths: Set<String>) async -> [CleanerItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var results: [CleanerItem] = []

        let downloadURL = home.appending(path: "Downloads")
        let desktopURL = home.appending(path: "Desktop")
        let documentsURL = home.appending(path: "Documents")

        let dirsToScan = [downloadURL, desktopURL, documentsURL]

        for dir in dirsToScan {
            guard accessibleDirectoryPaths.contains(dir.path) else { continue }

            let keys: [URLResourceKey] = [
                .isRegularFileKey,
                .contentModificationDateKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey,
                .fileSizeKey,
                .totalFileSizeKey,
            ]
            guard fm.fileExists(atPath: dir.path),
                  let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants, .skipsHiddenFiles]) else {
                continue
            }

            var largeFiles: [ScannedFile] = []

            while let fileURL = enumerator.nextObject() as? URL {
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true,
                      fileDiskUsage(url: fileURL) > 100_000_000 else {
                    continue
                }

                let fileSize = fileDiskUsage(url: fileURL)
                let modDate = values.contentModificationDate ?? Date()
                largeFiles.append(ScannedFile(
                    url: fileURL,
                    size: fileSize,
                    isDirectory: false,
                    modDate: modDate,
                    category: .largeFile
                ))

                if largeFiles.count >= 50 { break }
            }

            if !largeFiles.isEmpty {
                let totalSize = largeFiles.map(\.size).reduce(0, +)
                let dirName: String
                switch dir.path {
                case downloadURL.path: dirName = "下载"
                case desktopURL.path: dirName = "桌面"
                case documentsURL.path: dirName = "文稿"
                default: dirName = dir.lastPathComponent
                }

                results.append(CleanerItem(
                    id: UUID(), name: "\(dirName) 大文件", developer: "本地",
                    section: .largeFiles, icon: "doc.text.magnifyingglass",
                    size: totalSize, lastUsed: "今天",
                    version: "-", health: .verified,
                    description: "\(dirName) 文件夹中大于 100MB 的文件。",
                    permissions: [], files: largeFiles,
                    isSelected: false, appURL: dir
                ))
            }
        }

        return results
    }

    // MARK: - Security & Code Signing

    private func checkCodeSignature(url: URL) -> AppHealth {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", url.path]

        let stderr = Pipe()
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if output.contains("not signed") || output.contains("no identity") {
                return .unverified
            }
            if output.contains("adhoc") {
                return .warning
            }
            if output.contains("Apple Distribution") || output.contains("Apple Development") || output.contains("Developer ID") {
                return .verified
            }
            return process.terminationStatus == 0 ? .verified : .warning
        } catch {
            return .warning
        }
    }

    private func scanSecurity(items: [CleanerItem]) async -> [CleanerItem] {
        var results = items

        for item in items where item.section == .applications || item.section == .extensions {
            if let appURL = item.appURL, item.health == .verified {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                process.arguments = ["-dvv", appURL.path]

                let stderr = Pipe()
                process.standardError = stderr

                if (try? process.run()) != nil {
                    process.waitUntilExit()
                    let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                    if output.contains("flags=0x") && !output.contains("runtime") && !output.contains("hardened") {
                        if let idx = results.firstIndex(where: { $0.id == item.id }) {
                            results[idx].health = .warning
                        }
                    }
                }
            }
        }

        return results
    }

    // MARK: - Update Checker (stub)

    private func checkUpdates(items: [CleanerItem], knowledgeBase: KnowledgeBaseSnapshot) async -> [CleanerItem] {
        await AppUpdateChecker(knowledgeBase: knowledgeBase).checkUpdates(for: items)
    }

    // MARK: - Helpers

    private func deduplicatedItems(_ items: [CleanerItem]) -> [CleanerItem] {
        var deduped: [CleanerItem] = []
        var seenKeys: [String: Int] = [:]

        for item in items {
            let key = deduplicationKey(for: item)
            if let existingIndex = seenKeys[key] {
                if item.size > deduped[existingIndex].size {
                    deduped[existingIndex] = item
                }
            } else {
                seenKeys[key] = deduped.count
                deduped.append(item)
            }
        }

        return deduped
    }

    private func deduplicationKey(for item: CleanerItem) -> String {
        if let appURL = item.appURL {
            return "\(item.section.rawValue):\(appURL.resolvingSymlinksInPath().standardizedFileURL.path)"
        }

        if let firstFile = item.files.first {
            return "\(item.section.rawValue):\(firstFile.url.resolvingSymlinksInPath().standardizedFileURL.path)"
        }

        return "\(item.section.rawValue):\(item.name):\(item.developer)"
    }

    private func installedAppIndex() -> InstalledAppIndex {
        var index = InstalledAppIndex()
        let fm = FileManager.default

        for appDir in [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appending(path: "Applications")] {
            guard fm.fileExists(atPath: appDir.path) else { continue }

            var dirsToScan = [appDir]
            while !dirsToScan.isEmpty {
                let dir = dirsToScan.removeFirst()
                guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) else {
                    continue
                }

                for url in contents {
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }

                    if url.pathExtension == "app" {
                        addInstalledApp(url, to: &index)
                    } else {
                        dirsToScan.append(url)
                    }
                }
            }
        }

        return index
    }

    private func addInstalledApp(_ url: URL, to index: inout InstalledAppIndex) {
        let appName = url.deletingPathExtension().lastPathComponent
        index.names.insert(normalizedArtifactName(appName))

        guard let bundle = Bundle(url: url) else { return }

        if let bundleID = bundle.bundleIdentifier {
            let normalizedBundleID = bundleID.lowercased()
            index.bundleIDs.insert(normalizedBundleID)
            index.vendorTokens.formUnion(bundleVendorTokens(from: normalizedBundleID))
        }

        for key in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
            if let value = bundle.infoDictionary?[key] as? String, !value.isEmpty {
                index.names.insert(normalizedArtifactName(value))
            }
        }
    }

    private func isInstalledAppArtifact(_ artifactName: String, installedApps: InstalledAppIndex) -> Bool {
        let normalizedName = normalizedArtifactName(artifactName)
        if installedApps.names.contains(normalizedName) { return true }
        if installedApps.vendorTokens.contains(normalizedName) { return true }

        let bundleLikeName = artifactName.lowercased()
        return installedApps.bundleIDs.contains { bundleID in
            bundleLikeName == bundleID ||
            bundleLikeName.hasPrefix("\(bundleID).") ||
            bundleID.hasPrefix("\(bundleLikeName).")
        }
    }

    private func shouldIgnoreLeftoverArtifact(_ artifactName: String, installedApps: InstalledAppIndex) -> Bool {
        let normalizedName = normalizedArtifactName(artifactName)
        if ignoredLeftoverArtifactNames.contains(normalizedName) { return true }
        return isInstalledAppArtifact(artifactName, installedApps: installedApps)
    }

    private var ignoredLeftoverArtifactNames: Set<String> {
        [
            "pip",
            "python",
            "python3",
            "node",
            "npm",
            "npx",
            "yarn",
            "pnpm",
            "cargo",
            "rustup",
            "go",
            "gradle",
            "maven",
            "homebrew"
        ]
    }

    private func bundleVendorTokens(from bundleID: String) -> Set<String> {
        let ignoredTokens: Set<String> = ["com", "org", "net", "io", "app", "apps", "mac", "macos", "os", "desktop"]
        return Set(bundleID
            .split(separator: ".")
            .map { normalizedArtifactName(String($0)) }
            .filter { $0.count >= 3 && !ignoredTokens.contains($0) })
    }

    private func normalizedArtifactName(_ name: String) -> String {
        name
            .replacingOccurrences(of: ".plist", with: "")
            .replacingOccurrences(of: ".savedState", with: "")
            .replacingOccurrences(of: ".app", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private func appIcon(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let iconMap: [(String, String)] = [
            ("xcode", "hammer"), ("safari", "safari"), ("chrome", "globe"),
            ("firefox", "flame"), ("terminal", "terminal"), ("finder", "folder"),
            ("mail", "envelope"), ("messages", "message"), ("music", "music.note"),
            ("photos", "photo"), ("preview", "eye"), ("calendar", "calendar"),
            ("notes", "note.text"), ("reminders", "checklist"), ("maps", "map"),
            ("facetime", "video"), ("contacts", "person.crop.square"),
            ("calculator", "calculator"), ("weather", "cloud.sun"),
            ("dictionary", "book"), ("quicktime", "play.rectangle"),
            ("textedit", "doc.text"), ("pages", "doc.richtext"),
            ("numbers", "tablecells"), ("keynote", "presentation"),
            ("pixelmator", "paintbrush.pointed"), ("photoshop", "paintbrush"),
            ("illustrator", "pencil.tip"), ("figma", "pencil.line"),
            ("docker", "shippingbox"), ("slack", "bubble.left.and.bubble.right"),
            ("spotify", "music.note.list"), ("notion", "note.text"),
            ("transmit", "arrow.left.arrow.right.circle"),
            ("things", "checklist"), ("bear", "pawprint"),
        ]

        for (key, icon) in iconMap {
            if name.contains(key) { return icon }
        }

        return "app.dashed"
    }

    private func extractPermissions(from url: URL) -> [String] {
        var perms: [String] = []
        let name = url.deletingPathExtension().lastPathComponent.lowercased()

        if name.contains("screen") || name.contains("record") { perms.append("屏幕录制") }
        if name.contains("microphone") || name.contains("zoom") || name.contains("slack") || name.contains("discord") { perms.append("麦克风") }
        if name.contains("photo") || name.contains("pixelmator") || name.contains("affinity") { perms.append("照片") }
        if name.contains("finder") || name.contains("terminal") || name.contains("transmit") { perms.append("文件和文件夹") }

        if perms.isEmpty { perms.append("通知") }

        return perms
    }

    // MARK: - Selection & Actions

    func toggleSelection(_ item: CleanerItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isSelected.toggle()
    }

    func selectAllVisible() {
        let ids = Set(visibleItems.map(\.id))
        for index in items.indices where ids.contains(items[index].id) {
            items[index].isSelected = true
        }
    }

    func clearSelection() {
        for index in items.indices {
            items[index].isSelected = false
        }
    }

    func removeSelected() {
        var removedIDs = Set<CleanerItem.ID>()
        var failures: [String] = []
        var trashRecords: [TrashRecord] = []

        for item in items where item.isSelected {
            var itemFailed = false
            let batchID = UUID()
            let batchName = item.name

            if let appURL = item.appURL {
                if !trashIfNeeded(appURL, failures: &failures, records: &trashRecords, batchID: batchID, batchName: batchName) {
                    itemFailed = true
                    continue
                }
            }

            for file in item.files {
                if !trashIfNeeded(file.url, failures: &failures, records: &trashRecords, batchID: batchID, batchName: batchName) {
                    itemFailed = true
                }
            }

            if !itemFailed {
                removedIDs.insert(item.id)
            }
        }

        items.removeAll { removedIDs.contains($0.id) }
        if selectedItemID.map({ removedIDs.contains($0) }) == true {
            selectedItemID = nil
        }
        rememberTrashRecords(trashRecords)
        publishCleanupFailures(failures)
    }

    func remove(item: CleanerItem, filePaths: Set<String>) {
        guard !filePaths.isEmpty else { return }

        var failures: [String] = []
        var removedPaths = Set<String>()
        var trashRecords: [TrashRecord] = []
        let batchID = UUID()
        let batchName = item.name

        if let appURL = item.appURL, filePaths.contains(appURL.path) {
            if trashIfNeeded(appURL, failures: &failures, records: &trashRecords, batchID: batchID, batchName: batchName) {
                removedPaths.insert(appURL.path)
            } else {
                rememberTrashRecords(trashRecords)
                publishCleanupFailures(failures)
                return
            }
        }

        for file in item.files where filePaths.contains(file.url.path) {
            if trashIfNeeded(file.url, failures: &failures, records: &trashRecords, batchID: batchID, batchName: batchName) {
                removedPaths.insert(file.url.path)
            }
        }

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            let appWasRemoved = item.appURL.map { removedPaths.contains($0.path) } ?? false
            if appWasRemoved || filePaths.count >= item.files.count + (item.appURL == nil ? 0 : 1) {
                if failures.isEmpty {
                    items.remove(at: index)
                    selectedItemID = nil
                } else {
                    items[index].files.removeAll { removedPaths.contains($0.url.path) }
                    items[index].size = max(0, items[index].size - item.files.filter { removedPaths.contains($0.url.path) }.map(\.size).reduce(0, +))
                }
            } else {
                items[index].files.removeAll { removedPaths.contains($0.url.path) }
                items[index].size = max(0, items[index].size - item.files.filter { removedPaths.contains($0.url.path) }.map(\.size).reduce(0, +))
            }
        }

        rememberTrashRecords(trashRecords)
        publishCleanupFailures(failures)
    }

    func restoreLastRemovedItems() {
        guard let batch = deletedTrashBatches.first(where: \.canRestore) else {
            restoreErrorMessage = "没有可恢复的项目。只有通过 MacAppClean 移入废纸篓、且仍在废纸篓中的项目可以恢复。"
            return
        }
        restoreDeletedBatch(id: batch.id)
    }

    func restoreDeletedBatch(id batchID: UUID) {
        let records = recentTrashRecords.filter { $0.batchID == batchID && $0.isRestorable }
        guard !records.isEmpty else {
            restoreErrorMessage = "这个删除记录已经不可恢复；可能已经恢复、被清空废纸篓，或原位置已有同名项目。"
            saveRecentTrashRecords()
            return
        }

        var restoredIDs: [TrashRecord.ID: Date] = [:]
        var failures: [String] = []

        for record in records.reversed() {
            if restore(record, failures: &failures) {
                restoredIDs[record.id] = Date()
            }
        }

        for index in recentTrashRecords.indices {
            if let restoredAt = restoredIDs[recentTrashRecords[index].id] {
                recentTrashRecords[index].restoredAt = restoredAt
            }
        }
        saveRecentTrashRecords()

        if failures.isEmpty {
            let name = records.first?.batchName ?? "项目"
            lastScanSummary = "已从废纸篓恢复 \(name) 的 \(restoredIDs.count) 个项目，删除记录已保留。"
        } else {
            let visibleFailures = failures.prefix(5).joined(separator: "\n")
            let remaining = failures.count > 5 ? "\n以及另外 \(failures.count - 5) 项。" : ""
            restoreErrorMessage = "以下项目未能恢复：\n\(visibleFailures)\(remaining)"
        }
    }

    private func trashIfNeeded(_ url: URL, failures: inout [String], records: inout [TrashRecord], batchID: UUID, batchName: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return true }
        let removedSize = directoryTotalSize(url: url)

        guard quitRunningAppIfNeeded(at: url, failures: &failures) else { return false }

        if let preflightFailure = trashPreflightFailure(for: url) {
            failures.append(preflightFailure)
            return false
        }

        do {
            var resultingTrashURL: NSURL?
            try fm.trashItem(at: url, resultingItemURL: &resultingTrashURL)
            guard !fm.fileExists(atPath: url.path) else { return false }
            if let trashURL = resultingTrashURL as URL? {
                records.append(TrashRecord(batchID: batchID, batchName: batchName, originalURL: url, trashURL: trashURL, removedAt: Date(), size: removedSize))
            }
            return true
        } catch {
            if trashUsingFinder(url) {
                if let trashURL = findTrashItem(named: url.lastPathComponent, removedAfter: Date().addingTimeInterval(-10)) {
                    records.append(TrashRecord(batchID: batchID, batchName: batchName, originalURL: url, trashURL: trashURL, removedAt: Date(), size: removedSize))
                }
                return true
            }

            failures.append("\(failureLabel(for: url))：\(error.localizedDescription)\(trashPermissionHint(for: url))。已尝试通过 Finder 授权移除，但系统仍拒绝。")
            return false
        }
    }

    private func rememberTrashRecords(_ records: [TrashRecord]) {
        guard !records.isEmpty else { return }
        recentTrashRecords.append(contentsOf: records)
        recentTrashRecords = Array(recentTrashRecords.suffix(500))
        saveRecentTrashRecords()
    }

    private func restore(_ record: TrashRecord, failures: inout [String]) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: record.trashURL.path) else { return true }

        if fm.fileExists(atPath: record.originalURL.path) {
            failures.append("\(record.originalURL.lastPathComponent)：原位置已有同名项目，未覆盖。")
            return false
        }

        do {
            try fm.createDirectory(at: record.originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: record.trashURL, to: record.originalURL)
            saveRecentTrashRecords()
            return fm.fileExists(atPath: record.originalURL.path)
        } catch {
            if restoreUsingFinder(record.trashURL), fm.fileExists(atPath: record.originalURL.path) {
                saveRecentTrashRecords()
                return true
            }
            failures.append("\(record.originalURL.lastPathComponent)：\(error.localizedDescription)")
            return false
        }
    }

    private func trashPreflightFailure(for url: URL) -> String? {
        let parentURL = url.deletingLastPathComponent()
        if !FileManager.default.isWritableFile(atPath: parentURL.path) {
            return "\(failureLabel(for: url))：没有写入 \(parentURL.path) 的权限，可能需要管理员授权。"
        }

        return nil
    }

    private func quitRunningAppIfNeeded(at url: URL, failures: inout [String]) -> Bool {
        guard url.pathExtension == "app",
              let bundleID = Bundle(url: url)?.bundleIdentifier else {
            return true
        }

        var runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !runningApps.isEmpty else { return true }

        for app in runningApps {
            app.terminate()
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if runningApps.isEmpty {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        failures.append("\(failureLabel(for: url))：应用仍在运行，已请求退出但未成功，请手动退出后再移除。")
        return false
    }

    private func trashPermissionHint(for url: URL) -> String {
        let parentURL = url.deletingLastPathComponent()
        if !FileManager.default.isWritableFile(atPath: parentURL.path) {
            return "。\(parentURL.path) 不可写，可能需要管理员授权。"
        }
        return ""
    }

    private func trashUsingFinder(_ url: URL) -> Bool {
        let escapedPath = url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"Finder\" to delete POSIX file \"\(escapedPath)\""
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        return process.terminationStatus == 0 && !FileManager.default.fileExists(atPath: url.path)
    }

    private func restoreUsingFinder(_ trashURL: URL) -> Bool {
        let escapedPath = trashURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"Finder\" to put back POSIX file \"\(escapedPath)\""
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func findTrashItem(named fileName: String, removedAfter date: Date) -> URL? {
        let trashURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
        guard let contents = try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return nil
        }

        return contents
            .filter { $0.lastPathComponent == fileName }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
            .first { url in
                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return modDate >= date
            }
    }

    private static func loadRecentTrashRecords() -> [TrashRecord] {
        guard let data = UserDefaults.standard.data(forKey: trashRecordsKey),
              let records = try? JSONDecoder().decode([TrashRecord].self, from: data) else {
            return []
        }
        return Array(records.suffix(500))
    }

    private func saveRecentTrashRecords() {
        recentTrashRecords = Array(recentTrashRecords.suffix(500))
        let records = recentTrashRecords
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.trashRecordsKey)
        }
    }

    private func failureLabel(for url: URL) -> String {
        "\(url.lastPathComponent)（\(url.path)）"
    }

    private func publishCleanupFailures(_ failures: [String]) {
        guard !failures.isEmpty else { return }

        let visibleFailures = failures.prefix(5).joined(separator: "\n")
        let remaining = failures.count > 5 ? "\n以及另外 \(failures.count - 5) 项。" : ""
        cleanupErrorMessage = "以下项目没有被移入废纸篓，可能是应用仍在运行、权限不足，或路径受系统保护：\n\(visibleFailures)\(remaining)"
    }
}

// MARK: - Date Formatting

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 3600 { return "今天" }
        if interval < 86400 { return "今天" }
        if interval < 172800 { return "昨天" }
        if interval < 604800 { return "\(Int(interval / 86400)) 天前" }
        if interval < 2592000 { return "\(Int(interval / 604800)) 周前" }
        if interval < 31536000 { return "\(Int(interval / 2592000)) 个月前" }
        return "\(Int(interval / 31536000)) 年前"
    }
}
