# Rate Limit Tomato 文档入口 · Documentation

本目录维护产品事实、实现状态、公开发布边界和可重复验证清单。根目录 [README](../README.md) 面向使用者；这里的规范面向维护者与贡献者。

This directory contains the product contract, implementation status, public-distribution boundaries, and repeatable verification checklists. The root [README](../README.md) is user-facing; these documents are for maintainers and contributors.

## 文档优先级 · Authority

发生冲突时，按下表从上到下处理：

| 优先级 | 文档 | 职责 |
|---|---|---|
| 1 | [SPEC.md](SPEC.md) | 产品语义、状态机、数据定义、不可妥协红线和规范性 DoD；唯一产品事实源 |
| 2 | [CHANGES.md](CHANGES.md) | 对 SPEC 的已批准工程裁决；裁决应同步回 SPEC |
| 3 | [UI-SPEC.md](UI-SPEC.md) | 视觉、交互和可访问性表现，不覆盖产品语义或红线 |
| 4 | [STATUS.md](STATUS.md) | 当前实现、验证级别、历史发布事实与未完成边界 |
| 5 | [OPEN_SOURCE_LAUNCH.md](OPEN_SOURCE_LAUNCH.md) | 源码优先的公开说明、宣传口径和公开二进制门禁 |
| 6 | [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) | 构建、签名、公证、归档与发布的重复执行门禁 |
| 7 | [APP-SMOKE-CHECKLIST.md](APP-SMOKE-CHECKLIST.md) | 真实 `.app` 系统接线与人工验收清单 |
| 8 | [DEPENDENCIES.md](DEPENDENCIES.md) | 直接依赖、锁定版本、用途与许可证来源 |
| 9 | [2026-07-14 开源准备审计](audits/2026-07-14-open-source-readiness.md) | 对抗性复审、发布阻断结论和可复现验证证据 |
| 10 | [`assets/`](assets/) | 品牌中立的社交预览、真实截图和公开视觉资产 |

根目录 [CHANGELOG.md](../CHANGELOG.md) 只记录用户可感知变化；Git 历史、CI 记录、Release manifest 和 SHA 清单承担可追溯证据，不在公开树中保存私人会话或代理执行日志。

## 公开文档规则 · Public-document rules

1. 公开 README、截图、发布说明和 Bundle 元数据必须品牌中立，不使用真实厂商名称、Logo、专有文案或购买链接。
2. “不联网”指应用运行时实现不发起网络请求；不得将其夸大为 App Sandbox 或操作系统强制隔离。
3. 未完成 Apple 公证、stapling 和 Gatekeeper 验证时，不得出现“下载即用”“稳定公开版”或同义宣传。
4. 所有额度、套餐、价格与升级交互必须明确为虚构；永远不接支付、不收集支付信息、不打开付费 URL。
5. 截图使用确定性假数据，不得包含真实用户名、绝对路径、通知内容或其他用户数据。
6. 公开树不得保存私人对话、用户授权记录、本机绝对路径、凭据状态或工具特定会话日志。

## 维护规则 · Maintenance

1. 产品语义或红线变化先更新 `SPEC.md`，并在 `CHANGES.md` 记录客观工程理由。
2. 实现变化同步更新 `STATUS.md`；不得用 SPEC 的 DoD checkbox 冒充完成证据。
3. 面向公众的声明必须区分“源码已验证”“本机已验证”“远端 CI 已验证”和“人工系统验收已完成”。
4. 发布前逐项执行 `RELEASE-CHECKLIST.md`；公开二进制还必须完成公证与干净系统 Gatekeeper 验收。
5. 新增第三方依赖时，同步更新根目录 `THIRD_PARTY_NOTICES.md` 和发行包内 notices。
6. 视觉资产变更后重新检查品牌、个人数据、免责文案和图片替代文本。
