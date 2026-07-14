# Rate Limit Tomato · UI 设计规格 v2

> 当前 UI 表现层蓝图。产品语义与红线以 docs/SPEC.md 为准；本文件只规定视觉、交互与可访问性，不得覆盖产品语义。实现进度见 docs/STATUS.md。
> 执行规则：本文未写的按此处设计系统推导，**不得自创布局/颜色/字号**。

## 0. 设计立场

Provider A 温暖纸面主题的四个支柱，v1 全部缺失，v2 逐条落实：

1. **衬线显示字体做情绪时刻**：大标题（Ready / Usage limit reached）用衬线（SwiftUI `.fontDesign(.serif)` → New York），是"温柔纸感"的主要来源。正文/控件回到 SF Pro。
2. **一屏一橙**：#D97757 每屏最多出现在一个主要元素（主按钮或进度条），其余全部米灰。橙多即廉价。
3. **留白即质感**：面板 padding 20，段落间距只用 4/8/12/16/20/24 六档，不出现奇数魔法值。
4. **代码块是戏仿的舞台**：假 headers/JSON/log 一律放在“深一度米色”码块（#EEECE2）里，等宽 11pt，保持通用 API 控制台观感，而不是散落的灰字。

## 1. 设计令牌（Design Tokens）

### 1.1 颜色（Provider A · 默认）

| token | 值 | 用途 |
|---|---|---|
| `bg` | #F5F4ED | 面板/窗口底 |
| `card` | #FAF9F5 | 卡片、输入框底 |
| `codeBlock` | #EEECE2 | 假 headers/JSON/log 底 |
| `accent` | #D97757 | 主按钮、进度条填充（一屏一处） |
| `accentDeep` | #C96442 | 限流态强调、进度条末段 |
| `success` | #7C9F6A | 200 OK、完成对勾 |
| `textPrimary` | #3D3D3A | 主文字 |
| `textSecondary` | #87867F | 中文释义/英文原声副行、说明 |
| `textTertiary` | #B5B3A7 | mono 装饰行（POST /v1/focus 等） |
| `border` | #E5E3DA | 1px 细边、分隔线 |
| `onAccent` | #FFFFFF | 橙底上的文字 |
| `onAccentSecondary` | rgba(255,255,255,0.75) | 橙底上的副行 |

### 1.2 字体（Type Scale）

| token | 规格 | 用途 |
|---|---|---|
| `display` | serif 24pt semibold | 状态大标题（Ready / Usage limit reached / I'm a teapot） |
| `displaySub` | serif 17pt regular | 大标题副句（reset at {time} 句） |
| `title` | sans 15pt semibold | 按钮主行、区块标题 |
| `body` | sans 13pt regular | 正文 |
| `caption` | sans 11pt regular | 双语副行（永远 textSecondary） |
| `monoBody` | mono 11pt | 码块内容、时间数字 |
| `monoBig` | mono 22pt medium | 滚动窗口计时数字 |
| `monoTag` | mono 10pt | 装饰行（POST /v1/focus、Reset at 00:00 UTC） |

双语规则（SPEC §14.4 / D8）：**主行文案随 settings.language**（zh-CN 主中文），副行为英文原声，统一 `caption` + textSecondary、间距 2；language=en 时无副行。英雄措辞（Usage limit reached / 各状态码）保持英文原声不译。Provider C 全部字体换 mono（display 用 mono 20pt bold）。

### 1.3 几何与动效

- 圆角：卡片/码块 12 · 按钮 8 · 进度条 999（Provider B 改 4/2；C 全 0）
- 边框：1px `border`；阴影全局禁用（米色纸面不投影）
- 面板：**380 × 540 固定**（高度不随状态变化——hug 高度会让窗口 resize 露出磨砂底层，v2.1 反馈#3）；内容区垂直居中弹性；内容 padding **20**；顶栏高 **44**
- 状态切换动效：`.easeOut(duration: 0.22)`，`opacity + 4pt 上移` 组合过场；进度条 1s 线性推进；禁止 spring/bounce
- 悬停：按钮亮度 -6%；图标按钮浮现 `card` 底色圆角 6

### 1.4 Provider B / C 令牌覆盖

