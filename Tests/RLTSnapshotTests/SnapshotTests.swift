import AppKit
import SwiftUI
import XCTest
@testable import RateLimitTomatoUI
@testable import TomatoCore

/// 视觉 QA 快照（UI-SPEC §6）：九状态 × 三主题离屏渲染成 PNG。
/// 设 `RLT_SNAPSHOT_DIR` 时落盘；未设时仅验证渲染不崩（CI 友好）。
@MainActor
final class SnapshotTests: XCTestCase {
    private var outDir: URL? {
        ProcessInfo.processInfo.environment["RLT_SNAPSHOT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }

    // MARK: 状态装配

    /// 造一个隔离 VM：MockClock 驱动，临时存储，免责已确认。
    private func makeVM(provider: Provider = .a) -> (AppViewModel, MockClock) {
        let clock = MockClock(start: Date(timeIntervalSince1970: 1_751_965_200)) // 2025-07-08 09:00 UTC
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlt-snap-\(UUID().uuidString)", isDirectory: true)
        let vm = AppViewModel(storeDirectory: dir, clock: clock)
        vm.stop() // 快照不需要真计时器
        vm.acknowledgeDisclaimer()
        vm.applySettings {
            $0.provider = provider
        }
        XCTAssertTrue(vm.settings.parodyDisclaimerAck, "快照 VM 必须先通过首次免责门")
        XCTAssertFalse(vm.showDisclaimer, "确认免责后不应再渲染免责叠层")
        XCTAssertEqual(vm.settings.provider, provider, "快照 VM 必须应用目标 provider")
        return (vm, clock)
    }

    private func advance(_ vm: AppViewModel, _ clock: MockClock, by seconds: TimeInterval) {
        clock.advance(by: seconds)
        vm.tick()
    }

    private func assertSnapshotState(
        _ vm: AppViewModel,
        phase: AppPhase,
        provider: Provider,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(vm.phase, phase, "快照状态装配错误", file: file, line: line)
        XCTAssertEqual(vm.settings.provider, provider, "快照 provider 装配错误", file: file, line: line)
    }

    private func vmIdle(_ provider: Provider = .a) -> AppViewModel {
        let vm = makeVM(provider: provider).0
        assertSnapshotState(vm, phase: .idle, provider: provider)
        return vm
    }

    private func vmFocusing(_ provider: Provider = .a, note: String? = "写 UI 设计规格 v2") -> AppViewModel {
        let (vm, clock) = makeVM(provider: provider)
        vm.pendingNote = note ?? ""
        vm.sendRequest()
        advance(vm, clock, by: 2)          // SENDING → FOCUSING
        advance(vm, clock, by: 12 * 60 + 40) // 12m40s 进行中
        assertSnapshotState(vm, phase: .focusing, provider: provider)
        return vm
    }

    private func vmRateLimited(_ provider: Provider = .a) -> AppViewModel {
        let (vm, clock) = makeVM(provider: provider)
        vm.sendRequest()
        advance(vm, clock, by: 2)
        advance(vm, clock, by: 25 * 60)    // → COMPLETED
        advance(vm, clock, by: 3)          // → RATE_LIMITED
        advance(vm, clock, by: 90)         // 冷却进行 1.5 分钟
        assertSnapshotState(vm, phase: .rateLimited, provider: provider)
        return vm
    }

    private func vmSending(_ provider: Provider = .a) -> AppViewModel {
        let (vm, _) = makeVM(provider: provider)
        vm.sendRequest()
        assertSnapshotState(vm, phase: .sending, provider: provider)
        return vm
    }

    private func vmCompleted(_ provider: Provider = .a) -> AppViewModel {
        let (vm, clock) = makeVM(provider: provider)
        vm.sendRequest()
        advance(vm, clock, by: 2)
        advance(vm, clock, by: 25 * 60)
        assertSnapshotState(vm, phase: .completed, provider: provider)
        return vm
    }

    private func vmAborted(_ provider: Provider = .a) -> AppViewModel {
        let (vm, clock) = makeVM(provider: provider)
        vm.sendRequest()
        advance(vm, clock, by: 2)
        advance(vm, clock, by: 9 * 60)
        vm.abortRequest()
        assertSnapshotState(vm, phase: .aborted, provider: provider)
        return vm
    }

    private func vmTeapot(_ provider: Provider = .a) -> AppViewModel {
        let (vm, clock) = makeVM(provider: provider)
        for _ in 0..<3 {
            vm.sendRequest()
            advance(vm, clock, by: 2)
            advance(vm, clock, by: 30)
            vm.abortRequest()
            vm.skipCooldown()
        }
        assertSnapshotState(vm, phase: .teapot, provider: provider)
        return vm
    }

    private func vmReset(_ provider: Provider = .a) -> AppViewModel {
        let (vm, clock) = makeVM(provider: provider)
        vm.sendRequest()
        advance(vm, clock, by: 2)
        advance(vm, clock, by: 25 * 60)
        advance(vm, clock, by: 3)
        // 前一步已比 COMPLETED 自然边界多推进 1.5s；这里落在 RESET 的 2s 展示窗内。
        advance(vm, clock, by: 5 * 60 - 1)
        assertSnapshotState(vm, phase: .reset, provider: provider)
        return vm
    }

    private func vmExhausted(_ provider: Provider = .a) -> AppViewModel {
        let (vm, clock) = makeVM(provider: provider)
        vm.applySettings { $0.maxPerDay = 1 }
        vm.sendRequest()
        advance(vm, clock, by: 2)
        advance(vm, clock, by: 25 * 60)
        advance(vm, clock, by: 3)
        vm.skipCooldown()
        assertSnapshotState(vm, phase: .idle, provider: provider)
        XCTAssertTrue(vm.isQuotaExhausted, "503 快照必须真的耗尽当日额度")
        return vm
    }

    // MARK: 渲染

    private func render(
        _ vm: AppViewModel,
        name: String,
        phase: AppPhase,
        provider: Provider
    ) throws {
        assertSnapshotState(vm, phase: phase, provider: provider)
        let view = MenubarPanel()
            .environmentObject(vm)
            .environment(\.tomatoTheme, vm.theme)
            .environment(\.rltShowSecondary, vm.settings.language != "en")
            .environment(\.rltPrimaryLocale, vm.settings.language)
        try renderView(view, name: name, width: 380)
    }

    private func renderView(_ view: some View, name: String, width: CGFloat) throws {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage else {
            XCTFail("渲染失败：\(name)"); return
        }
        XCTAssertGreaterThan(nsImage.size.height, 100, "\(name) 渲染高度异常")
        guard let dir = outDir else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("PNG 编码失败：\(name)"); return
        }
        try png.write(to: dir.appendingPathComponent("\(name).png"))
    }

    // MARK: 用例

    func testSnapshotAllStatesProviderA() throws {
        try render(vmIdle(), name: "a1-idle", phase: .idle, provider: .a)
        try render(vmSending(), name: "a2-sending", phase: .sending, provider: .a)
        try render(vmFocusing(), name: "a3-focusing", phase: .focusing, provider: .a)
        try render(vmCompleted(), name: "a4-completed", phase: .completed, provider: .a)
        try render(vmRateLimited(), name: "a5-ratelimited", phase: .rateLimited, provider: .a)
        try render(vmAborted(), name: "a6-aborted", phase: .aborted, provider: .a)
        try render(vmTeapot(), name: "a7-teapot", phase: .teapot, provider: .a)
        try render(vmReset(), name: "a8-reset", phase: .reset, provider: .a)
        try render(vmExhausted(), name: "a9-503", phase: .idle, provider: .a)
    }

    func testSnapshotProviderBAndC() throws {
        try render(vmIdle(.b), name: "b1-idle", phase: .idle, provider: .b)
        try render(vmRateLimited(.b), name: "b5-ratelimited", phase: .rateLimited, provider: .b)
        try render(vmIdle(.c), name: "c1-idle", phase: .idle, provider: .c)
        try render(vmRateLimited(.c), name: "c5-ratelimited", phase: .rateLimited, provider: .c)
        try render(vmFocusing(.c), name: "c3-focusing", phase: .focusing, provider: .c)
    }

    func testSnapshotAuxiliarySurfaces() throws {
        let (vm, _) = makeVM()
        try renderView(
            SettingsView()
                .environmentObject(vm)
                .environment(\.tomatoTheme, vm.theme),
            name: "x1-settings", width: 460
        )
        // 深色主题下设置页对比度（v3.2.1 反馈#2：原生控件黑字黑底隐身）
        let (vmB, _) = makeVM(provider: .b)
        try renderView(
            SettingsView()
                .environmentObject(vmB)
                .environment(\.tomatoTheme, vmB.theme),
            name: "x7-settings-b", width: 460
        )
        try renderView(
            UpgradeSheet()
                .environmentObject(vm)
                .environment(\.tomatoTheme, vm.theme),
            name: "x2-upgrade", width: 320
        )
        try renderView(
            UsageDashboardView(sessions: sampleSessions(), endingAt: Date(), onRefresh: {})
                .environmentObject(vm)
                .environment(\.tomatoTheme, vm.theme)
                .frame(height: 560),
            name: "x3-usage", width: 760
        )
        try renderView(
            UsageDashboardView(sessions: [], endingAt: Date(), onRefresh: {})
                .environmentObject(vm)
                .environment(\.tomatoTheme, vm.theme)
                .frame(height: 560),
            name: "x4-usage-empty", width: 760
        )
        // B 主题热力图（等级色须走 accent 阶梯而非 A 色板）
        let sessionsB = sampleSessions()
        let nowB = Date()
        try renderView(
            HeatmapGrid(
                cells: HeatmapAggregator.yearGrid(sessions: sessionsB, endingAt: nowB, calendar: .current),
                monthLabels: HeatmapAggregator.monthLabels(endingAt: nowB, calendar: .current),
                onSelectDay: { _ in }
            )
            .background(TomatoTheme.providerB.card)
            .environment(\.tomatoTheme, TomatoTheme.providerB),
            name: "x6-heatmap-grid-b", width: 780
        )
    }

    /// 热力图网格本体（ScrollView 内容 ImageRenderer 画不出，单独渲染验收）。
    func testSnapshotHeatmapGrid() throws {
        let sessions = sampleSessions()
        let now = Date()
        let grid = HeatmapAggregator.yearGrid(sessions: sessions, endingAt: now, calendar: .current)
        let labels = HeatmapAggregator.monthLabels(endingAt: now, calendar: .current)
        XCTAssertEqual(grid.count, 52)
        XCTAssertGreaterThan(grid.flatMap { $0 }.filter { $0.level > 0 }.count, 30, "样例数据应点亮足量格子")
        let view = HeatmapGrid(cells: grid, monthLabels: labels, onSelectDay: { _ in })
            .background(TomatoTheme.providerA.card)
            .environment(\.tomatoTheme, TomatoTheme.providerA)
        try renderView(view, name: "x5-heatmap-grid", width: 780)
    }

    /// log 流生成器逻辑非空（快照里 ScrollView 空白属渲染器局限，这里锁逻辑）。
    func testFakeLogStreamProducesLines() {
        let gen = FakeLogStreamGenerator(seed: 42)
        let lines = gen.lines(elapsed: 12 * 60 + 40)
        XCTAssertGreaterThan(lines.count, 5, "12m40s 应产出多条 log")
        XCTAssertTrue(lines.contains { $0.contains("POST /v1/focus") })
        XCTAssertTrue(lines.contains { $0.contains("tokens used") })
    }

    /// 造 90 天的确定性样例数据（固定种子，快照可复现）。
    private func sampleSessions() -> [FocusSession] {
        var out: [FocusSession] = []
        var day = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        var rng = SplitMix64(state: 20260708)
        while day <= Date() {
            let n = Int(rng.next() % 7)
            for i in 0..<n {
                let hour = [9, 10, 11, 14, 15, 16, 20][i % 7]
                out.append(FocusSession(
                    id: SessionID.generate(),
                    createdAt: day,
                    date: TomatoEngine.dateKey(now: day, calendar: .current),
                    startHour: hour, startMinute: 0, durationMin: 25,
                    status: i == 4 ? .aborted : .completed,
                    quality: 0, fakeTokens: 12000, fakeModel: "tomato-1.0",
                    note: nil, provider: .a
                ))
            }
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }
}
