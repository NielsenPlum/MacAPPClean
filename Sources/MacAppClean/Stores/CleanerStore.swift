import Foundation
import Observation

@Observable
final class CleanerStore {
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
        scanProgress = "正在扫描应用文件夹..."
        lastScanSummary = "正在扫描应用包、缓存、偏好设置、启动代理和浏览器扩展..."

        Task { @MainActor in
            var scanned: [CleanerItem] = []

            scanProgress = "正在扫描 /Applications..."
            var seenAppPaths = Set<String>()
            scanned += await scanApplicationsDirectory(url: URL(fileURLWithPath: "/Applications"), seenPaths: &seenAppPaths)
            scanned += await scanApplicationsDirectory(url: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"), seenPaths: &seenAppPaths)

            scanProgress = "正在扫描启动项..."
            scanned += await scanStartupPrograms()

            scanProgress = "正在扫描扩展..."
            scanned += await scanExtensions()

            scanProgress = "正在扫描残留文件..."
            scanned += await scanLeftovers()

            scanProgress = "正在扫描大文件..."
            scanned += await scanLargeFiles()

            scanProgress = "正在检查安全状态..."
            scanned = await scanSecurity(items: scanned)

            scanProgress = "正在检查更新..."
            scanned = await checkUpdates(items: scanned)

            scanned = deduplicatedItems(scanned)

            try? await Task.sleep(for: .milliseconds(200))
            self.items = scanned
            self.isScanning = false
            self.scanProgress = ""
            self.lastScanSummary = "扫描完成。在 \(CleanerSection.allCases.count) 个分类中共发现 \(scanned.count) 个项目，预估可释放 \(ByteCountFormatter.string(fromByteCount: totalRecoverable, countStyle: .file))。"
        }
    }

    // MARK: - Directory Size Calculator

    /// Recursively calculate total file size for a URL (works for both files and directories)
    private func directoryTotalSize(url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            return (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }

        // Directory: enumerate all regular files recursively
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsPackageDescendants, .skipsHiddenFiles]) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }
            total += Int64(fileSize)
        }
        return total
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

    private func scanApplicationsDirectory(url: URL, seenPaths: inout Set<String>) async -> [CleanerItem] {
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
                        let relatedFiles = findRelatedFiles(for: resolved)
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

    private func findRelatedFiles(for appURL: URL) -> [ScannedFile] {
        var files: [ScannedFile] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        guard let bundleID = Bundle(url: appURL)?.bundleIdentifier else { return files }
        let appName = appURL.deletingPathExtension().lastPathComponent

        let libraryPaths: [(String, ScannedFile.FileCategory)] = [
            ("Library/Application Support/\(appName)", .support),
            ("Library/Application Support/\(bundleID)", .support),
            ("Library/Caches/\(bundleID)", .cache),
            ("Library/Caches/\(appName)", .cache),
            ("Library/Preferences/\(bundleID).plist", .preferences),
            ("Library/Logs/\(appName)", .log),
            ("Library/WebKit/\(bundleID)", .cache),
            ("Library/Saved Application State/\(bundleID).savedState", .support),
            ("Library/Containers/\(bundleID)", .support),
            ("Library/Group Containers/\(bundleID)", .support),
        ]

        for (relativePath, category) in libraryPaths {
            let pathURL = home.appending(path: relativePath)
            if fm.fileExists(atPath: pathURL.path) {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: pathURL.path, isDirectory: &isDir)
                let dirSize = directoryTotalSize(url: pathURL)
                let modDate = (try? pathURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                files.append(ScannedFile(
                    url: pathURL,
                    size: dirSize,
                    isDirectory: isDir.boolValue,
                    modDate: modDate,
                    category: category
                ))
            }
        }

        return files
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

        let installedBundleIDs = installedAppBundleIDs()

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
                if installedBundleIDs.contains(possibleBundleID) { continue }
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

    private func scanLargeFiles() async -> [CleanerItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var results: [CleanerItem] = []

        let downloadURL = home.appending(path: "Downloads")
        let desktopURL = home.appending(path: "Desktop")
        let documentsURL = home.appending(path: "Documents")

        let dirsToScan = [downloadURL, desktopURL, documentsURL]

        for dir in dirsToScan {
            guard fm.fileExists(atPath: dir.path),
                  let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey], options: [.skipsPackageDescendants, .skipsHiddenFiles]) else {
                continue
            }

            var largeFiles: [ScannedFile] = []

            while let fileURL = enumerator.nextObject() as? URL {
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true,
                      let fileSize = values.fileSize,
                      fileSize > 100_000_000 else {
                    continue
                }

                let modDate = values.contentModificationDate ?? Date()
                largeFiles.append(ScannedFile(
                    url: fileURL,
                    size: Int64(fileSize),
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

    private func checkUpdates(items: [CleanerItem]) async -> [CleanerItem] {
        return items
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

    private func installedAppBundleIDs() -> Set<String> {
        var ids = Set<String>()
        let fm = FileManager.default

        for appDir in [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appending(path: "Applications")] {
            guard fm.fileExists(atPath: appDir.path),
                  let apps = try? fm.contentsOfDirectory(at: appDir, includingPropertiesForKeys: [], options: .skipsHiddenFiles) else {
                continue
            }
            for app in apps where app.pathExtension == "app" {
                if let bundleID = Bundle(url: app)?.bundleIdentifier {
                    ids.insert(bundleID)
                }
            }
        }

        return ids
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
        let selectedIDs = Set(items.filter(\.isSelected).map(\.id))
        let fm = FileManager.default

        for item in items where item.isSelected {
            if let appURL = item.appURL, fm.fileExists(atPath: appURL.path) {
                try? fm.trashItem(at: appURL, resultingItemURL: nil)
            }
            for file in item.files where fm.fileExists(atPath: file.url.path) {
                try? fm.trashItem(at: file.url, resultingItemURL: nil)
            }
        }

        items.removeAll { selectedIDs.contains($0.id) }
        selectedItemID = nil
    }

    func remove(item: CleanerItem, filePaths: Set<String>) {
        guard !filePaths.isEmpty else { return }

        let fm = FileManager.default
        if let appURL = item.appURL, filePaths.contains(appURL.path), fm.fileExists(atPath: appURL.path) {
            try? fm.trashItem(at: appURL, resultingItemURL: nil)
        }

        for file in item.files where filePaths.contains(file.url.path) && fm.fileExists(atPath: file.url.path) {
            try? fm.trashItem(at: file.url, resultingItemURL: nil)
        }

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            let appWasRemoved = item.appURL.map { filePaths.contains($0.path) } ?? false
            if appWasRemoved || filePaths.count >= item.files.count + (item.appURL == nil ? 0 : 1) {
                items.remove(at: index)
                selectedItemID = nil
            } else {
                items[index].files.removeAll { filePaths.contains($0.url.path) }
                items[index].size = max(0, items[index].size - item.files.filter { filePaths.contains($0.url.path) }.map(\.size).reduce(0, +))
            }
        }
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
