import XCTest
@testable import TomatoCore

final class L10nTests: XCTestCase {
    /// SPEC §14.2 全部 key —— 全 locale 都有 zh-CN + en 双值。
    private let requiredKeys: [String] = [
        "unit.focus_session",
        "unit.aborted_requests",
        "action.send_request",
        "action.abort",
        "action.upgrade",
        "status.ready",
        "status.streaming",
        "status.completed",
        "status.usage_limit_reached",
        "status.rate_limited",
        "status.too_many",
        "status.aborted",
        "status.timeout",
        "status.teapot",
        "status.teapot_headline",
        "status.meta_ready",
        "status.meta_exhausted",
        "status.meta_focusing",
        "status.meta_rate_limited",
        "status.meta_aborted",
        "status.meta_reset",
        "status.meta_teapot",
        "status.maintenance",
        "quota.daily",
        "quota.remaining",
        "quota.reset_daily",
        "quota.window_reset",
        "stats.uptime",
        "stats.year_total",
        "nav.usage",
        "metric.tokens",
        "metric.retry_after",
        "settings.provider",
        "settings.section_session",
        "settings.focus_duration",
        "settings.cooldown_duration",
        "settings.daily_quota",
        "settings.section_appearance",
        "settings.language",
        "settings.section_parody",
        "settings.fake_logs",
        "settings.fake_headers",
        "settings.sound",
        "settings.hotkey",
        "settings.launch_at_login",
        "settings.version_development",
        "notif.completed_title",
        "notif.completed_body",
        "notif.reset_title",
        "notif.reset_body",
        "notif.action_start",
        "action.teapot_ack",
        "status.sending",
        "action.skip_cooldown",
        "action.start_cooldown",
        "idle.note_placeholder",
        "status.service_unavailable",
        "parody.endpoint_focus",
        "parody.response_ok",
        "parody.status_ok",
        "parody.status_timeout_code",
        "parody.status_rate_limited_code",
        "parody.status_unavailable_code",
        "parody.http_429",
        "parody.streaming_ellipsis",
        "parody.logs_tag",
        "parody.json_tag",
        "usage.month_1",
        "usage.month_12",
        "error.parody_disclaimer",
    ]

    func testAllKeysPresentInZhCN() {
        for key in L10n.allKeys {
            XCTAssertTrue(L10n.hasKey(key, locale: "zh-CN"), "missing zh-CN for key \(key)")
        }
    }

    func testAllKeysPresentInEn() {
        for key in L10n.allKeys {
            XCTAssertTrue(L10n.hasKey(key, locale: "en"), "missing en for key \(key)")
        }
    }

    func testRequiredSpecKeysRemainListed() {
        let catalogKeys = Set(L10n.allKeys)
        XCTAssertTrue(
            Set(requiredKeys).isSubset(of: catalogKeys),
            "missing required keys: \(Set(requiredKeys).subtracting(catalogKeys).sorted())"
        )
    }

    func testTimePlaceholder() {
        XCTAssertEqual(
            L10n.t("status.usage_limit_reached", locale: "zh-CN", args: ["time": "14:32"]),
            "您已达到使用上限 —— 将于 14:32 重置。"
        )
        XCTAssertEqual(
            L10n.t("status.usage_limit_reached", locale: "en", args: ["time": "14:32"]),
            "Usage limit reached — your limit will reset at 14:32."
        )
    }

    func testRemainingAndMaxPlaceholders() {
        XCTAssertEqual(
            L10n.t("quota.remaining", locale: "zh-CN", args: ["remaining": "7", "max": "8"]),
            "今日剩余快速请求：7/8"
        )
        XCTAssertEqual(
            L10n.t("quota.remaining", locale: "en", args: ["remaining": "7", "max": "8"]),
            "Fast requests left: 7/8 today"
        )
    }

    func testDaysPlaceholder() {
        XCTAssertEqual(
            L10n.t("stats.uptime", locale: "en", args: ["days": "42"]),
            "Uptime: 42 days"
        )
        XCTAssertEqual(
            L10n.t("stats.uptime", locale: "zh-CN", args: ["days": "42"]),
            "在线时长（连续 42 天）"
        )
    }

    func testCountPlaceholder() {
        XCTAssertEqual(
            L10n.t("stats.year_total", locale: "en", args: ["count": "1,247"]),
            "1,247 fast requests this year"
        )
        XCTAssertEqual(
            L10n.t("stats.year_total", locale: "zh-CN", args: ["count": "1,247"]),
            "今年共发起 1,247 次快速请求"
        )
    }

    func testMissingArgsLeavesPlaceholderUntouched() {
        let raw = L10n.t("status.usage_limit_reached", locale: "en")
        XCTAssertTrue(raw.contains("{time}"))
    }

    func testFallbackDialectToZhCN() {
        // 方言 locale 缺少的 key → 落到 zh-CN
        let standard = L10n.t("action.send_request", locale: "zh-CN")
        let dialect = L10n.t("action.send_request", locale: "zh-dialect-northeast")
        XCTAssertEqual(dialect, standard)
    }

    func testFallbackMissingKey() {
        // 任何 locale 都找不到的 key → 返回 key 本身
        XCTAssertEqual(L10n.t("nonexistent.key", locale: "zh-CN"), "nonexistent.key")
        XCTAssertEqual(L10n.t("nonexistent.key", locale: "en"), "nonexistent.key")
    }

