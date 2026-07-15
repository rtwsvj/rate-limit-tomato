# Rate Limit Tomato 外部审计交接

> **给审计者：请从零验证，不要把本文件、既有审计结论或绿色 CI 当作正确性的替代品。**
>
> 本文件是公开源码审计的入口和证据索引，不改变 [SPEC.md](SPEC.md) 的产品语义，也不预设“没有 bug”。建议先保持只读，形成 findings 后再讨论修复。

可直接转发给审计者：

> 请对 <https://github.com/rtwsvj/rate-limit-tomato> 做一次从零开始的只读对抗性审计。以 `SPEC.md` 为产品事实源，不要把现有测试、CI 或旧审计结论当作证明；先复核代码基线 `2a0b04b6a053610bfcf975d3c03b1930c432d52e`，再按本文件第 7 节优先攻击真实 sleep/restart、持久化失败、首次免责绕过、运行时网络、macOS 系统接线和发布签名链。请按 P0–P3 输出文件/行号、证据、最小复现、影响、修复建议、置信度及未覆盖范围；先不要改代码。

## 1. 审计快照

| 项目 | 交接事实 |
|---|---|
| 公开仓库 | <https://github.com/rtwsvj/rate-limit-tomato> |
| 代码基线 | `2a0b04b6a053610bfcf975d3c03b1930c432d52e` |
| 工作区版本 | `3.2.2` |
| 最新代码 CI | [run 29378835493](https://github.com/rtwsvj/rate-limit-tomato/actions/runs/29378835493)，对应上述代码基线，结论为 success |
| 当前分发边界 | **源码优先**；没有已公证、可作为稳定版公开分发的二进制 |
| 许可证 | MIT；直接依赖声明见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) |

本交接文档之后若仅出现文档提交，请用下列命令确认实际产品代码相对基线是否变化：

```bash
git diff --stat 2a0b04b6a053610bfcf975d3c03b1930c432d52e..HEAD
git diff --name-only 2a0b04b6a053610bfcf975d3c03b1930c432d52e..HEAD
```

交接时的公开仓库没有公开 tag 或 Release。Actions 中的 ad-hoc artifact 是短期 CI 证据，不是稳定发行包。公开仓库当前也没有 branch protection 或 repository ruleset；Secret Scanning、Push Protection 和 Dependabot security updates 已开启。这些 GitHub 设置会变化，审计时应重新查询，不能只引用本快照。

## 2. 范围与证据限制

本次建议审计以下内容：

- 公开 `main` 及其可达 Git refs；
- `Sources/`、`Tests/`、`scripts/`、SwiftPM 依赖锁和公开文档；
- 从源码生成的本地 ad-hoc `.app`、ZIP 以及实际 macOS 系统接线；
- 产品红线、故障恢复、状态机、持久化、可访问性和发布链路声明。

明确不在现有证据范围内：

- 公开前不可达的维护历史；公开 clone 无法据此判断旧历史是否曾含秘密或受限内容；
- 已公证的正式发行包，因为当前不存在此类公开产物；
- Apple 公证、stapling、quarantine 下载和 Gatekeeper 最终验收；
- 仅凭 4 秒隔离冒烟推导长期运行、完整系统生命周期或操作系统级网络隔离。

## 3. 五分钟阅读顺序

发生冲突时，按以下顺序判断：

1. [SPEC.md](SPEC.md)：唯一产品事实源，包括状态机、数据和不可妥协红线；
2. [CHANGES.md](CHANGES.md)：对 SPEC 的已接受工程裁决；
3. [UI-SPEC.md](UI-SPEC.md)：视觉、交互与可访问性表现；
4. [STATUS.md](STATUS.md)：当前实现证据和未完成边界；
5. [2026-07-14 开源准备审计](audits/2026-07-14-open-source-readiness.md)：既有结论，只能作为待复核的 claim；
6. [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) 与 [APP-SMOKE-CHECKLIST.md](APP-SMOKE-CHECKLIST.md)：发布和真实系统验收门禁。

