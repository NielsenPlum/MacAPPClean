# macOS App 卸载关联知识库调研报告

日期：2026-05-31

## 结论摘要

MacAppClean 现在已经具备知识库雏形：`KnowledgeBaseRule` 支持按 bundle id / 名称匹配应用，按路径模板产出候选文件，并可通过 HTTPS 远端 JSON 覆盖内置规则。下一阶段不需要推翻现有设计，建议演进为“规则知识库 + 系统启发式 + 数据源导入管线 + 安全评分”的组合。

最有价值的外部参考有四类：

1. Apple 官方目录规范：确认 `Application Support`、`Caches`、`Preferences`、`LaunchAgents`、sandbox `Containers` / `Group Containers` 等目录的语义。
2. Homebrew Cask `zap` 生态：大量应用已经维护了可清理路径，是最适合半自动导入的结构化来源。
3. Pearcleaner / Mole / MacSift / MyMacCleaner 等开源项目：可借鉴扫描范围、安全交互、dry-run、操作日志、Trash 优先等产品策略。
4. 商业卸载器/AppCleaner 类工具：可借鉴“拖入 app 后列出关联文件，用户确认后移动到废纸篓”的保守交互。

## macOS 卸载残留的核心事实

macOS 普通 `.app` bundle 通常可以直接移动到废纸篓，但该动作不会自动清理运行时产生的支持文件、缓存、偏好设置、日志、登录项、容器、插件、receipt 等文件。Apple 的文件系统指南明确把 `~/Library/Application Support/<bundle id>` 作为 app-specific 支持数据位置，把 `~/Library/Caches/<bundle id>` 作为用户级缓存位置，并列出 `LaunchAgents`、`Preferences` 等常见 Library 子目录。

Sandbox app 首次启动时会在 `~/Library/Containers` 创建容器；App Group 共享数据则在 Group Container 中。也就是说，卸载关联扫描不能只查 `$APP_SUPPORT/$APP_NAME`，还必须覆盖 bundle id、group id、容器、ByHost 偏好、HTTPStorages、WebKit、Saved Application State 等目录。

系统级残留还可能位于 `/Library/Application Support`、`/Library/LaunchAgents`、`/Library/LaunchDaemons`、`/Library/PrivilegedHelperTools`、`/private/var/db/receipts`。这类路径可能需要 Full Disk Access、管理员权限或 privileged helper，应进入高风险/需确认流程。

## 外部项目调研

### Pearcleaner

