import SwiftUI
import TomatoCore

// 基础组件套件（UI-SPEC §4.1-§4.3）

// MARK: - BilingualText

private struct RLTShowSecondaryKey: EnvironmentKey {
    static let defaultValue = true
}

private struct RLTPrimaryLocaleKey: EnvironmentKey {
    static let defaultValue = AppLocale.zhCN.rawValue
}

extension EnvironmentValues {
    public var rltShowSecondary: Bool {
        get { self[RLTShowSecondaryKey.self] }
        set { self[RLTShowSecondaryKey.self] = newValue }
    }
    /// 当前主语言（settings.language）。主行文案随它切换（SPEC D8/§14.4）。
    public var rltPrimaryLocale: String {
        get { self[RLTPrimaryLocaleKey.self] }
        set { self[RLTPrimaryLocaleKey.self] = newValue }
    }
}

/// 语言感知的文案对：主行 = 当前语言，副行 = 英文原声（语言已是 en 时无副行）。
struct LocalizedPair {
    let title: String
    let subtitle: String?

    init(_ key: String, locale: String, args: [String: String] = [:]) {
        let pair = L10n.bilingual(key, primaryLocale: locale, args: args)
        title = pair.primary
        subtitle = pair.englishOriginal == pair.primary ? nil : pair.englishOriginal
    }

    /// 单行合成（幽灵/文字按钮用）："主行 · 英文原声"。
    var inline: String { subtitle.map { "\(title) · \($0)" } ?? title }
}

/// 生成配额行，并仅为 `remaining/max` 数字段应用等宽强调字体。
func quotaAttributed(
    remaining: Int,
    max: Int,
    locale: String,
    font: Font
) -> AttributedString {
    let pair = LocalizedPair("quota.remaining", locale: locale,
                             args: ["remaining": "\(remaining)", "max": "\(max)"])
    var result = AttributedString(pair.title)
    if let range = result.range(of: "\(remaining)/\(max)") {
        result[range].font = font
    }
    return result
}

/// 主行 + caption 副行（间距 2）。主行随 rltPrimaryLocale 切换（SPEC §14.4），
/// 副行为英文原声；仅接受 L10n key，避免视图重新引入用户可见硬编码。
struct BilingualText: View {
    private enum Source {
        case key(String, args: [String: String])
    }

    private let source: Source
    var primaryFont: Font? = nil
    var primaryColor: Color? = nil
    var alignment: HorizontalAlignment = .center

    @Environment(\.tomatoTheme) private var theme
    @Environment(\.rltShowSecondary) private var showSecondary
    @Environment(\.rltPrimaryLocale) private var locale

    init(_ key: String, primaryFont: Font? = nil, primaryColor: Color? = nil,
         alignment: HorizontalAlignment = .center, args: [String: String] = [:]) {
        self.source = .key(key, args: args)
        self.primaryFont = primaryFont
        self.primaryColor = primaryColor
        self.alignment = alignment
    }

    private var resolved: (primary: String, secondary: String?) {
        switch source {
        case let .key(key, args):
            let pair = LocalizedPair(key, locale: locale, args: args)
            return (pair.title, pair.subtitle)
        }
    }

    var body: some View {
        let r = resolved
        VStack(alignment: alignment, spacing: 2) {
            Text(r.primary)
                .font(primaryFont ?? theme.body13)
                .foregroundColor(primaryColor ?? theme.textPrimary)
            if showSecondary, let s = r.secondary {
                Text(s)
                    .font(theme.caption)
                    .foregroundColor(theme.textSecondary)
            }
        }
        .multilineTextAlignment(alignment == .leading ? .leading : .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(r.primary)
    }
}

// MARK: - TomatoButton

enum TomatoButtonVariant { case primary, ghost, text }

/// UI-SPEC §4.2。primary 是"一屏一橙"的那一处橙。
struct TomatoButton: View {
    let variant: TomatoButtonVariant
    let title: String
    var subtitle: String? = nil
    var height: CGFloat? = nil
    var disabled: Bool = false
    let action: () -> Void

