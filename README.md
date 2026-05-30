# MacAppClean — macOS 应用清理与卸载工具

复刻 [app-cleaner.com](https://app-cleaner.com/) 核心功能，全中文界面。

## 功能特性

| 模块 | 说明 |
|------|------|
| **应用程序** | 扫描 `/Applications` 和 `~/Applications`，连带服务文件、缓存、偏好设置、日志、容器等一起卸载 |
| **启动项** | 检测 `~/Library/LaunchAgents` 中的后台项目，管理登录项 |
| **扩展** | 扫描 Safari 扩展 (`~/Library/Safari/Extensions`) 和系统扩展 (`/Library/Extensions`) |
| **残留文件** | 在 `Library/Application Support`、`Caches`、`Preferences`、`Containers` 等目录中查找已卸载应用的残留 |
| **大文件** | 扫描桌面、下载、文稿文件夹中超过 100MB 的文件 |
| **安全检查** | 验证应用的代码签名和公证状态 |
| **更新** | 检测可用的应用更新 |

## 技术栈

- **语言**: Swift 5.9
- **框架**: SwiftUI + Observation
- **最低系统**: macOS 14.0 (Sonoma)

## 构建与运行

```bash
# 直接构建并运行
./script/build_and_run.sh

# 仅验证构建
./script/build_and_run.sh --verify

# 调试模式
./script/build_and_run.sh --debug

# 查看日志
./script/build_and_run.sh --logs
```