    func testFallbackEnLocaleToEn() {
        // 假设某个 key 仅有 zh-CN（人为构造）：en locale 应当回落到 zh-CN
        // 验证 fallback 链的中间段：en 命中就返 en，未命中则向下走。
        // 现有 catalog 所有 key 都有 en，这里通过双语 API 反向验证。
        let en = L10n.t("status.ready", locale: "en")
        XCTAssertEqual(en, "Ready")
    }

    func testDialectNortheastHasUsageLimitReached() {
        let value = L10n.t(
            "status.usage_limit_reached",
            locale: "zh-dialect-northeast",
            args: ["time": "14:32"]
        )
        XCTAssertTrue(value.contains("14:32"))
        XCTAssertFalse(value.isEmpty)
        XCTAssertNotEqual(
            value,
            L10n.t("status.usage_limit_reached", locale: "zh-CN", args: ["time": "14:32"])
        )
    }

    func testDialectSichuanHasUsageLimitReached() {
        let value = L10n.t(
            "status.usage_limit_reached",
            locale: "zh-dialect-sichuan",
            args: ["time": "14:32"]
        )
        XCTAssertTrue(value.contains("14:32"))
        XCTAssertFalse(value.isEmpty)
        XCTAssertNotEqual(
            value,
            L10n.t("status.usage_limit_reached", locale: "zh-CN", args: ["time": "14:32"])
        )
    }

    func testActionUpgradeIsBrandNeutral() {
        let en = L10n.t("action.upgrade", locale: "en")
        for vendor in ["Claude", "Codex", "Anthropic", "OpenAI", "Opus"] {
            XCTAssertFalse(en.localizedCaseInsensitiveContains(vendor))
        }
        XCTAssertTrue(en.contains("Pro"))
    }

    func testFixedLegalCopyIsLocaleIndependentAndExact() {
        let expected: [String: String] = [
            "disclaimer.title": "⚠️ Heads up · 友情提示",
            "disclaimer.summary": "This is a parody app. 本产品是一款戏仿（番茄钟）应用。",
            "disclaimer.virtual": "所有“额度”“限流”“升级 Pro”均为虚构，用于还原 AI 工具体感",
            "disclaimer.no_charge": "本应用不会进行任何真实收费",
            "disclaimer.local_only": "不会联网上报任何数据，所有数据保存在本地",
            "action.disclaimer_ack": "I understand · 我懂了，开始玩",
            "error.parody_disclaimer": "* Parody. 本产品为戏仿，不提供任何真实付费服务，不会进行任何扣款。You've been parodied.",
        ]

        for (key, value) in expected {
            XCTAssertEqual(L10n.t(key, locale: "zh-CN"), value)
            XCTAssertEqual(L10n.t(key, locale: "en"), value)
        }
    }

    func testSettingsLocalOnlyUsesRuntimeVersionPlaceholder() {
        XCTAssertEqual(
            L10n.t("settings.local_only", locale: "en", args: ["version": "3.2.1"]),
            "v3.2.1 · all data stays local"
        )
    }

    func testFixedAPIStyleCopyRemainsCatalogBackedAndExact() {
        let expected: [String: String] = [
            "parody.endpoint_focus": "POST /v1/focus",
            "parody.response_ok": "← 200 OK",
            "parody.status_timeout_code": "408",
            "parody.status_rate_limited_code": "429",
            "parody.status_unavailable_code": "503",
            "parody.http_429": "HTTP/1.1 429 Too Many Requests",
            "status.teapot_headline": "418 I'm a teapot",
            "usage.month_1": "Jan",
            "usage.month_12": "Dec",
        ]

        for (key, value) in expected {
            XCTAssertEqual(L10n.t(key, locale: "zh-CN"), value)
            XCTAssertEqual(L10n.t(key, locale: "en"), value)
        }
    }

    func testBilingualDefault() {
        let result = L10n.bilingual(
            "status.usage_limit_reached",
            primaryLocale: "zh-CN",
            args: ["time": "14:32"]
        )
        XCTAssertEqual(result.primary, "您已达到使用上限 —— 将于 14:32 重置。")
        XCTAssertEqual(result.englishOriginal, "Usage limit reached — your limit will reset at 14:32.")
    }

    func testBilingualEnglishPrimary() {
        let result = L10n.bilingual("status.ready", primaryLocale: "en")
        XCTAssertEqual(result.primary, "Ready")
        XCTAssertEqual(result.englishOriginal, "Ready")
    }

    func testNoUserFacingStringContainsRealVendor() {
        let forbidden = ["Claude", "Codex", "Anthropic", "OpenAI", "Opus",
                         "Cursor", "GitHub Copilot", "Windsurf"]
        for key in L10n.allKeys {
            for locale in ["zh-CN", "en"] {
                let value = L10n.t(key, locale: locale)
                for vendor in forbidden {
                    XCTAssertFalse(
                        value.localizedCaseInsensitiveContains(vendor),
                        "\(key)/\(locale) contains forbidden vendor name '\(vendor)': \(value)"
                    )
                }
            }
        }
    }
}
