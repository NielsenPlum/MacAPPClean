# MacAppClean TODO（基于当前仓库与既有讨论整理）

> 更新时间：2026-05-31
> 说明：以下按优先级拆解为可执行任务；默认以“完成后可验证”为准。

## P0（本周先完成）

- [ ] 为 `RulePath` 增加匹配类型（`exact` / `glob` / `prefix`）
  - 涉及：`KnowledgeBaseModels`、规则解析、`RelatedFileResolver`
  - 验收：现有规则不回归；新增单测覆盖三种匹配类型

- [ ] 扩展关联文件扫描目录（补齐高价值路径）
  - 目标新增：`Application Scripts`、`HTTPStorages`、`Preferences/ByHost`、系统级 `Application Support/Caches/Preferences`、`LaunchAgents/LaunchDaemons`、`PrivilegedHelperTools`、`/private/var/db/receipts`
  - 验收：针对至少 2 个样例 app 能识别新增路径；风险分级正确

- [ ] 在 UI 明确展示“匹配依据 + 风险说明”
  - 展示项：`matchedBy` 来源、风险等级、默认勾选原因
  - 验收：在关联文件列表可直接看到每项“为何命中”

- [ ] 删除路径统一走“移入废纸篓 + 操作记录”
  - 目标：所有删除入口统一通过 `trashItem`，并写入删除清单
  - 验收：单项删除和批量删除都能在“删除清单”中恢复

## P1（2-3 周）

- [ ] 增加 Homebrew Cask zap 导入脚本（生成规则）
  - 输出：`rules.generated.json`（可用于远端规则源或本地 seed）
  - 规则：先支持常见 `zap trash: [...]` 静态路径；复杂 cask 标记为人工复核
  - 验收：导入结果可被现有 KnowledgeBase 正常加载

- [ ] 给规则增加来源元数据与置信度
  - 建议字段：`source`、`confidence`、`ownership`、`warnings`
  - 验收：UI 或日志可追溯规则来源及风险依据

- [ ] 残留文件（orphan）增强：按 owner 反推归属
  - 思路：结合 bundle id、目录命名、规则来源做高置信匹配
  - 验收：误报率下降；默认勾选仅限高置信项

- [ ] LaunchAgent/LaunchDaemon 处理流程补全
  - 目标：在删除前提供 unload/bootout 提示或引导
  - 验收：用户能明确看到“需要额外操作”的项目

## P2（工程化与质量门禁）

- [ ] 完善测试矩阵（核心逻辑优先）
  - 补齐：版本比较、残留过滤、删除记录恢复状态、规则冲突优先级
  - 验收：`swift test` 覆盖关键分支且稳定

- [ ] 扩展本地验收脚本
  - 现有：`script/verify_app.sh`
  - 新增建议：扫描输出结构校验、图标资源校验、权限缺失场景提示校验
  - 验收：脚本失败时能给出可定位错误信息

- [ ] 建立 CI 守门（最小可用）
  - 目标：自动执行 `swift build` + `swift test`
  - 验收：PR/提交可见构建与测试状态

## 你当前最先做的 3 件事（建议顺序）

- [ ] 1. `RulePath` 匹配类型改造 + 单测
- [ ] 2. 扫描目录扩展（含 ByHost/HTTPStorages/receipts）
- [ ] 3. 关联文件列表增加“匹配依据”展示

## 完成定义（DoD）

- [ ] 代码可编译：`swift build`
- [ ] 测试通过：`swift test`
- [ ] 基础验收通过：`./script/verify_app.sh`
- [ ] 关键流程手测：扫描 → 选择 → 移入废纸篓 → 删除清单恢复
