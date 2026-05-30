import SwiftUI

struct InspectorView: View {
    @Bindable var store: CleanerStore

    var body: some View {
        ScrollView {
            if let item = store.selectedItem {
                VStack(alignment: .leading, spacing: 16) {
                    AppIdentityView(item: item)
                    FileBreakdownView(item: item)
                    SecurityPanel(item: item)
                    PermissionsPanel(item: item)
                    ActionPanel(item: item, store: store)
                }
                .padding(20)
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