## 4. 架构与信任边界

| 区域 | 职责 | 审计重点 |
|---|---|---|
| `Sources/TomatoCore/` | 平台中立状态机、数据模型、JSON 持久化、i18n、热力图和假数据 | 业务不变量、时间边界、损坏数据、原子写入、恢复与迁移 |
| `Sources/RateLimitTomatoUI/` | `AppViewModel`、SwiftUI、主题、通知、快捷键、URL Scheme、ticker、登录项 | 首次免责门禁、并发/主线程、系统权限、动作只执行一次 |
| `Sources/RateLimitTomato/` | 最小 `@main`、`MenuBarExtra` 与 AppDelegate 壳 | 冷启动、单实例、URL 事件装配和生命周期 |
| `Tests/` | Core、UI 接线和 ImageRenderer 快照 | 测试是否真的命中失败分支，是否把 mock 结果夸大成系统验证 |
| `scripts/` | 红线、公开树、构建、签名、验证、冒烟、归档、公证和 release manifest | shell 注入、失败传播、架构/资源遗漏、签名和归档事务性 |
| `Package.swift` / `Package.resolved` | 三个直接 SwiftPM 依赖及锁定版本 | 依赖源码、许可证、构建期网络和供应链可重复性 |

核心业务逻辑原则上应位于 `TomatoCore` 并使用可注入 `TomatoClock`。UI 接线集中在 `@MainActor AppViewModel`；这降低了数据竞争面，但不能自动证明磁盘 I/O 不会阻塞菜单栏 UI。

## 5. 不可妥协的产品红线

审计中发现任何违反以下条款的路径，应至少视为发布阻断：

1. 不接真实支付、不收集支付信息、不打开购买或订阅 URL；
2. 已交付界面、元数据和公开资产不使用真实厂商名称、商标、Logo 或专有品牌文案；
3. 应用运行时代码不联网、无遥测、无账号、无上传和云同步；SwiftPM 首次解析依赖的构建期网络不属于运行时承诺；
4. 所有套餐、价格、额度、token、响应头和用量数字均为虚构；
5. 升级/定价界面永久显示免责说明；
6. 首次启动在确认免责前，所有会改变状态的入口都必须被阻止；
7. 唯一升级 CTA 是 `Send more messages with Pro →`，只能产生本地虚构反馈。

当前声明是“实现层没有运行时网络请求”，不是“App Sandbox 或操作系统强制隔离网络”。请同时审查应用源码、锁定依赖和打包产物，避免把源码扫描当成完整证明。

## 6. Claim → 证据 → 缺口

| 待验证声明 | 现有证据入口 | 仍需独立验证 |
|---|---|---|
| 25/5 核心循环和崩溃恢复正确 | `TomatoEngine.swift`、Engine/Crash/StaleQuota 测试 | 真实 sleep/wake、冷重启、跨午夜和系统时钟回拨 |
| 完成会话不会丢失或重复 | `AppViewModel.swift`、`TomatoStore.swift`、持久化故障测试 | 跨文件写入中途退出、磁盘满/权限错误、连续多次失败后崩溃 |
| 首次免责覆盖全部动作入口 | AppViewModel、Sheets 和门禁回归测试 | 菜单、快捷键、URL、通知、ticker 与升级按钮的真实冷/热路径 |
| 运行时零网络、零支付、品牌中立 | `check-redlines.sh`、`check-public-tree.sh`、包扫描、隔离冒烟 | 锁定依赖源码审查和更长时间的实际网络观察 |
| ad-hoc 包结构完整 | `make-app.sh`、`verify-app.sh`、`archive-app.sh`、最新 CI | 独立机器重建、ZIP 往返、资源 bundle、最低系统和双架构运行 |
| 系统通知、快捷键、URL、登录项可用 | 注入式测试与打包 smoke | 干净 macOS 账户上的 TCC、冲突、登录/注销及单实例行为 |
| 基础可访问性成立 | 语义测试、Reduce Motion 分支和快照 | VoiceOver、Full Keyboard Access、实际对比度与缩放 |
| 可公开分发稳定二进制 | 当前**没有该 claim** | Developer ID、hardened runtime、secure timestamp、公证、stapling、quarantine Gatekeeper 和上传哈希闭环 |

