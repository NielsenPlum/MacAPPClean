import SwiftUI

struct ContentView: View {
    @Bindable var store: CleanerStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 230, ideal: 250)
        } content: {
            CleanerListView(store: store)
                .navigationSplitViewColumnWidth(min: 430, ideal: 520)
        } detail: {
            InspectorView(store: store)
                .navigationSplitViewColumnWidth(min: 310, ideal: 360)
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
            }
        }
    }
}
