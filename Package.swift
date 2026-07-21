// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RateLimitTomato",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 直接依赖（docs/DEPENDENCIES.md）：全局快捷键 / 开机自启 / MenuBarExtra 底层访问
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.0.0"),
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.0.0"),
    ],
    targets: [
        // 平台中立核心：状态机、数据模型、持久化、假数据生成、i18n、热力图聚合
        .target(
            name: "TomatoCore",
            path: "Sources/TomatoCore"
        ),
        // UI 库：主题令牌、组件、视图、接线层（拆库以支持快照测试）
        .target(
            name: "RateLimitTomatoUI",
            dependencies: [
                "TomatoCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
            ],
            path: "Sources/RateLimitTomatoUI"
        ),
        // macOS 菜单栏 App 壳：@main 与 Scene 装配
        .executableTarget(
            name: "RateLimitTomato",
            dependencies: [
                "RateLimitTomatoUI", "TomatoCore",
                .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess"),
            ],
            path: "Sources/RateLimitTomato"
        ),
        .testTarget(
            name: "TomatoCoreTests",
            dependencies: ["TomatoCore"],
            path: "Tests/TomatoCoreTests"
        ),
        // UI 快照渲染（ImageRenderer 离屏出 PNG，视觉 QA 用；设 RLT_SNAPSHOT_DIR 时才落盘）
        .testTarget(
            name: "RLTSnapshotTests",
            dependencies: ["RateLimitTomatoUI", "TomatoCore"],
            path: "Tests/RLTSnapshotTests"
        ),
        .testTarget(
            name: "RateLimitTomatoUITests",
            dependencies: ["RateLimitTomatoUI", "TomatoCore"],
            path: "Tests/RateLimitTomatoUITests"
        ),
    ]
)
