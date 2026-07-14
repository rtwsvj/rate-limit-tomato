# Open-source Launch · 开源发布说明

![Rate Limit Tomato — When you hit 429, take five.](assets/social-preview.png)

> **When you hit 429, take five. · 让 429 替你喊停。**

本文定义 Rate Limit Tomato 的公开介绍、源码优先分发方式和未来公开二进制必须满足的门禁。它不替代 [产品规格](SPEC.md)、[实现状态](STATUS.md) 或 [发布检查清单](RELEASE-CHECKLIST.md)。

This document defines the public story, source-first distribution model, and gates required for a future public binary. It does not replace the [product specification](SPEC.md), [implementation status](STATUS.md), or [release checklist](RELEASE-CHECKLIST.md).

## 当前结论 · Current position

| 项目 | 当前口径 |
|---|---|
| 源码 | 源码优先；通过 Git 仓库审阅、构建和运行 |
| 系统要求 | macOS 14+；Swift tools 5.9 兼容工具链 |
| 公开稳定二进制 | **暂无** |
| 旧工程预发布资产 | 已从公开分发面撤下；不提供未公证下载 |
| 推荐体验方式 | 从源码运行，或在本机生成仅供自己使用的 ad-hoc `.app` |
| 隐私模型 | 运行时代码无网络请求、遥测、账号或云同步；不是 App Sandbox 强制隔离声明 |

The launch is source-first. There is currently **no public stable binary** that is Apple-notarized and ready for normal Gatekeeper installation. Previous private engineering artifacts are not exposed as general-user downloads.

## 产品介绍 · Product story

Rate Limit Tomato 是一款 macOS 菜单栏番茄钟，把虚构的 API 限流语义变成真正可用的专注节律：发起一次 “fast request”，专注一个番茄；遇到 `429 Too Many Requests`，就离开屏幕休息五分钟。

Rate Limit Tomato is a macOS menu-bar Pomodoro that turns fictional API rate-limit semantics into a practical focus rhythm: send one “fast request,” focus for one Pomodoro, and step away for five minutes when the app returns `429 Too Many Requests`.

| Focus · 专注 | Rate limited · 休息 |
|---|---|
| ![正在进行的虚构 fast request](assets/screenshots/a3-focusing.png) | ![虚构的 429 限流休息界面](assets/screenshots/a5-ratelimited.png) |

![由本机专注数据生成的年度活动网格](assets/screenshots/x5-heatmap-grid.png)

建议公开短文案：

> **Local-first focus, wrapped in fictional rate limits.**
>
> **把限流焦虑，变成离开屏幕的理由。**

## 可以公开承诺的事实 · Claims we can make

### Local by implementation · 实现层本地优先

- 应用运行时代码不发起网络请求。
- 不含遥测、账号、云同步或远端配置。
- 专注记录保存在 `~/Library/Application Support/RateLimitTomato/`。
- 首次解析 SwiftPM 依赖和克隆源码需要开发环境联网；这不属于应用运行时行为。
- 当前构建不宣称由 App Sandbox 强制阻断网络或文件访问。

- The app contains no runtime network-request code.
- It has no telemetry, account, cloud sync, or remote configuration.
- Focus history is stored under `~/Library/Application Support/RateLimitTomato/`.
- Cloning the source and resolving SwiftPM dependencies require build-time network access.
- The current build does not claim App Sandbox enforcement.

### Parody without payment · 戏仿而非收费

- 所有额度、套餐、价格、响应头、错误码和升级提示均为虚构。
- 不集成 StoreKit 或第三方支付，不收集支付信息，不打开购买/订阅 URL。
- 首次使用必须确认戏仿免责声明；升级/定价弹窗永久展示免责小字。
- 公开文案、截图、Bundle 元数据与运行时 UI 保持品牌中立。
- 本项目与任何 AI 厂商均无隶属、合作、授权或背书关系。

- Every quota, plan, price, response header, status code, and upgrade prompt is fictional.
- No real payment is processed, no payment data is collected, and no purchase URL is opened.
- The first-run disclaimer precedes use; upgrade and pricing surfaces retain a permanent disclaimer.
- Public copy, screenshots, bundle metadata, and runtime UI remain vendor-neutral.
- The project is not affiliated with, authorized by, or endorsed by any AI vendor.

## 现在如何体验 · How to try it now

```bash
git clone https://github.com/rtwsvj/rate-limit-tomato.git
cd rate-limit-tomato
swift build
swift test
bash scripts/verify.sh
swift run RateLimitTomato
```

`swift run` 没有完整 App bundle，因此系统通知与 `rlt://` 会降级为 no-op。需要在本机测试完整 `.app` 形态时：

`swift run` does not provide a full App bundle, so notifications and `rlt://` safely degrade to no-op. For a local packaged build:

