import SwiftUI

struct CleanerListView: View {
    @Bindable var store: CleanerStore

    var body: some View {
        VStack(spacing: 0) {
            DashboardHeader(store: store)

            Divider()

            if store.visibleItems.isEmpty {
                emptyState
            } else {
                List(selection: $store.selectedItemID) {
                    Section {
                        ForEach(store.visibleItems) { item in
                            CleanerItemRow(item: item) {
                                store.toggleSelection(item)
                            }
                            .tag(item.id)
                            .contextMenu {
                                Button(item.isSelected ? "从选择中移除" : "加入选择") {
                                    store.toggleSelection(item)
                                }
                                if let url = item.appURL {
                                    Button("在访达中显示") {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(store.selectedSection.rawValue)
                                .font(.headline)
                            Text("（\(store.visibleItems.count) 项）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                store.sortMode = store.sortMode.next
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: store.sortMode.icon)
                                    Text(store.sortMode.rawValue)
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            Divider()
                                .frame(height: 12)
                            Button("全选") {
                                store.selectAllVisible()
                            }
                            .font(.caption)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            if store.selectedCount > 0 {
                CleanupBar(store: store)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: store.selectedSection.icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("暂无\(store.selectedSection.rawValue)")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("点击左侧「立即扫描」按钮开始检测")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DashboardHeader: View {
    @Bindable var store: CleanerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("清理、更新并保护你的 Mac")
                            .font(.title2.weight(.semibold))
                        if store.isScanning {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                        }
                    }
                    Text("彻底卸载应用、清理残留文件、管理启动项、检查更新和公证状态。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !store.metrics.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(store.metrics) { metric in
                        MetricTile(metric: metric)
                    }
                }
            }
        }
        .padding(20)
    }
}

private struct MetricTile: View {
    var metric: Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: metric.icon)
                    .font(.caption)
                    .foregroundStyle(metric.tint)
                Spacer()
            }
            Text(metric.value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(metric.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            Text(metric.caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CleanerItemRow: View {
    var item: CleanerItem
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(item.health.tint.opacity(0.15))
                Image(systemName: item.icon)
                    .font(.title2)
                    .foregroundStyle(item.health.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if item.hasUpdate {
                        Label("可更新", systemImage: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .labelStyle(.iconOnly)
                    }
                }

                Text("\(item.developer) · \(item.fileCount) 个文件 · \(item.lastUsed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.formattedSize)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.health == .verified ? .primary : item.health.tint)
                Label(item.health.rawValue, systemImage: item.health == .verified ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(item.health.tint)
                    .labelStyle(.iconOnly)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct CleanupBar: View {
    @Bindable var store: CleanerStore
    @State private var deletionListIsPresented = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.fill")
                .font(.title3)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text("已选择 \(store.selectedCount) 项")
                    .font(.subheadline.weight(.semibold))
                Text(ByteCountFormatter.string(fromByteCount: store.selectedSize, countStyle: .file) + " 可释放")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("取消选择") {
                store.clearSelection()
            }
            .font(.subheadline)
            .disabled(store.selectedCount == 0)

            Button {
                deletionListIsPresented = true
            } label: {
                Label("删除清单", systemImage: "list.bullet.rectangle")
                    .font(.subheadline)
            }
            .disabled(store.restorableTrashCount == 0)

            Button {
                store.removeSelected()
            } label: {
                Label("移入废纸篓", systemImage: "trash")
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(store.selectedCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .sheet(isPresented: $deletionListIsPresented) {
            DeletionListSheet(store: store)
        }
    }
}

private struct DeletionListSheet: View {
    @Bindable var store: CleanerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("删除清单")
                        .font(.title2.weight(.semibold))
                    Text("选择要恢复的 App 或项目")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("完成") {
                    dismiss()
                }
            }
            .padding(20)

            Divider()

            if store.deletedTrashBatches.isEmpty {
                ContentUnavailableView("没有可恢复项目", systemImage: "trash", description: Text("通过 MacAppClean 移入废纸篓的项目会出现在这里。"))
                    .frame(minHeight: 260)
            } else {
                List {
                    ForEach(store.deletedTrashBatches) { batch in
                        HStack(spacing: 12) {
                            Image(systemName: "app.badge")
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 34)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(batch.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(batch.itemCount) 个项目 · \(batch.formattedSize) · \(batch.removedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("恢复") {
                                store.restoreDeletedBatch(id: batch.id)
                                if store.deletedTrashBatches.isEmpty {
                                    dismiss()
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 600, minHeight: 420)
    }
}