| token | B（深色赛博） | C（终端绿字） |
|---|---|---|
| bg / card / codeBlock | #14161D / #1B1E27 / #10131A | #000000 / #050505 / #0A0F0A |
| accent / accentDeep | #45C4D6 / #2FA3B4 | #00FF41 / #00C433 |
| textPrimary / Secondary / Tertiary | #E8EAF0 / #8B90A0 / #565B6B | #00FF41 / #00A02C / #005A18 |
| border | #262B38 | #0E3B14 |
| onAccent | #0B0D12 | #000000 |
| success | #5BD6A2 | #00FF41 |
| 字体/圆角 | 同 A / 4·2 | 全 mono / 全 0 |
| 限流措辞 | `Rate limit exceeded` | `ERR_TOO_MANY_REQUESTS` |

## 2. 面板骨架（所有状态共用）

```
┌────────────────────────────────────┐
│ ● {状态标签}            ▤  ⚙  ⏻  │ ← 顶栏 44px
├────────────────────────────────────┤
│                                    │
│           {状态内容区}             │ ← padding 20
│                                    │
├────────────────────────────────────┤
│ tomato-1.0 · local only            │ ← 底栏 28px，monoTag，居中
└────────────────────────────────────┘
```

- **顶栏**：左侧状态点（8px 圆，颜色见 §3 表）+ 状态标签（monoBody，textSecondary）；右侧三个图标按钮（20px，textSecondary，hover 见 §1.3）：`▤` 打开 Usage 窗口、`⚙` 打开设置窗口、`⏻` 退出（先 `vm.flush()` 再 `NSApplication.terminate`）。顶栏底部 1px `border` 分隔。
- **底栏**：`tomato-1.0 · local only`（monoTag，textTertiary），上方 1px `border`。
- 日终横幅：`didDailyReset` 时顶栏下方插入一条 32px 横幅（card 底，body 主行 + caption 副行，quota.reset_daily 双语），4s 后自动淡出。

### 状态点颜色

| 状态 | 点色 | 顶栏标签（monoBody） |
|---|---|---|
| IDLE | success | `ready` |
| IDLE(额度尽) | textTertiary | `503 service_unavailable` |
| SENDING | accent（脉冲 1s） | `POST /v1/focus` |
| FOCUSING | accent（脉冲 2s） | `streaming` |
| COMPLETED | success | `200 OK` |
| RATE_LIMITED | accentDeep | `429 rate_limited` |
| ABORTED | textTertiary | `408 timeout` |
| TEAPOT | accentDeep | `418 teapot` |
| RESET | success | `quota replenished` |

**菜单栏图标**：IDLE `⏱ {remaining}`；FOCUSING `⏱ {mm:ss 剩余}`（mono digits）；RATE_LIMITED `⏱ 429`；额度尽 `⏱ 503`。

## 3. 逐状态内容区

### 3.1 IDLE

自上而下（间距标注在左）：

```
24  Ready                    ← display，居中
 2  就绪                     ← caption，居中
20  ┌─ 输入框 ─────────────┐  ← card 底、border 1px、radius 8、高 64（可两行）
    │ What to focus on…    │    body；placeholder textTertiary；双语 placeholder 主中文
    └──────────────────────┘
16  ┌──────────────────────┐  ← 主按钮：accent 底、radius 8、高 48、全宽
    │    Send Request      │    title onAccent
    │      发起请求        │    caption onAccentSecondary
    └──────────────────────┘
12  Fast requests left: 7/8 today    ← body 居中；数字部分 mono semibold
 2  今日剩余快速请求：7/8            ← caption 居中
16  POST /v1/focus                   ← monoTag textTertiary 居中
```

- 额度点阵：数字行下方 6px 处画 `maxPerDay` 个 6px 圆点（间距 6，居中）：已用 = border 色空心，剩余 = accent 实心。maxPerDay > 12 时不画点阵。
- **503 变体**（isQuotaExhausted）：display 换 `Service unavailable`，caption 换 status.service_unavailable 中文；主按钮禁用态（card 底、border 边、textTertiary 文字）；输入框隐藏。

### 3.2 SENDING（≈1.5s 瞬时）

内容居中，垂直排列：转圈（20px，accent）→ 12 → `Sending request...` body + caption 双语 → 16 → 码块（§4.1 样式）内两行 mono：`POST /v1/focus` / `← 200 OK`（第二行延迟 0.6s 淡入）。
假闪现彩蛋：30% 概率在 0.5s 处叠加一行 `Something went wrong. Retrying...`（monoBody，accentDeep），300ms 后消失。

### 3.3 FOCUSING