```bash
bash scripts/make-app.sh \
  --configuration release \
  --arch current \
  --sign adhoc
```

该 ad-hoc App 仅用于本机开发与验证，不是官方公开二进制。

The ad-hoc app is for local development and verification only. It is not an official public binary.

## 未来公开二进制门禁 · Gates for a future public binary

只有以下条件全部满足，README 和 Release 才能出现公开下载 CTA：

- [ ] 从干净提交构建 release universal App，版本、tag、manifest 和归档名一致。
- [ ] Developer ID 签名、hardened runtime 和 secure timestamp 验证通过。
- [ ] Apple notarization 成功，ticket 已 stapled，`stapler validate` 通过。
- [ ] `spctl --assess` 在带 quarantine 的真实下载包上接受。
- [ ] ZIP 解包后重新验证签名、架构、最低 macOS、资源 bundle 和 SHA-256。
- [ ] 在干净 macOS 14 环境验证首次启动、通知、URL Scheme、开机自启和卸载路径。
- [ ] 验证 Apple silicon、Intel/Rosetta、VoiceOver、Full Keyboard Access 与 Reduce Motion。
- [ ] 完整远端 CI 绿色，未把 Billing、runner 或跳过 job 误记为通过。
- [ ] App/ZIP 内包含第三方许可证 notices；公开资产不含真实用户数据或厂商品牌。
- [ ] Release body 明确隐私、戏仿、系统要求、安装、校验和已知限制。

Until every item is complete, distribution remains source-first and no stable-download claim is allowed.

在全部门禁完成前，分发方式保持源码优先，不得声称存在稳定公开下载版。

## 完整性与许可证 · Integrity and licenses

- 项目源码采用 [MIT License](../LICENSE)。
- 第三方组件及许可证见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。
- 旧工程 ZIP、manifest 与 `SHA256SUMS` 仅在私有归档中用于追溯，不作为公开下载。
- 公开二进制必须同时提供可验证的 SHA-256 和来源 manifest。

- Project source is available under the [MIT License](../LICENSE).
- Third-party components and licenses are listed in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
- Previous ZIPs, manifests, and `SHA256SUMS` remain private engineering records, not public downloads.
- Any future public binary must include a verifiable SHA-256 checksum and provenance manifest.

## 维护本说明 · Maintaining this document

只有当 [STATUS.md](STATUS.md) 和发布证据都已更新时，才能改变本文件的分发状态。视觉与宣传文案变化必须继续满足：品牌中立、纯虚构额度、无真实支付、运行时无网络请求、无真实用户数据。

Change the distribution status here only after [STATUS.md](STATUS.md) and the release evidence have been updated. Visuals and launch copy must remain vendor-neutral, entirely fictional in quota/payment semantics, free of real user data, and accurate about runtime networking.

## 宣传素材包 · Launch copy kit

### GitHub description

> A local-only macOS menu bar Pomodoro that turns AI rate limits into focus breaks. No account, telemetry, or real payments.

### 一句话介绍 · One-liner

> 让 429 替你喊停：一款把虚构限流变成真实休息节律的本地 macOS 菜单栏番茄钟。

> When you hit 429, take five: a local macOS menu-bar Pomodoro wrapped in fictional rate limits.

### 中文发布帖

> 我把“又限流了”的体感做成了一款番茄钟：Rate Limit Tomato。发起一次虚构请求，就专注一个番茄；看到 429，就真的离开屏幕休息五分钟。它是 macOS 菜单栏应用，专注记录纯本地，没有账号、遥测、云同步或真实支付。源码现已开放；公开二进制会等 Apple 公证与 Gatekeeper 验证全部完成后再提供。

### English launch post

> I turned the feeling of hitting a rate limit into a reason to step away from the screen. Rate Limit Tomato is a local-only macOS menu-bar Pomodoro: one fictional request starts a focus session, and 429 means it is time to take five. No account, telemetry, cloud sync, or real payment. The source is open now; a public binary will wait for notarization and full Gatekeeper verification.

### 素材清单 · Asset inventory

- Social preview: [`assets/social-preview.png`](assets/social-preview.png) — 1280×640
- App icon source: [`assets/brand/app-icon-source.png`](assets/brand/app-icon-source.png)
- Focus screenshot: [`assets/screenshots/a3-focusing.png`](assets/screenshots/a3-focusing.png)
- 429 break screenshot: [`assets/screenshots/a5-ratelimited.png`](assets/screenshots/a5-ratelimited.png)
- Activity grid screenshot: [`assets/screenshots/x5-heatmap-grid.png`](assets/screenshots/x5-heatmap-grid.png)

All promotional assets use fictional data and original, vendor-neutral visuals.
