import SwiftUI

struct InspectorView: View {
    @Bindable var store: CleanerStore

    var body: some View {
        ScrollView {
            if let item = store.selectedItem {
                if item.section == .applications {
                    AppUninstallDetailView(item: item, store: store)
                        .padding(16)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        AppIdentityView(item: item)
                        FileBreakdownView(item: item)
                        SecurityPanel(item: item)
                        PermissionsPanel(item: item)
                        ActionPanel(item: item, store: store)
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "app.dashed")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("未选择项目")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("在列表中选择一个项目\n查看详细信息、相关文件和操作选项")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .background(.background)
    }
}

// MARK: - App Uninstall Detail

private struct AppUninstallDetailView: View {
    var item: CleanerItem
    @Bindable var store: CleanerStore
    @State private var expandedCategories: Set<ScannedFile.FileCategory> = Set(ScannedFile.FileCategory.allCases)
    @State private var selectedPaths: Set<String> = []

    private var uninstallEntries: [UninstallEntry] {
        var entries: [UninstallEntry] = []

        if let appURL = item.appURL {
            let appSize = max(item.size - item.files.map(\.size).reduce(0, +), 0)
            entries.append(UninstallEntry(
                url: appURL,
                size: appSize,
                isDirectory: true,
                category: .app,
                version: item.version
            ))
        }

        entries += item.files.map { file in
            UninstallEntry(
                url: file.url,
                size: file.size,
                isDirectory: file.isDirectory,
                category: file.category,
                version: nil
            )
        }

        return entries
    }

    private var groupedEntries: [UninstallGroup] {
        ScannedFile.FileCategory.uninstallOrder.compactMap { category in
            let entries = uninstallEntries.filter { $0.category == category }
            guard !entries.isEmpty else { return nil }
            return UninstallGroup(category: category, entries: entries)
        }
    }

    private var selectedSize: Int64 {
        uninstallEntries
            .filter { selectedPaths.contains($0.url.path) }
            .map(\.size)
            .reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UninstallSummaryCard(
                item: item,
                entries: uninstallEntries,
                selectedPaths: selectedPaths,
                onToggleAll: toggleAllEntries
            )

            VStack(spacing: 10) {
                ForEach(groupedEntries) { group in
                    UninstallFileGroup(
                        group: group,
                        selectedPaths: $selectedPaths,
                        isExpanded: Binding(
                            get: { expandedCategories.contains(group.category) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedCategories.insert(group.category)
                                } else {
                                    expandedCategories.remove(group.category)
                                }
                            }
                        )
                    )
                }
            }

            UninstallDetailActions(
                item: item,
                selectedSize: selectedSize,
                selectedCount: selectedPaths.count,
                store: store,
                onRemoveSelected: {
                    store.remove(item: item, filePaths: selectedPaths)
                },
                onSelectAll: selectAllEntries
            )
        }
        .onAppear(perform: selectAllEntries)
        .onChange(of: item.id) { _, _ in
            selectAllEntries()
            expandedCategories = Set(ScannedFile.FileCategory.allCases)
        }
    }

    private func selectAllEntries() {
        selectedPaths = Set(uninstallEntries.map { $0.url.path })
    }

    private func toggleAllEntries() {
        if selectedPaths.count == uninstallEntries.count {
            selectedPaths.removeAll()
        } else {
            selectAllEntries()
        }
    }
}

private struct UninstallSummaryCard: View {
    var item: CleanerItem
    var entries: [UninstallEntry]
    var selectedPaths: Set<String>
    var onToggleAll: () -> Void