```
16  2h 32m                   ← monoBig，居中；"/ 5h 00m" 用 monoBody textSecondary 基线对齐（分钟粒度，C7）
 2  · fast requests           ← monoTag textTertiary 居中
12  ▓▓▓▓▓▓░░░░░░░░░░          ← 进度条：高 8 胶囊，track=border，fill 连续渐变 accent→accentDeep
16  {流式回显卡片}             ← 有 note 时；card 底 radius 12 padding 12：
                                 首行 `streaming...` monoTag accent（脉冲）；正文 body 打字机
12  {假 log 码块}              ← showFakeLogs 时；§4.1 码块，高 88 固定，内部滚动，
                                 新行从底部推入，超出顶部 12px 渐隐
16  [ Abort Request · 中止请求 ]  ← 幽灵按钮：透明底 border 边框，高 36，body textSecondary；
                                    hover 边框与文字转 accentDeep
```

### 3.4 COMPLETED（≈2s 瞬时）

居中：`✓`（28px success 圆环内对勾）→ 12 → `Request completed in 25m 00s` display 20pt + caption 双语 → 16 → 假 JSON 码块（§4.1，最多 8 行）→ 8 → `/cost · $0.00 (you were the compute)` monoTag textTertiary。

### 3.5 RATE_LIMITED（梗高潮，全产品最讲究的一屏）

```
28  Usage limit reached            ← display，居中，textPrimary
 8  your limit will reset at 14:32 ← displaySub 居中；"14:32" 用 mono 17pt semibold accentDeep
 4  您已达到使用上限 —— 将于 14:32 重置。 ← caption 居中
20  ── 细进度线 ──                 ← 高 4 胶囊、宽 200 居中；track=border，fill=accentDeep，
                                     随冷却推进从满到空（倒放）
20  ▸ HTTP/1.1 429 Too Many Requests  ← 折叠三角 + monoBody；展开后 §4.1 码块显示完整 6 行假 headers
20  ┌──────────────────────┐
    │ Send more messages   │      ← 主按钮 accent 底（本屏唯一的亮橙），高 44
    │   with Pro →         │
    └──────────────────────┘
 8  Skip cooldown · 跳过休息      ← 纯文字按钮 caption textSecondary，hover 下划线
16  Reset at 00:00 UTC            ← monoTag textTertiary 居中（§9.4.2 彩蛋）
```

禁止红/黑/警告图标。整屏仍是米色纸面，**温柔地拒绝**。

### 3.6 ABORTED

居中：`408` mono 20pt textTertiary → 8 → `Request Timeout` display 20pt → 2 → status.aborted 双语 caption → 20 → 两按钮并排（各半宽，间距 12）：`Start cooldown anyway · 还是去休息`（主按钮样式）/ `Skip cooldown · 跳过休息`（幽灵按钮样式）。

### 3.7 TEAPOT

居中：`🫖` 40pt → 12 → `418 I'm a teapot` display → 4 → status.teapot 双语 caption（max 2 行）→ 20 → `[ I'll behave · 我会乖乖的 ]` 主按钮。

### 3.8 RESET（≈2s 瞬时）

居中：`Rate limit window reset.` display 20pt → 4 → quota.window_reset 双语 caption → 12 → `Fast requests left: {n}/{max}` body（数字 mono，从旧值滚动到新值 0.4s）。

## 4. 组件规格

### 4.1 CodeBlock（假 headers/JSON/log 统一容器）

codeBlock 底、radius 12、padding 12、内容 monoBody textPrimary、行距 +2；左上角可选标签行（monoTag textTertiary，如 `http`/`json`/`logs`）。折叠版（FakeHeaderBlock）：`▸/▾` 三角 + 首行，展开 0.22s。

### 4.2 TomatoButton

| 变体 | 底 | 文字 | 边 | 高 |
|---|---|---|---|---|
| primary | accent | onAccent（title）+ onAccentSecondary（caption 副行） | 无 | 44-48 |
| ghost | 透明 | textSecondary（body） | 1px border | 36 |
| text | 透明 | textSecondary（caption） | 无 | 24 |

按下缩放 0.98；disabled：card 底 + border 边 + textTertiary 字。

### 4.3 BilingualText

主行 + caption 副行（间距 2），alignment 参数化。副行显隐读 settings（默认开）。

### 4.4 Usage 窗口（760×560，bg 底）

