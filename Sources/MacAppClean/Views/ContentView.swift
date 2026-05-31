import SwiftUI

struct ContentView: View {
    @Bindable var store: CleanerStore
    @State private var deletionListIsPresented = false

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } content: {
            CleanerListView(store: store)
                .navigationSplitViewColumnWidth(min: 360, ideal: 500)
        } detail: {
            InspectorView(store: store)
                .navigationSplitViewColumnWidth(min: 420, ideal: 680)
        }
        .searchable(text: $store.query, placement: .toolbar, prompt: "搜索应用、开发者、文件")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.scan()
                } label: {
                    Label(store.isScanning ? "扫描中" : "扫描", systemImage: store.isScanning ? "waveform.path.ecg" : "magnifyingglass")
                }
                .disabled(store.isScanning)

                Button {
                    store.clearSelection()
                } label: {
                    Label("清除", systemImage: "xmark.circle")
                }
                .disabled(store.selectedCount == 0)

                Button {
                    deletionListIsPresented = true
                } label: {
                    Label("删除清单", systemImage: "list.bullet.rectangle")
                }
                .disabled(store.restorableTrashCount == 0)
            }
        }
        .alert("无法完成移除", isPresented: cleanupErrorIsPresented) {
            Button("好") {
                store.cleanupErrorMessage = nil
            }
        } message: {
            Text(store.cleanupErrorMessage ?? "")
        }
        .alert("文件夹访问未完整授权", isPresented: scanAccessMessageIsPresented) {
            Button("好") {
                store.scanAccessMessage = nil
            }
        } message: {
            Text(store.scanAccessMessage ?? "")
        }
        .alert("无法恢复项目", isPresented: restoreErrorIsPresented) {
            Button("好") {
                store.restoreErrorMessage = nil
            }
        } message: {
            Text(store.restoreErrorMessage ?? "")
        }
        .sheet(isPresented: $deletionListIsPresented) {
            DeletionListView(store: store)
        }
    }

    private var cleanupErrorIsPresented: Binding<Bool> {
        Binding(
            get: { store.cleanupErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    store.cleanupErrorMessage = nil
                }
            }
        )
    }

    private var scanAccessMessageIsPresented: Binding<Bool> {
        Binding(
            get: { store.scanAccessMessage != nil },
            set: { isPresented in
                if !isPresented {
                    store.scanAccessMessage = nil
                }
            }
        )
    }

    private var restoreErrorIsPresented: Binding<Bool> {
        Binding(
            get: { store.restoreErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    store.restoreErrorMessage = nil
                }
            }
        )
    }
}

private struct DeletionListView: View {
    @Bindable var store: CleanerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("删除清单")
                        .font(.title2.weight(.semibold))
                    Text("选择要从废纸篓恢复的 App 或项目")
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
                        DeletionBatchRow(batch: batch) {
                            store.restoreDeletedBatch(id: batch.id)
                            if store.deletedTrashBatches.isEmpty {
                                dismiss()
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
    }
}

private struct DeletionBatchRow: View {
    var batch: CleanerStore.DeletedTrashBatch
    var onRestore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.blue.opacity(0.12))
                Image(systemName: "app.badge")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(batch.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(batch.formattedSize)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text("\(batch.itemCount) 个项目 · \(batch.removedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !batch.previewPaths.isEmpty {
                    Text(batch.previewPaths.joined(separator: "\n"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button {
                onRestore()
            } label: {
                Label("恢复", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
    }
}