    private var selectedSize: Int64 {
        entries
            .filter { selectedPaths.contains($0.url.path) }
            .map(\.size)
            .reduce(0, +)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Button(action: onToggleAll) {
                Image(systemName: selectedPaths.count == entries.count ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(selectedPaths.isEmpty ? Color.secondary : Color.blue)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help(selectedPaths.count == entries.count ? "取消选择所有项目" : "选择所有项目")

            AppArtwork(url: item.appURL, fallback: item.icon, size: 72)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)

                    if item.version != "未知", item.version != "-" {
                        Text("v.\(item.version)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text("开发人员")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("应用程序文件和文件夹")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if !item.permissions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(item.permissions.prefix(3), id: \.self) { permission in
                            Label(permission, systemImage: "key.horizontal")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(item.developer)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(selectedPaths.count) / \(entries.count) 个项目")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
            .frame(minWidth: 120, alignment: .trailing)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.blue.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct UninstallFileGroup: View {
    var group: UninstallGroup
    @Binding var selectedPaths: Set<String>
    @Binding var isExpanded: Bool

    private var selectedCount: Int {
        group.entries.filter { selectedPaths.contains($0.url.path) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    toggleGroup()
                } label: {
                    Image(systemName: selectedCount == group.entries.count ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selectedCount == 0 ? Color.secondary : Color.blue)
                        .frame(width: 18)
                }
                .buttonStyle(.plain)

                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text(group.category.detailTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(group.summaryText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.11))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.blue.opacity(0.22), lineWidth: 1)
            )

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.entries) { entry in
                        UninstallFileRow(entry: entry, isSelected: selectedPaths.contains(entry.url.path)) {
                            if selectedPaths.contains(entry.url.path) {
                                selectedPaths.remove(entry.url.path)
                            } else {
                                selectedPaths.insert(entry.url.path)
                            }
                        }

                        if entry.id != group.entries.last?.id {
                            Divider()
                                .padding(.leading, 84)
                        }
                    }
                }
            }
        }
    }

    private func toggleGroup() {
        let paths = Set(group.entries.map { $0.url.path })
        if selectedCount == group.entries.count {
            selectedPaths.subtract(paths)
        } else {
            selectedPaths.formUnion(paths)
        }
    }
}