- 标题行：`Usage Dashboard` display 20pt + 双语 caption；右侧 `⟳ Refresh`（ghost 小按钮，点击真的重读 sessions——不再是纯装饰）与 `Last 24h ▾`（假装饰，textTertiary）。
- 统计行：两枚"数字卡"（card 底 radius 12 padding 16 并排）：`Uptime: {n} days`、`{count} fast requests this year`，数字 mono 22pt accent，副行双语 caption。
- 年图：格子 11px、间距 3、radius 2；等级色即 SPEC §12.1 五档；hover 放大 1.15 + tooltip；月份标签 monoTag。
- 钻取：卡片式下展（card 底 radius 12），24 柱、柱宽 16 间距 6，completed=accent、aborted=border 叠顶；峰值标注 `Peak: 14:00-15:00 · 4 requests` monoBody；legend `■ fast requests ■ aborted requests` monoTag。
- 空数据：居中 `No usage yet. Send your first request.` body + caption 双语。

### 4.5 SettingsView（460×自适应）

分组卡（card 底 radius 12，组间 16，组内行高 40，行间 1px border）：
1. **Session**：focus/cooldown/maxPerDay 三行 Stepper（数值 mono）
2. **Appearance**：Provider 分段控件（A/B/C，选中态 accent 底 onAccent 字）、Language picker、双语副行开关
3. **Parody**：showFakeLogs / showFakeHeaders / soundEnabled 三个 Toggle（tint=accent）
4. 底部：`Telemetry: disabled (we don't actually collect anything)` 双语 caption + 从 Bundle 读取的版本号及 `all data stays local`

首次免责未确认时，Settings 窗口仍可作为只读信息页打开，但 Stepper、Recorder、Launch at Login、分段控件与 Toggle 整组禁用，避免第三方控件绕过 AppViewModel 的写入门。

### 4.6 Upgrade / Disclaimer sheets

沿用 v1 文案与红线（SPEC §13 一字不动），视觉按本设计系统重排：sheet 宽 320、card 底、display 18pt 标题、主按钮 primary、免责小字 caption textTertiary 永久可见。
固定法律文案始终以完整中英混排形式显示，不随当前 locale 退化为单语。

## 5. 接线层行为规格（AppViewModel v2，修 v1 交互 bug）

1. **计时器在 App 启动即运行**（App init 调 `vm.start()`），不依赖面板 onAppear——v1 的"不开面板状态永远不走"是最重的交互 bug。
2. 菜单栏 label 由 vm 派生量驱动（§2 表），每 tick 刷新。
3. 面板打开时 tick 间隔 1s；`objectWillChange` 只在派生量真变化时发（对比后发布，避免整面板每秒无效重绘）。
4. 状态转移持久化语义沿用 v1 修复版（finalized session 双路径落盘、去重）。
5. QA 时间缩放：环境变量 `RLT_TIME_SCALE=n`（浮点）→ 用 `ScaledClock(base: SystemClock(), anchor: 启动时刻, scale: n)` 注入引擎；n=60 时 25 分钟专注 25 秒走完。生产不设即 1。快照恢复兼容：TIME_SCALE 模式下启动时丢弃旧快照（QA 数据不混生产）。
6. 升级 nudge / 音效 / 假闪现逻辑沿用 v1 修复版。

## 6. 验收清单（R4 视觉 QA 逐条勾）

- [ ] 九个状态截图对照 §3 逐条一致（布局/间距/字级/颜色）
- [ ] 一屏一橙：每屏数一遍亮橙元素 ≤1
- [ ] 双语副行全局 caption + textSecondary，无字号漂移
- [ ] 码块统一 §4.1 样式，无裸灰字假数据
- [ ] 菜单栏 label 四态正确且 focusing 倒计时走动
- [ ] 不开面板放着，专注照常完成并弹限流（bug#1 回归）
- [ ] Provider B/C 切换后布局不变、令牌全换、C 全等宽
- [ ] 顶栏 ⏻ 退出前落盘（重启恢复到退出时状态）
- [ ] Usage 窗口 Refresh 真的刷新；空数据态正常
- [ ] 红线复查（SPEC §13）+ 免责小字在位
- [ ] VoiceOver 不出现无名按钮，双语组件只朗读当前主语言
- [ ] Full Keyboard Access 可完成免责、开始、终止、冷却、设置与 Usage 主流程
- [ ] Reduce Motion 下关闭脉冲、打字机和非必要过场
- [ ] 空热力格不污染可访问性树，有数据日期/小时提供本地化数值摘要
- [ ] 必要正文与免责声明达到至少 4.5:1 对比度；装饰性低对比元素不承载必要信息
- [ ] 大字号与 Increase Contrast 下主要操作和免责内容不截断
