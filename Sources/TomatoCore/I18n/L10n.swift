import Foundation

/// 代码内文案目录（§14）。所有面向用户的字符串都从这里取，不硬编码。
/// 默认语言 zh-CN，英文原声保留为 `en` 供双语并列展示。
/// fallback 链：请求 locale → zh-CN → en → 返回 key 本身。
/// 预留 `zh-dialect-*` 方言彩蛋（§14.3）。
///
/// 红线（docs/CHANGES.md C1）：`action.upgrade` 不得含真实厂商名称。
public enum L10n {
    public static let defaultLocale = "zh-CN"
    public static let englishLocale = "en"
    public static let fallbackLocale = "en"

    /// 取出指定 locale 的文案（缺失时回退到 zh-CN → en → key 本身）。
    /// 支持占位符 `{time}` / `{remaining}` / `{max}` / `{days}` / `{count}`。
    public static func t(_ key: String, locale: String = defaultLocale, args: [String: String] = [:]) -> String {
        let template = lookupTemplate(key, locale: locale)
        return substitute(template, args: args)
    }

    /// 双语并列：返回主语言文案 + 英文原声（§14.4）。
    /// 主语言缺失时回退到 zh-CN；英文原声缺失时回退到 zh-CN 再到 key。
    public static func bilingual(
        _ key: String,
        primaryLocale: String = defaultLocale,
        args: [String: String] = [:]
    ) -> (primary: String, englishOriginal: String) {
        let entries = catalog[key] ?? [:]
        let primaryRaw = entries[primaryLocale] ?? entries[defaultLocale] ?? entries[englishLocale] ?? key
        let englishRaw = entries[englishLocale] ?? entries[defaultLocale] ?? key
        return (substitute(primaryRaw, args: args), substitute(englishRaw, args: args))
    }

    /// 当前已知全部 key（按字典序）。
    public static var allKeys: [String] {
        return catalog.keys.sorted()
    }

    /// 指定 locale 下显式存在的 key（方言彩蛋用）。
    public static func keys(in locale: String) -> [String] {
        return catalog.compactMap { (key, entries) in
            entries[locale] != nil ? key : nil
        }.sorted()
    }

    public static func hasKey(_ key: String, locale: String) -> Bool {
        return catalog[key]?[locale] != nil
    }

    // MARK: - 内部

    private static func lookupTemplate(_ key: String, locale: String) -> String {
        let entries = catalog[key]
        if let v = entries?[locale] { return v }
        if let v = entries?[defaultLocale] { return v }
        if let v = entries?[fallbackLocale] { return v }
        return key
    }