private struct UninstallFileRow: View {
    var entry: UninstallEntry
    var isSelected: Bool
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            FileArtwork(entry: entry)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.url.deletingPathExtensionIfApp.lastPathComponent)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let version = entry.version, version != "未知", version != "-" {
                        Text("v.\(version)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text(entry.displayLocation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 76, alignment: .trailing)
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}

private struct UninstallDetailActions: View {
    var item: CleanerItem
    var selectedSize: Int64
    var selectedCount: Int
    @Bindable var store: CleanerStore
    var onRemoveSelected: () -> Void
    var onSelectAll: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("将移除 \(selectedCount) 个项目")
                    .font(.subheadline.weight(.semibold))
                Text(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file) + " 可释放")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("全选", action: onSelectAll)
                .disabled(selectedCount == 0 && item.fileCount == 0 && item.appURL == nil)

            if let url = item.appURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("显示", systemImage: "folder")
                }
            }

            Button {
                onRemoveSelected()
            } label: {
                Label("移入废纸篓", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedCount == 0)
        }
        .padding(14)
        .background(.bar, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AppArtwork: View {
    var url: URL?
    var fallback: String
    var size: CGFloat

    var body: some View {
        Group {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.quaternary)
                    Image(systemName: fallback)
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

private struct FileArtwork: View {
    var entry: UninstallEntry

    var body: some View {
        Group {
            if entry.category == .app {
                AppArtwork(url: entry.url, fallback: "app.dashed", size: 34)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
            }
        }
        .frame(width: 34, height: 34)
    }
}

private struct UninstallEntry: Identifiable, Hashable {
    var id: String { url.path }
    var url: URL
    var size: Int64
    var isDirectory: Bool
    var category: ScannedFile.FileCategory
    var version: String?

    var displayLocation: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let parent = url.deletingLastPathComponent().path

        if parent == "/Applications" {
            return "/Applications"
        }

        if parent.hasPrefix(home) {
            let shortened = parent.replacingOccurrences(of: home, with: NSUserName())
            return shortened
        }

        return parent
    }
}

private struct UninstallGroup: Identifiable {
    var id: ScannedFile.FileCategory { category }
    var category: ScannedFile.FileCategory
    var entries: [UninstallEntry]

    var summaryText: String {
        let files = entries.filter { !$0.isDirectory }.count
        let folders = entries.filter(\.isDirectory).count
        let size = ByteCountFormatter.string(fromByteCount: entries.map(\.size).reduce(0, +), countStyle: .file)

        switch (files, folders) {
        case (0, 0):
            return size
        case (0, _):
            return "\(folders) 个文件夹 · \(size)"
        case (_, 0):
            return "\(files) 个文件 · \(size)"
        default:
            return "\(files) 个文件和 \(folders) 个文件夹 · \(size)"
        }
    }
}

// MARK: - App Identity

private struct AppIdentityView: View {
    var item: CleanerItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(item.health.tint.opacity(0.15))
                    Image(systemName: item.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(item.health.tint)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.title3.weight(.semibold))
                    Text(item.developer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if item.version != "-" {
                        Text("版本 \(item.version)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Text(item.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .inspectorCard()
    }
}

// MARK: - File Breakdown

private struct FileBreakdownView: View {
    var item: CleanerItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("关联文件")
                    .font(.headline)
                Spacer()
                Text("共 \(item.fileCount) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                StatPill(title: "总计大小", value: item.formattedSize, icon: "internaldrive")
                StatPill(title: "文件数量", value: "\(item.fileCount)", icon: "doc.on.doc")
            }

            if !item.files.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(item.files.prefix(10))) { file in
                        FileLine(file: file)
                    }
                    if item.files.count > 10 {
                        Text("以及其余 \(item.files.count - 10) 项...")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("未发现关联文件。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .inspectorCard()
    }
}

// MARK: - Security Panel

private struct SecurityPanel: View {
    var item: CleanerItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("安全")
                .font(.headline)

            HStack(spacing: 10) {
                Image(systemName: item.health == .verified ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(item.health.tint)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.health.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Text(securityDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let latestVersion = item.latestVersion {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.purple)
                    Text("新版本可用：\(latestVersion)")
                        .font(.subheadline)
                    Spacer()
                    Button("更新") {}
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
                .padding(10)
                .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .inspectorCard()
    }

    private var securityDescription: String {
        switch item.health {
        case .verified: "Apple 公证和签名状态正常。"
        case .warning: "保留或移除前，请检查发布者和敏感权限。"
        case .unverified: "未经过 Apple 公证的应用。保留前请确认来源可信。"
        }
    }
}

// MARK: - Permissions Panel

private struct PermissionsPanel: View {
    var item: CleanerItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("权限")
                .font(.headline)

            if item.permissions.isEmpty {
                Text("未发现敏感权限。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 6) {
                    ForEach(item.permissions, id: \.self) { permission in
                        Label(permission, systemImage: "key.horizontal")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
        .inspectorCard()
    }
}

// MARK: - Action Panel

private struct ActionPanel: View {
    var item: CleanerItem
    @Bindable var store: CleanerStore

    var body: some View {
        VStack(spacing: 10) {
            Button {
                store.toggleSelection(item)
            } label: {
                Label(item.isSelected ? "从选择中移除" : "加入移除队列",
                      systemImage: item.isSelected ? "minus.circle" : "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(item.isSelected ? .gray : .blue)

            HStack(spacing: 10) {
                if let url = item.appURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("在访达中显示", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                }

                Button {
                    if let idx = store.items.firstIndex(where: { $0.id == item.id }) {
                        store.items.remove(at: idx)
                    }
                } label: {
                    Label("忽略", systemImage: "eye.slash")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(item.appURL == nil)
        }
        .inspectorCard()
    }
}

// MARK: - Supporting Views

private struct StatPill: View {
    var title: String
    var value: String
    var icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FileLine: View {
    var file: ScannedFile

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.isDirectory ? "folder" : "doc")
                .font(.caption)
                .foregroundStyle(file.category == .cache ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                Text(file.url.deletingLastPathComponent().lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(file.sizeFormatted)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - View Modifier

private extension View {
    func inspectorCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
