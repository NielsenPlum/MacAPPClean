import SwiftUI

@main
struct MacAppCleanApp: App {
    @State private var store = CleanerStore()

    var body: some Scene {
        WindowGroup("MacAppClean") {
            ContentView(store: store)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("扫描应用") {
                    store.scan()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("移入废纸篓") {
                    store.removeSelected()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(store.selectedCount == 0)

                Button("恢复上次移除") {
                    store.restoreLastRemovedItems()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(store.restorableTrashCount == 0)

                Divider()
            }

            CommandGroup(after: .windowList) {
                Button("全选当前列表") {
                    store.selectAllVisible()
                }
                .keyboardShortcut("a", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
        }
    }
}
