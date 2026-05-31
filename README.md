# MacAppClean — macOS 应用清理与卸载工具

MacAppClean 是一个 SwiftUI macOS 应用清理与卸载工具，目标是用全中文界面完成应用扫描、关联文件识别、移入废纸篓、恢复记录、更新检查和安全状态查看。

## 当前功能

| 模块 | 说明 |
|------|------|
| **应用扫描** | 扫描 `/Applications` 和 `~/Applications`，递归发现 `.app`，读取名称、版本、开发者、图标和大小信息 |
| **关联文件识别** | 结合内置/远端知识库和启发式路径，查找支持文件、缓存、偏好设置、日志、容器、启动代理等关联文件 |
| **风险分级** | 关联文件支持低/中/高风险标记；用户数据、游戏内容等高风险项目默认更谨慎处理 |
| **启动项** | 扫描 `~/Library/LaunchAgents`，读取 plist 中的后台项目，并标记目标程序是否已不存在 |
| **扩展** | 扫描 Safari 扩展 (`~/Library/Safari/Extensions`) 和系统扩展 (`/Library/Extensions`) |
| **残留文件** | 在 Application Support、Caches、Preferences、Logs、Containers、WebKit、Saved Application State 等目录中查找疑似已卸载应用残留 |
| **大文件** | 扫描下载、桌面、文稿中超过 100 MB 的普通文件；扫描范围依赖 macOS 文件夹授权 |
| **安全检查** | 调用 `codesign` 检查应用签名状态，并对未签名、adhoc 或缺少 hardened runtime 的项目提示风险 |
| **更新检查** | 根据知识库或内置映射查询 Homebrew Cask 和 App Store 最新版本，展示可更新状态 |
| **移入废纸篓** | 支持整项或单个关联文件移入废纸篓；移除应用前会尝试终止正在运行的应用 |
| **删除清单与恢复** | 记录最近移入废纸篓的项目批次，支持恢复仍在废纸篓且原位置不存在的项目 |
| **知识库设置** | 支持配置 HTTPS 远端规则源、本地缓存、仅使用本地规则，并在远端失败时回退缓存/内置规则 |
| **界面操作** | 三栏 SwiftUI 界面，支持搜索、排序、全选当前列表、清除选择、删除清单和设置窗口 |

## 技术栈

- **语言**: Swift 5.9
- **框架**: SwiftUI + Observation
- **最低系统**: macOS 14.0 (Sonoma)

## 构建与运行

```bash
# 仅构建
swift build

# 直接构建并运行
./script/build_and_run.sh

# 仅验证构建
./script/build_and_run.sh --verify

# 调试模式
./script/build_and_run.sh --debug

# 查看日志
./script/build_and_run.sh --logs
```

## 快捷键

| 快捷键 | 操作 |
|--------|------|
| `Command + R` | 扫描应用 |
| `Command + Delete` | 将已选择项目移入废纸篓 |
| `Command + Shift + Z` | 恢复上次可恢复的移除记录 |
| `Command + A` | 全选当前列表 |

## 知识库规则格式

设置页可以配置一个 HTTPS 远端规则源。MacAppClean 只下载规则 JSON，不上传本机应用列表。

```json
{
  "version": "2026.05.31",
  "rules": [
    {
      "id": "com.example.App",
      "name": "Example App",
      "match": {
        "bundleIDs": ["com.example.App"],
        "names": ["Example App"]
      },
      "paths": [
        {
          "template": "$APP_SUPPORT/Example App",
          "category": "support",
          "risk": "medium",
          "defaultSelected": true
        }
      ],
      "update": {
        "homebrewCaskToken": "example-app",
        "appStoreCountry": "US"
      }
    }
  ]
}
```

支持的模板变量包括：`~`、`$HOME`、`$APP_NAME`、`$BUNDLE_ID`、`$APP_SUPPORT`、`$CACHES`、`$PREFERENCES`、`$LOGS`、`$CONTAINERS`、`$GROUP_CONTAINERS`、`$HTTP_STORAGES`、`$WEBKIT`、`$SAVED_STATE`、`$APPLICATION_SCRIPTS`、`$SYSTEM_LIBRARY`、`$SYSTEM_APP_SUPPORT`、`$SYSTEM_CACHES`、`$SYSTEM_PREFERENCES`、`$SYSTEM_LAUNCH_AGENTS`、`$SYSTEM_LAUNCH_DAEMONS`、`$PRIVILEGED_HELPER_TOOLS`、`$PKG_RECEIPTS`。

## 功能看护建议

当前最基础的回归门禁是：

```bash
swift build
swift test
./script/verify_app.sh
```

建议后续按风险逐步补齐：

- **核心逻辑单元测试**：当前已覆盖知识库 URL/内置规则加载、关联文件解析、路径去重、风险默认选择；后续继续补版本比较、残留过滤、删除记录恢复状态等纯逻辑。
- **本地验收脚本**：`script/verify_app.sh` 会执行构建、测试和启动 smoke check；后续可继续扩展基础扫描输出、bundle 信息和图标资源检查。
- **CI 守门**：在 GitHub Actions 或其他 CI 中执行 `swift build` 和 `swift test`。
- **人工验收清单**：每次涉及扫描、删除或设置逻辑时，至少检查启动、扫描、搜索/排序、选择、移入废纸篓、删除清单恢复、知识库设置。

## 当前状态与限制

- 当前仓库已有最小测试 target，覆盖部分纯逻辑；UI、权限和真实文件系统行为仍需要本地验收脚本与人工验收。
- 桌面、下载、文稿等权限敏感目录的大文件扫描依赖 macOS 文件夹授权；未授权目录会被跳过并提示。
- 清理行为使用系统废纸篓，不执行永久删除。
- 设置页中的部分扫描/移除开关目前更多是配置展示，扫描流程尚未完全按这些开关分支执行。
- 更新检查依赖网络请求 Homebrew Cask API 或 App Store lookup；请求失败时不会阻塞本地扫描。