## 7. 优先审查清单

下面按真实用户影响和发布风险排序。不要因既有测试通过而跳过失败注入或真实系统验证。

### P0/P1 候选面

1. **最终会话的持久化与崩溃恢复**
   - 入口：`Sources/RateLimitTomatoUI/AppViewModel.swift` 中的 `persistFinalizedSessionIfNeeded`、`persistQuotaAndSnapshot`；`Sources/TomatoCore/TomatoStore.swift` 中的 `flush`、`processDirty`。
   - 假设：跨 sessions/quota/engine 三个文件的退出时序可能造成最后一次完成记录丢失、重复或恢复快照过早清除。
   - 验证：分别注入三类写入失败，并在每一个中间点强制退出后重启。

2. **sleep/wake 的多阶段追赶**
   - 入口：`TomatoEngine.tick`、`AppViewModel` catch-up、`TickerService`。
   - 假设：一次休眠跨越专注结束、冷却结束和次日边界时，live wake 与 cold restart 可能得出不同结果。
   - 验证：正常完整周期、跨午夜和长时间休眠都比较实时唤醒与冷启动恢复。

3. **日切、午夜和时钟回拨**
   - 入口：`Sources/TomatoCore/TomatoEngine.swift` 与 StaleQuota/CrashHardening/Engine 测试。
   - 假设：23:59 会话、时区/日历变化或系统时间回拨可能错误重置额度、重复计数或产生负时长。

4. **损坏 JSON、事务导入和原子替换**
   - 入口：`Sources/TomatoCore/TomatoStore.swift` 的加载、导入、备份、提交和原子写入路径。
   - 假设：截断文件、磁盘满、权限错误或 backup/commit 中途失败时，磁盘与内存状态可能不一致。

5. **首次免责是否真正封锁所有状态变更**
   - 入口：`AppViewModel.swift`、`Sheets.swift`，以及快捷键、URL、通知、ticker 和设置入口。
   - 假设：应用装配完成前到达的动作，或从系统服务绕过 UI 的动作，可能在确认前改变状态。

6. **零网络、零支付、零真实品牌**
   - 入口：`scripts/check-redlines.sh`、`scripts/smoke-app.sh`、`Package.swift`、`Package.resolved` 和升级/定价视图。
   - 假设：源码字符串扫描可能漏掉依赖、动态行为、元数据或非文本资产。

### P1/P2 系统与发行面

7. **URL Scheme 冷启动、热启动与单实例**
   - 入口：`URLCommandService.swift`、`RateLimitTomatoApp.swift`、`make-app.sh`、`MenubarPanel.swift`。
   - 验证六条 `rlt://` 命令在未启动/已启动两种状态下均恰好执行一次，且不产生第二个进程。

8. **通知、全局快捷键与 Launch at Login**
   - 入口：`NotificationService.swift`、`Shortcuts.swift`、`SettingsView.swift`。
   - 在干净 macOS 账户测试拒绝/允许通知、快捷键冲突、登录/注销和登录项移除。

9. **运行时设置、i18n 与可访问性**
   - 入口：`Models.swift`、`AppViewModel.swift`、`L10n.swift` 和所有主要视图。
   - 切换语言、主题和 Reduce Motion；使用 VoiceOver 与 Full Keyboard Access 完成全流程。

10. **Universal 包、资源 bundle 与 macOS 14**
    - 入口：`make-app.sh`、`verify-app.sh`、`archive-app.sh` 和 `.github/workflows/ci.yml`。
    - 验证 arm64/x86_64 slices、SPM `*.bundle`、版本、签名、ZIP 往返及真实最低系统启动。

