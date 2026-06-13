import SwiftUI

struct SettingsView: View {
    @AppStorage("scanCaches") private var scanCaches = true
    @AppStorage("scanStartup") private var scanStartup = true
    @AppStorage("scanSecurity") private var scanSecurity = true
    @AppStorage("scanLargeFiles") private var scanLargeFiles = true
    @AppStorage("askBeforeRemoval") private var askBeforeRemoval = true
    @AppStorage("trashInsteadOfDelete") private var trashInsteadOfDelete = true
    @AppStorage(KnowledgeBaseProvider.remoteRulesURLKey) private var remoteRulesURL = ""
    @AppStorage(KnowledgeBaseProvider.localOnlyKey) private var onlyUseLocalRules = false
    @State private var knowledgeBaseStatus = "未更新"
    @State private var isUpdatingKnowledgeBase = false

    var body: some View {
        TabView {
            Form {
                Section("扫描范围") {
                    Toggle("应用缓存和服务文件", isOn: $scanCaches)
                    Toggle("启动项和启动代理", isOn: $scanStartup)
                    Toggle("安全与权限审计", isOn: $scanSecurity)
                    Toggle("大文件扫描（> 100MB）", isOn: $scanLargeFiles)
                }

                Section("移除") {
                    Toggle("移到废纸篓前先询问", isOn: $askBeforeRemoval)
                    Toggle("使用废纸篓（而非永久删除）", isOn: $trashInsteadOfDelete)
                }

                Section("知识库") {
                    Toggle("仅使用本地规则", isOn: $onlyUseLocalRules)

                    TextField("远端规则源 URL（HTTPS）", text: $remoteRulesURL)
                        .textFieldStyle(.roundedBorder)
                        .disabled(onlyUseLocalRules)

                    HStack {
                        Button {
                            updateKnowledgeBase()
                        } label: {
                            Label(isUpdatingKnowledgeBase ? "更新中" : "更新知识库", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(onlyUseLocalRules || isUpdatingKnowledgeBase || remoteRulesURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Spacer()

                        Text(knowledgeBaseStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("语言")
                        Spacer()
                        Text("中文（简体）")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("通用", systemImage: "gearshape")
            }

            Form {
                Section("隐私说明") {
                    Text("MacAppClean 不会上传你的任何应用数据。所有扫描在本地完成，文件仅在本地处理。远端规则源只用于下载规则文件，不会发送你的应用列表。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("数据") {
                    Button("清除扫描缓存") {
                        UserDefaults.standard.removeObject(forKey: "scanCaches")
                        UserDefaults.standard.removeObject(forKey: "scanStartup")
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("隐私", systemImage: "hand.raised")
            }
        }
        .frame(width: 500, height: 400)
        .onAppear(perform: loadKnowledgeBaseStatus)
    }

    private func updateKnowledgeBase() {
        isUpdatingKnowledgeBase = true
        knowledgeBaseStatus = "正在下载..."

        Task { @MainActor in
            do {
                let snapshot = try await KnowledgeBaseProvider().refreshConfiguredRemoteCache()
                knowledgeBaseStatus = "已更新 v\(snapshot.version)"
            } catch {
                knowledgeBaseStatus = error.localizedDescription
            }
            isUpdatingKnowledgeBase = false
        }
    }

    private func loadKnowledgeBaseStatus() {
        if let metadata = KnowledgeBaseProvider().cachedMetadata() {
            knowledgeBaseStatus = "缓存 v\(metadata.version) · \(metadata.updatedAt.formatted(date: .numeric, time: .shortened))"
        } else {
            knowledgeBaseStatus = "使用内置规则"
        }
    }
}
