import SwiftUI

struct SidebarView: View {
    @Bindable var store: CleanerStore

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "cat.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacAppClean")
                        .font(.headline)
                    Text("应用清理与卸载工具")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)

            List(CleanerSection.allCases, selection: $store.selectedSection) { section in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.rawValue)
                            .font(.subheadline)
                        Text(section.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } icon: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(sectionIconColor(section).opacity(0.2))
                            .frame(width: 26, height: 26)
                        Image(systemName: section.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(sectionIconColor(section))
                    }
                }
                .tag(section)
                .padding(.vertical, 2)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            // Bottom info panel
            VStack(alignment: .leading, spacing: 10) {
                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("智能扫描")
                            .font(.subheadline.weight(.semibold))
                        if store.isScanning {
                            Text(store.scanProgress)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if store.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(store.lastScanSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Button {
                    store.scan()
                } label: {
                    Label(store.isScanning ? "扫描中..." : "立即扫描", systemImage: store.isScanning ? "arrow.triangle.2.circlepath" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(store.isScanning)
            }
            .padding(12)
        }
    }

    private func sectionIconColor(_ section: CleanerSection) -> Color {
        switch section {
        case .applications: .blue
        case .startupPrograms: .orange
        case .extensions: .purple
        case .remainingFiles: .red
        case .largeFiles: .teal
        case .updates: .indigo
        case .security: .green
        }
    }
}