11. **Developer ID、公证和 release 事务**
    - 入口：`make-app.sh`、`notarize-app.sh`、`release-manifest.sh`、[RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md)。
    - 当前 CI 只证明 ad-hoc 路径。正式发布必须在合法凭据和独立环境中验证失败回滚、notary ticket、stapler、`spctl` 和 quarantine。

12. **版本、tag、release notes 与供应链**
    - 入口：`check-version.sh`、tagged-release CI job、`Package.swift`、`Package.resolved`、`check-public-tree.sh`。
    - 当前公开远端没有 tag，最新 CI 的 tagged-release job 因 main push 而跳过。未来正式二进制应使用新版本和对应 release notes，不要把旧的 `3.2.2` 重新标记为新公开发行。

## 8. 可重复验证命令

以下命令故意不包含维护者本机 wrapper，外部 clone 可直接执行。

### 8.1 基线与统一质量门

```bash
git clone https://github.com/rtwsvj/rate-limit-tomato.git
cd rate-limit-tomato
git status --short
git rev-parse HEAD
swift --version
xcodebuild -version
bash scripts/verify.sh
bash scripts/check-redlines.sh
bash scripts/check-public-tree.sh
```

`verify.sh` 已包含版本契约、红线、公开树、diff whitespace、锁定依赖构建和完整测试。额外单独执行红线/公开树检查便于保留清晰日志。

### 8.2 聚焦回归

```bash
swift test --only-use-versions-from-resolved-file \
  --filter 'AppViewModelTests|TomatoStoreHardeningTests'

swift test --only-use-versions-from-resolved-file \
  --filter 'TomatoEngineTests|StaleQuotaResetTests|CrashHardeningTests'
```

### 8.3 本机 ad-hoc 包

```bash
bash scripts/make-app.sh \
  --configuration release \
  --arch current \
  --sign adhoc \
  --output-dir dist/external-audit

bash scripts/verify-app.sh \
  --app dist/external-audit/RateLimitTomato.app \
  --arch current \
  --sign adhoc \
  --require-release

bash scripts/smoke-app.sh \
  --app dist/external-audit/RateLimitTomato.app

bash scripts/archive-app.sh \
  --app dist/external-audit/RateLimitTomato.app \
  --label adhoc \
  --output-dir dist/external-audit
```

在具备双架构工具链的机器上，将构建和验证命令的 `--arch current` 改为 `--arch universal`。

### 8.4 快照

```bash
RLT_SNAPSHOT_DIR=/tmp/rlt-snapshots \
  swift test --filter RLTSnapshotTests
```

快照测试依赖 AppKit/ImageRenderer，不能用 Intel job 跳过快照这一事实推导 Intel 视觉结果已验证。

## 9. 人工验收清单

至少在一个干净 macOS 14 账户和另一台独立 Mac 上记录屏幕、系统版本、CPU、包 SHA-256 和每项结论：

- [ ] 首次启动免责阻止菜单、快捷键、URL、通知和设置写入，确认后才解锁；
- [ ] 25 分钟专注、5 分钟冷却、完成、中止、跳过与额度恢复均符合 SPEC；
- [ ] 真实 sleep/wake、跨午夜、改时钟和冷重启不丢失或重复会话；
- [ ] 六条 URL 命令在冷/热启动各执行一次且维持单实例；
- [ ] 通知允许/拒绝、快捷键冲突和 Launch at Login 的登录/注销生命周期正确；
- [ ] VoiceOver、Full Keyboard Access、Reduce Motion、三主题和双语界面可用；
- [ ] 长时间运行网络观察无 socket、无上传、无购买 URL；
- [ ] arm64、Intel/Rosetta、SPM 资源 bundle 和 macOS 14 启动通过；
- [ ] ZIP 解包后哈希、签名、版本、资源和隔离 smoke 与归档前一致；
- [ ] 若评估正式发行，再单独验证 Developer ID、公证、stapling、quarantine 与 Gatekeeper。

