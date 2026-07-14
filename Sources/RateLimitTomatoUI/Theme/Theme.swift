import SwiftUI
import TomatoCore

// 设计令牌（docs/UI-SPEC.md §1）。三套 Provider 主题只换令牌，不换布局。

public struct TomatoTheme {
    // MARK: 颜色
    public let bg: Color
    public let card: Color
    public let codeBlock: Color
    public let accent: Color
    public let accentDeep: Color
    public let success: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let border: Color
    public let onAccent: Color
    public let onAccentSecondary: Color

    // MARK: 几何
    public let cardRadius: CGFloat
    public let buttonRadius: CGFloat
    public let progressRadius: CGFloat

    // MARK: 措辞与字体风格
    public let usesMonospace: Bool
    /// 限流大标题 i18n key（UI-SPEC §1.4：A/B/C 各不同）
    public let rateLimitHeadlineKey: String

    /// 热力图等级色：A 用 SPEC §12.1 固定五档（false），B/C 按 accent 阶梯（true）
    public let usesHeatmapAccentScale: Bool

    // MARK: 字级（UI-SPEC §1.2）
    public func display(_ size: CGFloat = 24, weight: Font.Weight = .semibold) -> Font {
        usesMonospace
            ? .system(size: size - 4, weight: .bold, design: .monospaced)
            : .system(size: size, weight: weight, design: .serif)
    }
    public var displaySub: Font {
        usesMonospace
            ? .system(size: 14, design: .monospaced)
            : .system(size: 17, design: .serif)
    }
    public var title: Font {
        .system(size: usesMonospace ? 14 : 15, weight: .semibold,
                design: usesMonospace ? .monospaced : .default)
    }
    public var body13: Font {
        .system(size: 13, design: usesMonospace ? .monospaced : .default)
    }
    public var caption: Font {
        .system(size: 11, design: usesMonospace ? .monospaced : .default)
    }
    public var monoBody: Font { .system(size: 11, design: .monospaced) }
    public var monoBig: Font { .system(size: 22, weight: .medium, design: .monospaced) }
    public var monoTag: Font { .system(size: 10, design: .monospaced) }
}

// MARK: - 三套主题

extension TomatoTheme {
    /// Provider A：温暖米色纸感（默认）
    public static let providerA = TomatoTheme(
        bg: Color(hex: 0xF5F4ED), card: Color(hex: 0xFAF9F5), codeBlock: Color(hex: 0xEEECE2),
        accent: Color(hex: 0xD97757), accentDeep: Color(hex: 0xC96442), success: Color(hex: 0x7C9F6A),
        textPrimary: Color(hex: 0x3D3D3A), textSecondary: Color(hex: 0x696861),
        textTertiary: Color(hex: 0x696861), border: Color(hex: 0xE5E3DA),
        onAccent: .white, onAccentSecondary: .white.opacity(0.75),
        cardRadius: 12, buttonRadius: 8, progressRadius: 999,
        usesMonospace: false, rateLimitHeadlineKey: "status.rate_limit_headline_a",
        usesHeatmapAccentScale: false
    )

    /// Provider B：深色赛博
    public static let providerB = TomatoTheme(
        bg: Color(hex: 0x14161D), card: Color(hex: 0x1B1E27), codeBlock: Color(hex: 0x10131A),
        accent: Color(hex: 0x45C4D6), accentDeep: Color(hex: 0x2FA3B4), success: Color(hex: 0x5BD6A2),
        textPrimary: Color(hex: 0xE8EAF0), textSecondary: Color(hex: 0x8B90A0),
        textTertiary: Color(hex: 0x8B90A0), border: Color(hex: 0x262B38),
        onAccent: Color(hex: 0x0B0D12), onAccentSecondary: Color(hex: 0x0B0D12).opacity(0.7),
        cardRadius: 4, buttonRadius: 2, progressRadius: 4,
        usesMonospace: false, rateLimitHeadlineKey: "status.rate_limit_headline_b",
        usesHeatmapAccentScale: true
    )

    /// Provider C：终端绿字
    public static let providerC = TomatoTheme(
        bg: .black, card: Color(hex: 0x050505), codeBlock: Color(hex: 0x0A0F0A),
        accent: Color(hex: 0x00FF41), accentDeep: Color(hex: 0x00C433), success: Color(hex: 0x00FF41),
        textPrimary: Color(hex: 0x00FF41), textSecondary: Color(hex: 0x00A02C),
        textTertiary: Color(hex: 0x00A02C), border: Color(hex: 0x0E3B14),
        onAccent: .black, onAccentSecondary: .black.opacity(0.7),
        cardRadius: 0, buttonRadius: 0, progressRadius: 0,
        usesMonospace: true, rateLimitHeadlineKey: "status.rate_limit_headline_c",
        usesHeatmapAccentScale: true
    )

    public static func theme(for provider: Provider) -> TomatoTheme {
        switch provider {
        case .a: return .providerA
        case .b: return .providerB
        case .c: return .providerC
        }
    }
}

// MARK: - Environment

private struct TomatoThemeKey: EnvironmentKey {
    static let defaultValue: TomatoTheme = .providerA
}

extension EnvironmentValues {
    public var tomatoTheme: TomatoTheme {
        get { self[TomatoThemeKey.self] }
        set { self[TomatoThemeKey.self] = newValue }
    }
}

// MARK: - Color(hex:)

extension Color {
    /// SPEC §10.1 要求色值精确；0xRRGGBB 写法避免浮点漂移。
    public init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