    @Environment(\.tomatoTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(titleFont).foregroundColor(titleColor)
                if let s = subtitle {
                    Text(s).font(theme.caption).foregroundColor(subtitleColor)
                }
            }
            .frame(maxWidth: variant == .text ? nil : .infinity)
            .frame(height: height ?? defaultHeight)
            .background(background)
            .overlay(borderOverlay)
            .clipShape(RoundedRectangle(cornerRadius: theme.buttonRadius, style: .continuous))
            .contentShape(Rectangle()) // clear 背景不参与命中测试：不加则只有文字笔画可点
            .brightness(hovering && !disabled ? -0.06 : 0)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(disabled)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var defaultHeight: CGFloat {
        switch variant { case .primary: return 44; case .ghost: return 36; case .text: return 24 }
    }
    private var titleFont: Font {
        switch variant { case .primary: return theme.title; case .ghost: return theme.body13; case .text: return theme.caption }
    }
    private var titleColor: Color {
        if disabled { return theme.textTertiary }
        switch variant {
        case .primary: return theme.onAccent
        case .ghost: return hovering ? theme.accentDeep : theme.textSecondary
        case .text: return theme.textSecondary
        }
    }
    private var subtitleColor: Color {
        if disabled { return theme.textTertiary }
        return variant == .primary ? theme.onAccentSecondary : theme.textSecondary
    }
    @ViewBuilder private var background: some View {
        if variant == .primary {
            disabled ? theme.card : theme.accent
        } else {
            Color.clear
        }
    }
    @ViewBuilder private var borderOverlay: some View {
        if variant == .ghost || (variant == .primary && disabled) {
            RoundedRectangle(cornerRadius: theme.buttonRadius, style: .continuous)
                .stroke(hovering && !disabled && variant == .ghost ? theme.accentDeep : theme.border, lineWidth: 1)
        }
    }
}

private struct PressScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.98 : 1.0))
    }
}

/// 顶栏图标按钮：20px 图标，hover 浮现 card 底（UI-SPEC §2）。
struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @Environment(\.tomatoTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.textSecondary)
                .frame(width: 26, height: 26)
                .background(hovering ? theme.card : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - ThemedSegment

/// 主题化分段选择（设置页 Provider/Language 用）。
/// 原生 `.segmented` Picker 不吃主题令牌，深色主题下文字隐身（v3.2.1 反馈#2）。
struct ThemedSegment<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value

    @Environment(\.tomatoTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(theme.monoBody)
                        .foregroundColor(selected ? theme.onAccent : theme.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .frame(minWidth: 36)
                        .background(selected ? theme.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: theme.buttonRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.buttonRadius, style: .continuous)
                                .stroke(selected ? Color.clear : theme.border, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: - CodeBlock

/// 假 headers/JSON/log 的统一容器（UI-SPEC §4.1）：戏仿舞台。
struct CodeBlock: View {
    var tag: String? = nil
    let lines: [String]

    @Environment(\.tomatoTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let tag {
                Text(tag).font(theme.monoTag).foregroundColor(theme.textTertiary)
                    .padding(.bottom, 2)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(theme.monoBody)
                    .foregroundColor(theme.textPrimary)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.codeBlock)
        .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
    }
}

/// 折叠码块（限流页假 headers 用）。
struct CollapsibleCodeBlock: View {
    let summary: String
    let lines: [String]

    @Environment(\.tomatoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                    Text(summary).font(theme.monoBody).foregroundColor(theme.textSecondary)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            if expanded {
                CodeBlock(lines: lines)
            }
        }
    }
}

// MARK: - CapsuleProgress

/// 胶囊进度条：fill 连续渐变 accent→accentDeep（UI-SPEC §3.3，修 v1 的 0.8 突变）。
struct CapsuleProgress: View {
    let fraction: Double
    var height: CGFloat = 8
    /// 倒放模式（限流页细进度线：从满到空）
    var reversed: Bool = false
    /// 纯 accentDeep 填充（限流页用：主按钮才是本屏唯一亮橙，UI-SPEC §3.5）
    var solidDeep: Bool = false

    @Environment(\.tomatoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let f = min(1, max(0, reversed ? 1 - fraction : fraction))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: theme.progressRadius, style: .continuous)
                    .fill(theme.border)
                RoundedRectangle(cornerRadius: theme.progressRadius, style: .continuous)
                    .fill(solidDeep
                        ? AnyShapeStyle(theme.accentDeep)
                        : AnyShapeStyle(LinearGradient(colors: [theme.accent, theme.accentDeep],
                                                       startPoint: .leading, endPoint: .trailing)))
                    .frame(width: max(height, geo.size.width * f))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .linear(duration: 1.0), value: fraction)
    }
}

// MARK: - QuotaDots

/// 额度点阵（UI-SPEC §3.1）：剩余 = accent 实心，已用 = border 空心。
struct QuotaDots: View {
    let remaining: Int
    let max: Int

    @Environment(\.tomatoTheme) private var theme
    @Environment(\.rltPrimaryLocale) private var locale

    var body: some View {
        if max <= 12, max > 0 {
            HStack(spacing: 6) {
                ForEach(0..<max, id: \.self) { i in
                    Circle()
                        .strokeBorder(theme.border, lineWidth: i < remaining ? 0 : 1.5)
                        .background(Circle().fill(i < remaining ? theme.accent : .clear))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.t(
                "quota.remaining",
                locale: locale,
                args: ["remaining": "\(remaining)", "max": "\(max)"]
            ))
        }
    }
}