更细的逐项步骤见 [APP-SMOKE-CHECKLIST.md](APP-SMOKE-CHECKLIST.md)。

## 10. 已知限制与剩余风险

这些项目没有被隐藏，也不应被自动升级为 blocker；请根据可复现影响定级：

- 历史文件接近 64 MiB 上限时，编码和原子写入位于主 actor 调用链，可能短暂阻塞菜单栏 UI；
- 持久化持续失败期间，单一恢复快照只保证一个恢复点；如果用户继续完成多个会话后进程崩溃，后续仅在内存中的记录可能丢失；
- 恢复追赶有十年产品上限，这是显式防御边界；无需在穷举每一秒上消耗审计时间；
- 通知 TCC、URL 冷/热启动、Launch at Login、VoiceOver、Full Keyboard Access、真实 sleep/wake 和 logout/login 尚未完成独立人工闭环；
- 当前没有 Apple 公证、stapling、真实下载 quarantine 或 Gatekeeper 证据；
- 构建首次解析依赖需要联网；运行时零网络是源码和行为承诺，不是 App Sandbox 强制；
- `URLCommandService.swift` 与 `NotificationService.swift` 的源码注释仍引用已移出公开树的旧文档名，属于注释文档债，不影响运行时；
- README 使用仓库内社交预览图，但 GitHub 仓库设置是否另行上传 custom social preview 仍应人工确认。

审计时间优先投入真实 sleep/restart、磁盘失败、免责绕过、系统集成、网络行为和签名/公证链。除非已有真实影响证据，不建议把主要时间用于逐字节穷举 64 MiB 边界、十年窗口的每一秒、病态 Unicode/NaN 重复组合，或 AppViewModel 装配前连续发送多条 URL 命令。

## 11. 已有 CI 能证明什么

[run 29378835493](https://github.com/rtwsvj/rate-limit-tomato/actions/runs/29378835493) 对代码基线证明：

- macOS 15 arm64 完成 261 项测试，其中含 5 项快照测试；
- macOS 15 Intel 完成 256 项非渲染测试，按工作流设计跳过快照；
- universal ad-hoc candidate 的 arm64/x86_64 slices、签名、资源、版本、红线、ZIP 往返和隔离 smoke 通过；
- macOS 14.8.7 arm64 对同一 universal ad-hoc 包完成哈希、解包、完整性和 4 秒隔离启动 smoke；
- tagged-release contract 在该 main push 中是 skipped，不应表述为已通过；
- CI 的外部环境警告不等于仓库自有 Swift 源码“零警告”。

这些证据不证明没有 bug，不替代独立重跑，也不证明长期零网络、真实 TCC、Apple 公证或正式发行质量。

## 12. 审计交付格式

请输出一个可复核报告，至少包含：

1. **结论**：可接受 / 有条件接受 / 阻断；
2. **Findings**：按 P0–P3 排序，每项给出文件与行号、证据、最小复现、用户影响、建议修复和置信度；
3. **Claims matrix**：分别标记 verified、refuted、not tested，避免把“未发现”写成“已证明不存在”；
4. **执行记录**：提交 SHA、系统/CPU/工具链、完整命令和退出码；
5. **人工证据**：截图、系统日志、网络观察、包哈希及复现环境；
6. **剩余风险**：说明哪些边界因设备、凭据、时间或范围限制未覆盖。

建议严重级别：

| 级别 | 定义 |
|---|---|
| P0 | 数据破坏、真实付款/外联/秘密泄露，或广泛无法启动；立即阻断 |
| P1 | 常见路径的数据丢失、红线绕过、主要功能失效或正式发布链不可信；发布前修复 |
| P2 | 有现实触发条件的功能、性能、可访问性或可维护性缺陷；排期修复 |
| P3 | 低影响、表述、注释或仅改善防御深度的问题；记录即可 |

请先提交只读 findings。除非维护者明确委托修复，不要一边审计一边改代码，以免丢失原始证据。
