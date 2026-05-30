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

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(CleanerSection.allCases) { section in
                        SidebarSectionRow(
                            section: section,
                            isSelected: store.selectedSection == section,
                            color: sectionIconColor(section)
                        ) {
                            store.selectedSection = section
                        }
                    }

                    SidebarScanPanel(store: store)
                        .padding(.top, 8)
                }
                .padding(10)
            }
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

private struct SidebarSectionRow: View {
    var section: CleanerSection
    var isSelected: Bool
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color.opacity(0.2))
                    Image(systemName: section.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(color)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.rawValue)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(section.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarScanPanel: View {
    @Bindable var store: CleanerStore

    var body: some View {
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
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
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
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

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
        .padding(.top, 2)
    }
}