仓库：[alienator88/Pearcleaner](https://github.com/alienator88/Pearcleaner)

定位是 Swift/SwiftUI 原生 macOS app cleaner，功能包含 App Uninstall、Orphaned File Search、Homebrew Manager、PKG Manager、Plugin Manager、Services Manager、Apps Updater 等；支持拖放 app、CLI、deep link、Finder Extension、自动监控 app 进废纸篓后的清理提示。项目 README 说明它需要 Full Disk Access 搜索文件，并需要 Privileged Helper 操作系统目录。当前 README 标注项目在 2025 年底后基本暂停维护，最新版本显示为 5.4.3，release 日期为 2025-11-26。

可借鉴点：

- 扫描范围非常完整：`~/Library/Application Scripts`、`Application Support`、`Caches`、`Containers`、`Group Containers`、`HTTPStorages`、`Internet Plug-Ins`、`LaunchAgents`、`Logs`、`Preferences/ByHost`、`Saved Application State`、`WebKit`，以及 `/Library` 下的支持目录、LaunchAgents/Daemons、PrivilegedHelperTools、receipts、Homebrew 相关目录。
- 产品能力不只删除 app，还包括 orphaned file search、plugin/service/pkg 管理。
- 用户可配置 include/exclude 目录与搜索敏感度。

风险点：

- License 是 Apache 2.0 with Commons Clause，禁止商业化变体。可以学习思路和公开目录知识，但不要直接复制核心代码或规则数据。

### Mole

仓库：[tw93/Mole](https://github.com/tw93/mole)

定位是 macOS 终端清理/卸载/分析工具，README 描述为一体化工具，包含 deep cleaning、smart uninstaller、disk insights、live monitoring。CLI 支持 `mo clean`、`mo uninstall`、`--dry-run`、`mo history` 等。README 明确 smart uninstaller 会移除 app、launch agents、preferences、hidden remnants；clean 模式覆盖 caches、logs、browser leftovers、orphaned app data。

可借鉴点：

- `--dry-run` 和 `history` 很适合迁移到 GUI：先预览、不直接删除、保留操作日志。
- 命令行工具强调 `mo clean` 处理已卸载 app 残留、`mo uninstall` 处理仍安装 app，正好对应 MacAppClean 的“应用程序”和“残留文件”两个模块。
- 搜索结果显示 Mole 近期版本将 Homebrew cask uninstall 接入 `--zap`，并针对 macOS 15+ Local Network 权限残留给出提示。这类“无法安全自动删除，只能提示用户”的知识也应该进入 MacAppClean 的知识库。

风险点：

- Mole 是 Go/Shell CLI，架构与 SwiftUI app 不同，适合借鉴流程和规则，不建议嵌入调用其二进制作为核心能力。

### MacSift

仓库：[Lcharvol/MacSift](https://github.com/Lcharvol/MacSift)

定位是透明 macOS disk cleaner，README/About 描述为按 app 分组文件，并把选中项移动到 Trash，而非永久删除；SwiftUI + Liquid Glass，MIT license。

可借鉴点：

- “按 app owner 分组”和“只移动到废纸篓”是低风险 UX。
- MIT license 更适合作为可读参考。
- 对 MacAppClean 来说，可以把 `RelatedFileCandidate.matchedBy` 进一步显示成“为什么认为它属于这个 app”的证据链。

### MyMacCleaner

仓库：[Prot10/MyMacCleaner](https://github.com/Prot10/MyMacCleaner)

定位是 Swift/SwiftUI 原生 macOS maintenance utility。README 提到自动更新使用 Sparkle，技术栈为 Swift 5.9+、SwiftUI、async/await、TaskGroups，并在 Attribution 中说明借鉴 Pearcleaner 的 app uninstallation patterns、Clean-Me 的 junk file categories、Latest 的 app update detection、FullDiskAccess 的 permission handling。

可借鉴点：

- 与 MacAppClean 技术栈接近，可参考模块拆分、权限引导、Sparkle 更新体验。
- 它把多个开源项目的能力拆成 attribution，很适合我们做“知识库数据来源可追踪”的设计。

## Homebrew Cask `zap` 的价值

Homebrew Cask Cookbook 明确说明 `zap` stanza 描述比普通 uninstall 更完整的关联文件清理，可能包含用户 `~/Library` 下的 preferences/caches，也可能包含 shared resources；文档也提醒 shared resources 可能影响其他应用，用户需要理解风险。官方建议优先使用 `trash:` 而不是 `delete:`，并列出手工补 zap 时应检查的典型路径：

- `/Library/Application Support`
- `/Library/LaunchAgents`
- `/Library/LaunchDaemons`
- `/Library/Frameworks`
- `/Library/Logs`
- `/Library/Preferences`
- `/Library/PrivilegedHelperTools`
- `~/Library/Application Support`
- `~/Library/Caches`
- `~/Library/Containers`
- `~/Library/LaunchAgents`
- `~/Library/Logs`
- `~/Library/Preferences`
- `~/Library/Saved Application State`

集成建议：把 Homebrew cask 的 `zap trash/delete/rmdir` 作为规则导入源，而不是运行 `brew uninstall --zap`。这样 MacAppClean 可以继续保持自己的预览、风险评分和废纸篓流程。

## 知识库 schema 建议

当前 schema：

```json
{
  "id": "com.example.App",
  "match": { "bundleIDs": ["com.example.App"], "names": ["Example App"] },
  "paths": [{ "template": "$APP_SUPPORT/Example App", "category": "support", "risk": "medium", "defaultSelected": true }]
}
```

建议扩展为 v2：

```json
{
  "version": "2026.06.01",
  "rules": [
    {
      "id": "com.example.App",
      "name": "Example App",
      "source": {
        "type": "homebrew-cask",
        "url": "https://github.com/Homebrew/homebrew-cask/blob/master/Casks/e/example.rb",
        "license": "BSD-2-Clause",
        "updatedAt": "2026-05-31"
      },
      "match": {
        "bundleIDs": ["com.example.App"],
        "names": ["Example App"],
        "executables": ["Example"],
        "teamIDs": ["ABCDE12345"],
        "pkgIDs": ["com.example.pkg"]
      },
      "paths": [
        {
          "template": "$APP_SUPPORT/Example App",
          "category": "support",
          "risk": "medium",
          "defaultSelected": true,
          "confidence": 0.9,
          "ownership": "app-private",
          "action": "trash"
        }
      ],
      "warnings": [
        {
          "kind": "manual-step",
          "message": "macOS 权限数据库或 Local Network 权限可能不会随文件删除自动清空。"
        }
      ]
    }
  ]
}
```

字段说明：

- `source`：保存规则来源、license、更新时间，方便审计。
- `match.executables/teamIDs/pkgIDs`：减少同名 app 误判，尤其对 Electron app、供应商套件、pkg 安装器有用。
- `confidence`：区分确定命中、名称相似命中、vendor 目录命中。
- `ownership`：建议值 `app-private`、`vendor-shared`、`user-created`、`system-managed`。shared/user-created 默认不选。
- `action`：建议值 `trash`、`deleteWithPrivilege`、`manualOnly`、`unloadLaunchdThenTrash`。
- `warnings`：保存无法自动完成的清理知识，例如 TCC/Local Network/系统设置残留。

## 与当前 MacAppClean 的集成方式

### 1. 扩展扫描目录和启发式规则

当前 `RelatedFileResolver` 已覆盖 `Application Support`、`Caches`、`Preferences`、`Logs`、`WebKit`、`Saved Application State`、`Containers`、`Group Containers`。建议新增：

- `$HOME/Library/Application Scripts/$BUNDLE_ID`
- `$HOME/Library/HTTPStorages/$BUNDLE_ID`
- `$HOME/Library/Preferences/ByHost/$BUNDLE_ID.*.plist`
- `$HOME/Library/Caches/com.apple.helpd/Generated/$BUNDLE_ID*`
- `$HOME/Library/Logs/DiagnosticReports/$APP_NAME*`
- `$HOME/Library/Application Support/CrashReporter/$APP_NAME*`
- `/Library/Application Support/$APP_NAME`
- `/Library/Caches/$BUNDLE_ID`
- `/Library/Preferences/$BUNDLE_ID.plist`
- `/Library/LaunchAgents/$BUNDLE_ID*.plist`
- `/Library/LaunchDaemons/$BUNDLE_ID*.plist`
- `/Library/PrivilegedHelperTools/$BUNDLE_ID*`
- `/private/var/db/receipts/$BUNDLE_ID*.bom`
- `/private/var/db/receipts/$BUNDLE_ID*.plist`

这需要给 `RulePath.template` 增加 glob 支持，例如 `matchType: "exact" | "glob" | "prefix"`。没有 glob 时很多 ByHost、DiagnosticReports、receipts 无法优雅表达。

### 2. 构建 Homebrew Cask 导入器

新增离线脚本或 SwiftPM command plugin：

1. 读取 Homebrew/homebrew-cask 的 cask Ruby 文件。
2. 提取 `bundle_id`、`name`、`app`、`zap trash/delete/rmdir`。
3. 将 `~`、`~/Library/...`、`/Library/...` 标准化成 MacAppClean 模板。
4. 根据路径分类和风险：
   - `Caches`、`Logs`：low，默认选中。
   - `Preferences`、`Saved Application State`、`HTTPStorages`：medium，默认选中。
   - `Application Support`、`Containers`、`Group Containers`：high，默认不选或按 source confidence 判断。
   - `PrivilegedHelperTools`、`LaunchDaemons`、`receipts`：medium/high，需要权限或额外确认。
5. 输出 `KnowledgeBaseDocument` JSON，作为远端规则源或 bundled seed。

注意：解析 Ruby 不应靠简单正则硬切所有情况；可以先支持最常见的 `zap trash: [...]` 静态字符串，复杂 cask 标记为 `manualReviewRequired`。

### 3. 引入安全评分和删除策略

MacAppClean 应默认“移动到废纸篓”，不要永久删除。对每个候选文件显示：

- 命中来源：knowledge-base、heuristic、homebrew-zap、pkg-receipt、launchd-label。
- 风险：低/中/高。
- 默认选择状态。
- 是否 shared resource。
- 是否需要管理员权限。

建议默认策略：

- 低风险缓存/日志默认选中。
- 偏好设置、Saved State 默认选中。
- 用户数据、容器、Group Container、Steam 游戏库、浏览器 profile、开发工具配置默认不选。
- 系统级 LaunchDaemon、PrivilegedHelper、receipt 默认不选，提供“高级清理”流程。

### 4. 做“卸载”和“残留文件”双入口

参考 Mole 的分工：

- 应用程序页：app 仍存在时，使用 bundle id、签名、Info.plist、Homebrew cask token 做强匹配。
- 残留文件页：app 已不存在时，按 orphan 目录反推 owner，需要更高置信阈值。只对明确 bundle id / cask zap / pkg receipt 关联的路径默认勾选。

### 5. 更新现有 UI

当前 `RelatedFileCandidate` 已有 `matchedBy`，可以直接扩展展示：

- “规则来源：内置规则 / 远端规则 / Homebrew Zap / 启发式”
- “为什么匹配：bundle id、app 名称、路径模板、launchd label”
- “清理建议：建议清理 / 需确认 / 仅手动提示”

设置页已有远端规则 URL 和本地模式，建议增加：

- 规则源版本、更新时间、规则数量。
- “只使用内置规则”。
- “导入 Homebrew zap 规则”。
- “高风险项默认不勾选”开关。

## 优先级路线图

### P0：一周内可做

- 给 `RulePath` 增加 `matchType`，支持 exact/glob/prefix。
- 扩展启发式目录：HTTPStorages、ByHost、Application Scripts、system Library、receipts。
- UI 展示 `matchedBy` 和风险说明。
- 删除动作统一使用 `FileManager.trashItem`，并记录操作日志。

### P1：两到三周

- 新增 Homebrew Cask zap 导入脚本，生成 `rules.generated.json`。
- 增加 rule source metadata 和 confidence。
- 增加 orphan scan 的 owner 反推逻辑。
- 对 LaunchAgent/Daemon 增加 unload/bootout 提示或动作。

### P2：长期

- 建立远端知识库仓库，规则走 PR review。
- 支持用户上报“误报/漏报”但默认不上传本机应用列表。
- 支持 vendor uninstaller/manual instructions。
- 支持 pkg receipt 反查安装文件，但必须走只读预览和高风险确认。

## 参考来源

- Apple File System Programming Guide: macOS Library Directory Details  
  https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/MacOSXDirectories/MacOSXDirectories.html
- Apple Developer Documentation: Accessing files from the macOS App Sandbox  
  https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
- Homebrew Cask Cookbook: zap stanza  
  https://docs.brew.sh/Cask-Cookbook
- Pearcleaner  
  https://github.com/alienator88/Pearcleaner
- Mole  
  https://github.com/tw93/mole
- MacSift  
  https://github.com/Lcharvol/MacSift
- MyMacCleaner  
  https://github.com/Prot10/MyMacCleaner
- AppCleaner  
  https://freemacsoft.net/appcleaner/