    private static func substitute(_ template: String, args: [String: String]) -> String {
        guard !args.isEmpty else { return template }
        var result = template
        for (key, value) in args {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    // MARK: - 文案目录

    private static let catalog: [String: [String: String]] = [
        "unit.focus_session": [
            "zh-CN": "快速请求（专注）",
            "en": "fast request",
        ],
        "action.send_request": [
            "zh-CN": "发起请求",
            "en": "Send Request",
        ],
        "action.abort": [
            "zh-CN": "中止请求",
            "en": "Abort Request",
        ],
        "action.upgrade": [
            "zh-CN": "升级到 Pro",
            "en": "Send more messages with Pro",
        ],
        "status.ready": [
            "zh-CN": "就绪",
            "en": "Ready",
        ],
        "status.streaming": [
            "zh-CN": "流式输出中",
            "en": "streaming",
        ],
        "status.completed": [
            "zh-CN": "请求已完成",
            "en": "Request completed",
        ],
        "status.usage_limit_reached": [
            "zh-CN": "您已达到使用上限 —— 将于 {time} 重置。",
            "en": "Usage limit reached — your limit will reset at {time}.",
            "zh-dialect-northeast": "哎呀妈呀，今儿调得够多了，歇会儿吧，等着 {time} 再来。",
            "zh-dialect-sichuan": "莫慌嘛，用超了，等到 {time} 再来搞。",
        ],
        "status.rate_limited": [
            "zh-CN": "冷却中 / 限流窗口",
            "en": "cooldown / rate limit window",
        ],
        "status.too_many": [
            "zh-CN": "请求过多",
            "en": "Too Many Requests",
        ],
        "status.aborted": [
            "zh-CN": "请求已中止，专注被打断。",
            "en": "Request aborted. Focus was interrupted.",
        ],
        "status.timeout": [
            "zh-CN": "请求超时（你走神了）",
            "en": "Request Timeout",
        ],
        "status.teapot": [
            "zh-CN": "我是个茶壶。你已经连续摸鱼 3 次了，不如真的休息一下？",
            "en": "I'm a teapot. You've slacked off 3 times in a row. Maybe take a real break?",
        ],
        "status.teapot_headline": [
            "zh-CN": "418 I'm a teapot",
            "en": "418 I'm a teapot",
        ],
        // 顶栏状态是 SPEC §3 的 API 风格标签；两种语言保持同一原声，
        // 但仍必须经过文案目录，避免视图和接线层出现用户可见硬编码。
        "status.meta_ready": [
            "zh-CN": "ready",
            "en": "ready",
        ],
        "status.meta_exhausted": [
            "zh-CN": "503 service_unavailable",
            "en": "503 service_unavailable",
        ],
        "status.meta_focusing": [
            "zh-CN": "streaming",
            "en": "streaming",
        ],
        "status.meta_rate_limited": [
            "zh-CN": "429 rate_limited",
            "en": "429 rate_limited",
        ],
        "status.meta_aborted": [
            "zh-CN": "408 timeout",
            "en": "408 timeout",
        ],
        "status.meta_reset": [
            "zh-CN": "quota replenished",
            "en": "quota replenished",
        ],
        "status.meta_teapot": [
            "zh-CN": "418 teapot",
            "en": "418 teapot",
        ],
        "status.maintenance": [
            "zh-CN": "维护窗口（长休息）",
            "en": "maintenance window",
        ],
        "quota.daily": [
            "zh-CN": "今日额度",
            "en": "daily quota",
        ],
        "quota.remaining": [
            "zh-CN": "今日剩余快速请求：{remaining}/{max}",
            "en": "Fast requests left: {remaining}/{max} today",
        ],
        "quota.reset_daily": [
            "zh-CN": "每日额度已重置。早安。",
            "en": "Daily quota reset. Good morning.",
        ],
        "quota.window_reset": [
            "zh-CN": "限流窗口已重置，额度已恢复。",
            "en": "Rate limit window reset. Quota replenished.",
        ],
        "stats.uptime": [
            "zh-CN": "在线时长（连续 {days} 天）",
            "en": "Uptime: {days} days",
        ],
        "stats.year_total": [
            "zh-CN": "今年共发起 {count} 次快速请求",
            "en": "{count} fast requests this year",
        ],
        "nav.usage": [
            "zh-CN": "用量看板",
            "en": "Usage Dashboard",
        ],
        "metric.tokens": [
            "zh-CN": "已用 token",
            "en": "tokens used",
        ],
        "metric.retry_after": [
            "zh-CN": "重试等待",
            "en": "retry-after",
        ],
        "notif.completed_title": [
            "zh-CN": "429 Too Many Requests — 该休息了",
            "en": "429 Too Many Requests — take a break",
        ],
        "notif.completed_body": [
            "zh-CN": "专注完成。已进入 {min} 分钟限流窗口，离开键盘歇一歇。",
            "en": "Focus complete. Rate limited for {min} minutes — step away from the keyboard.",
        ],
        "notif.reset_title": [
            "zh-CN": "Rate limit window reset — 额度已恢复",
            "en": "Rate limit window reset — quota replenished",
        ],
        "notif.reset_body": [
            "zh-CN": "休息结束，可以发起下一个快速请求了。",
            "en": "Break is over. Ready for your next fast request.",
        ],
        "notif.action_start": [
            "zh-CN": "发起下一轮",
            "en": "Send next request",
        ],
        "settings.hotkey": [
            "zh-CN": "全局快捷键",
            "en": "Global hotkey",
        ],
        "settings.launch_at_login": [
            "zh-CN": "开机自启",
            "en": "Launch at login",
        ],
        "settings.section_session": [
            "zh-CN": "会话",
            "en": "Session",
        ],
        "settings.focus_duration": [
            "zh-CN": "专注时长",
            "en": "Focus duration",
        ],
        "settings.cooldown_duration": [
            "zh-CN": "冷却时长",
            "en": "Cooldown",
        ],
        "settings.daily_quota": [
            "zh-CN": "每日额度",
            "en": "Daily quota",
        ],
        "settings.section_appearance": [
            "zh-CN": "外观",
            "en": "Appearance",
        ],
        "settings.language": [
            "zh-CN": "语言",
            "en": "Language",
        ],
        "settings.section_parody": [
            "zh-CN": "戏仿",
            "en": "Parody",
        ],
        "settings.fake_logs": [
            "zh-CN": "假日志流",
            "en": "Fake logs",
        ],
        "settings.fake_headers": [
            "zh-CN": "假响应头",
            "en": "Fake headers",
        ],
        "settings.sound": [
            "zh-CN": "音效",
            "en": "Sound",
        ],
        "settings.provider": [
            "zh-CN": "服务商",
            "en": "Provider",
        ],
        // 快照与 OCR 检查补齐的 i18n 文案
        "action.teapot_ack": [
            "zh-CN": "我会乖乖的",
            "en": "I'll behave",
        ],
        "status.sending": [
            "zh-CN": "正在发送请求...",
            "en": "Sending request...",
        ],
        "action.skip_cooldown": [
            "zh-CN": "跳过休息",
            "en": "Skip cooldown",
        ],
        "action.start_cooldown": [
            "zh-CN": "还是去休息",
            "en": "Start cooldown anyway",
        ],
        "action.refresh": [
            "zh-CN": "刷新",
            "en": "Refresh",
        ],
        "action.close": [
            "zh-CN": "关闭",
            "en": "Close",
        ],
        "action.start_trial": [
            "zh-CN": "开始免费试用 →",
            "en": "Start free trial →",
        ],
        "action.maybe_later": [
            "zh-CN": "以后再说",
            "en": "Maybe later",
        ],
        "action.got_it": [
            "zh-CN": "知道了",
            "en": "Got it",
        ],
        "action.disclaimer_ack": [
            "zh-CN": "I understand · 我懂了，开始玩",
            "en": "I understand · 我懂了，开始玩",
        ],
        "idle.note_placeholder": [
            "zh-CN": "这次专注什么",
            "en": "What to focus on",
        ],
        "unit.minute_short": [
            "zh-CN": "分钟",
            "en": "min",
        ],
        "unit.request_short": [
            "zh-CN": "次",
            "en": "req",
        ],
        "unit.fast_requests": [
            "zh-CN": "快速请求",
            "en": "fast requests",
        ],
        "unit.aborted_requests": [
            "zh-CN": "中止请求",
            "en": "aborted requests",
        ],
        "status.service_unavailable": [
            "zh-CN": "今日额度已尽，明天再来。",
            "en": "Service unavailable. Try again tomorrow.",
        ],
        "status.service_unavailable_title": [
            "zh-CN": "服务不可用",
            "en": "Service unavailable",
        ],
        "status.retrying": [
            "zh-CN": "出了点问题，正在重试……",
            "en": "Something went wrong. Retrying...",
        ],
        "status.completed_in": [
            "zh-CN": "请求于 {min} 分钟 00 秒内完成",
            "en": "Request completed in {min}m 00s",
        ],
        "status.reset_headline": [
            "zh-CN": "限流窗口已重置。",
            "en": "Rate limit window reset.",
        ],
        "status.reset_time_prefix": [
            "zh-CN": "您的限额将于 ",
            "en": "your limit will reset at ",
        ],
        "status.reset_at_midnight": [
            "zh-CN": "于 00:00 UTC 重置",
            "en": "Reset at 00:00 UTC",
        ],
        "status.rate_limit_headline_a": [
            "zh-CN": "Usage limit reached",
            "en": "Usage limit reached",
        ],
        "status.rate_limit_headline_b": [
            "zh-CN": "Rate limit exceeded",
            "en": "Rate limit exceeded",
        ],
        "status.rate_limit_headline_c": [
            "zh-CN": "ERR_TOO_MANY_REQUESTS",
            "en": "ERR_TOO_MANY_REQUESTS",
        ],
        "parody.cost_compute": [
            "zh-CN": "/cost · $0.00（算力来自你）",
            "en": "/cost · $0.00 (you were the compute)",
        ],
        "parody.endpoint_focus": [
            "zh-CN": "POST /v1/focus",
            "en": "POST /v1/focus",
        ],
        "parody.response_ok": [
            "zh-CN": "← 200 OK",
            "en": "← 200 OK",
        ],
        "parody.status_ok": [
            "zh-CN": "200 OK",
            "en": "200 OK",
        ],
        "parody.status_timeout_code": [
            "zh-CN": "408",
            "en": "408",
        ],
        "parody.status_rate_limited_code": [
            "zh-CN": "429",
            "en": "429",
        ],
        "parody.status_unavailable_code": [
            "zh-CN": "503",
            "en": "503",
        ],
        "parody.http_429": [
            "zh-CN": "HTTP/1.1 429 Too Many Requests",
            "en": "HTTP/1.1 429 Too Many Requests",
        ],
        "parody.streaming_ellipsis": [
            "zh-CN": "streaming...",
            "en": "streaming...",
        ],
        "parody.logs_tag": [
            "zh-CN": "logs",
            "en": "logs",
        ],
        "parody.json_tag": [
            "zh-CN": "json",
            "en": "json",
        ],
        "settings.section_general": [
            "zh-CN": "通用",
            "en": "General",
        ],
        "settings.telemetry_disabled": [
            "zh-CN": "遥测：已禁用（我们其实什么也没采集）",
            "en": "Telemetry: disabled (we don't actually collect anything)",
        ],
        "settings.storage_unavailable": [
            "zh-CN": "存储不可用——当前仅在内存中运行，退出后数据不保留",
            "en": "Storage unavailable — running in memory only; data won't persist after quit",
        ],
        "settings.local_only": [
            "zh-CN": "v{version} · 所有数据仅保存在本地",
            "en": "v{version} · all data stays local",
        ],
        "settings.version_development": [
            "zh-CN": "dev",
            "en": "dev",
        ],
        "settings.language_zh_cn": [
            "zh-CN": "中文",
            "en": "Chinese",
        ],
        "settings.language_en": [
            "zh-CN": "英文",
            "en": "English",
        ],
        "nav.settings": [
            "zh-CN": "设置",
            "en": "Settings",
        ],
        "nav.quit": [
            "zh-CN": "退出",
            "en": "Quit",
        ],
        "window.usage": [
            "zh-CN": "用量",
            "en": "Usage",
        ],
        "window.settings": [
            "zh-CN": "设置",
            "en": "Settings",
        ],
        "app.footer": [
            "zh-CN": "tomato-1.0 · 仅本地运行",
            "en": "tomato-1.0 · local only",
        ],
        "app.menu_bar_status": [
            "zh-CN": "番茄钟状态：{state}，{value}",
            "en": "Timer status: {state}, {value}",
        ],
        "usage.last_24h": [
            "zh-CN": "最近 24 小时 ▾",
            "en": "Last 24h ▾",
        ],
        "usage.empty": [
            "zh-CN": "还没有用量记录。发起第一次请求后这里会亮起来。",
            "en": "No usage yet. Send your first request.",
        ],
        "usage.refresh_hint": [
            "zh-CN": "重新读取本地用量数据",
            "en": "Refresh local usage data",
        ],
        "usage.close_drilldown": [
            "zh-CN": "关闭小时详情",
            "en": "Close hourly details",
        ],
        "usage.day_tooltip": [
            "zh-CN": "{date} 有 {count} 次快速请求",
            "en": "{count} fast requests on {date}",
        ],
        "usage.open_day_hint": [
            "zh-CN": "打开当天的小时详情",
            "en": "Open hourly details for this day",
        ],
        "usage.peak": [
            "zh-CN": "峰值：{start}:00-{end}:00 · {count} 次请求",
            "en": "Peak: {start}:00-{end}:00 · {count} requests",
        ],
        "usage.peak_empty": [
            "zh-CN": "峰值：--",
            "en": "Peak: --",
        ],
        "usage.hour_empty": [
            "zh-CN": "{hour}:00 — 没有请求",
            "en": "{hour}:00 — no requests",
        ],
        "usage.hour_counts": [
            "zh-CN": "{hour}:00 — 完成 {completed} 次，中止 {aborted} 次",
            "en": "{hour}:00 — {completed} completed, {aborted} aborted",
        ],
        // 年度热力图固定英文月份缩写；目录化后仍
        // 保持两种 locale 的视觉一致，同时满足 UI 文案零硬编码约束。
        "usage.month_1": ["zh-CN": "Jan", "en": "Jan"],
        "usage.month_2": ["zh-CN": "Feb", "en": "Feb"],
        "usage.month_3": ["zh-CN": "Mar", "en": "Mar"],
        "usage.month_4": ["zh-CN": "Apr", "en": "Apr"],
        "usage.month_5": ["zh-CN": "May", "en": "May"],
        "usage.month_6": ["zh-CN": "Jun", "en": "Jun"],
        "usage.month_7": ["zh-CN": "Jul", "en": "Jul"],
        "usage.month_8": ["zh-CN": "Aug", "en": "Aug"],
        "usage.month_9": ["zh-CN": "Sep", "en": "Sep"],
        "usage.month_10": ["zh-CN": "Oct", "en": "Oct"],
        "usage.month_11": ["zh-CN": "Nov", "en": "Nov"],
        "usage.month_12": ["zh-CN": "Dec", "en": "Dec"],
        "upgrade.plan": [
            "zh-CN": "Pro · 每月 $20",
            "en": "Pro · $20/month",
        ],
        "upgrade.benefit_unlimited": [
            "zh-CN": "无限专注会话",
            "en": "Unlimited focus sessions",
        ],
        "upgrade.benefit_priority": [
            "zh-CN": "优先队列（跳过冷却）",
            "en": "Priority queue (skip the cooldown)",
        ],
        "upgrade.benefit_deep_work": [
            "zh-CN": "深度专注模式",
            "en": "Deep-work mode",
        ],
        "upgrade.benefit_context": [
            "zh-CN": "扩展上下文（更长专注时段）",
            "en": "Extended context (longer focus blocks)",
        ],
        "upgrade.thanks": [
            "zh-CN": "感谢你的兴趣。😏",
            "en": "Thank you for your interest. 😏",
        ],
        "upgrade.comedy_primary": [
            "zh-CN": "心动了？回去专注吧。",
            "en": "Tempted? Get back to focusing.",
        ],
        "upgrade.comedy_secondary": [
            "zh-CN": "你已升级为：一个会专注的人。",
            "en": "You've been upgraded to: a person who focuses.",
        ],
        "disclaimer.title": [
            "zh-CN": "⚠️ Heads up · 友情提示",
            "en": "⚠️ Heads up · 友情提示",
        ],
        "disclaimer.summary": [
            "zh-CN": "This is a parody app. 本产品是一款戏仿（番茄钟）应用。",
            "en": "This is a parody app. 本产品是一款戏仿（番茄钟）应用。",
        ],
        "disclaimer.virtual": [
            "zh-CN": "所有“额度”“限流”“升级 Pro”均为虚构，用于还原 AI 工具体感",
            "en": "所有“额度”“限流”“升级 Pro”均为虚构，用于还原 AI 工具体感",
        ],
        "disclaimer.no_charge": [
            "zh-CN": "本应用不会进行任何真实收费",
            "en": "本应用不会进行任何真实收费",
        ],
        "disclaimer.local_only": [
            "zh-CN": "不会联网上报任何数据，所有数据保存在本地",
            "en": "不会联网上报任何数据，所有数据保存在本地",
        ],
        "error.parody_disclaimer": [
            // SPEC §13.4 完整版（红线），比 §14.2 的短样本多"不会进行任何扣款"
            "zh-CN": "* Parody. 本产品为戏仿，不提供任何真实付费服务，不会进行任何扣款。You've been parodied.",
            "en": "* Parody. 本产品为戏仿，不提供任何真实付费服务，不会进行任何扣款。You've been parodied.",
        ],
    ]
}
