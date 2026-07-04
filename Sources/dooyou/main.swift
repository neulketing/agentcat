import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemLength: CGFloat = 82
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var snap = Snapshot()
    private var frameIdx = 0
    private var animTimer: Timer?
    private var animInterval = 0.45        // current frame interval (idle stroll)
    private var motionTier: MotionTier = .walk
    private var dashWindow: NSWindow?
    private let dashModel = DashModel()
    private let popModel = PopModel()
    private let connectionModel = ConnectionModel()
    private let preferencesModel = PreferencesModel()
    private let routerStore = RouterDecisionStore()
    private var routerAPI: RouterAPI?

    private func updateStatusImage() {
        statusItem.button?.image = dooyouImage(frameIdx, tier: motionTier, mascot: preferencesModel.mascot, background: preferencesModel.backgroundTheme)
    }

    @objc func openDashboard() {
        popover.performClose(nil)
        if let w = dashWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); dashModel.refresh(); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "DOOYOU"
        w.center()
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: DashboardView(model: dashModel, connections: connectionModel, preferences: preferencesModel, routerStore: routerStore))
        dashWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    @objc func openRouterDashboard() {
        dashModel.requestedRoute = .router
        openDashboard()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        if CommandLine.arguments.contains("--snapshot") {
            SnapshotRenderer.run(args: CommandLine.arguments)   // UI를 PNG로 렌더 후 exit(0) — Fable이 볼 수 있게
            return
        }
        _selfCheck()
        NSApp.setActivationPolicy(.accessory)   // menu-bar only, no dock icon
        statusItem = NSStatusBar.system.statusItem(withLength: statusItemLength)
        if let b = statusItem.button {
            b.image = dooyouImage(0, tier: .rest, mascot: preferencesModel.mascot, background: preferencesModel.backgroundTheme)
            b.imagePosition = .imageLeading
            b.imageScaling = .scaleProportionallyDown
            b.action = #selector(togglePopover)
            b.target = self
        }
        preferencesModel.didChange = { [weak self] in self?.updateStatusImage() }
        popover.behavior = .transient
        routerAPI = RouterAPI(store: routerStore)
        routerAPI?.start()
        refresh()
        startAnim()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sampleStats() }
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refreshLaunchAgentStatus() }
        if CommandLine.arguments.contains("--dashboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.openDashboard() }
        }
        if CommandLine.arguments.contains("--popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.togglePopover() }
        }
    }

    private func sampleStats() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let s = sampleSys()
            DispatchQueue.main.async {
                guard let self else { return }
                self.popModel.sys = s
                let load = max(s.cpu, s.memPct > 85 ? s.memPct : 0)   // CPU, or memory when under pressure
                let tier = MotionTier.from(load: load)
                if tier != self.motionTier {
                    self.motionTier = tier
                    self.updateStatusImage()
                }
                let want = tier.frameInterval
                if abs(want - self.animInterval) > 0.002 { self.animInterval = want; self.startAnim() }
            }
        }
    }

    private func refreshLaunchAgentStatus() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = sampleLaunchAgent()
            DispatchQueue.main.async { self?.popModel.launchAgent = status }
        }
    }
    private func startAnim() {
        animTimer?.invalidate()
        animTimer = Timer.scheduledTimer(withTimeInterval: animInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            // 모노토닉 틱(2026-07-04): 종전 %4는 0~3만 순환 → 유휴가 늘 같은 숨쉬기.
            // 큰 주기(4의 배수)로 돌려 다리 위상(%4)은 그대로, 매크로 사이클로 유휴 제스처를 얹는다.
            self.frameIdx = (self.frameIdx + 1) % 100_000
            self.updateStatusImage()
        }
    }

    @objc private func togglePopover() {
        guard let b = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        if popover.contentViewController == nil {   // build once; updates flow via popModel
            let hc = NSHostingController(rootView: DashView(model: popModel, connections: connectionModel, routerStore: routerStore))
            hc.sizingOptions = [.preferredContentSize]   // popover sizes to content, no clip/empty
            popover.contentViewController = hc
        }
        popModel.snap = snap
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
    }

    private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let s = scanAll()
            let pm = currentPowerMode()
            let launchAgent = sampleLaunchAgent()
            let dispatch = loadDispatchLog()
            let pending = loadPendingApprovals()
            let etas = BurnMonitor.shared.record(s.accounts)
            DispatchQueue.main.async {
                guard let self else { return }
                self.snap = s
                self.popModel.snap = s   // SwiftUI updates the popover in place — no controller swap
                self.popModel.powerMode = pm
                self.popModel.launchAgent = launchAgent
                self.popModel.dispatch = dispatch
                self.popModel.pending = pending
                self.popModel.burnEta = etas
                self.statusItem.button?.title = " " + eok(s.today)
            }
        }
    }

    func forceRefresh() {
        connectionModel.refresh()
        refresh()
        sampleStats()
        refreshLaunchAgentStatus()
    }   // manual refresh button

    // 커넥터 새로고침 = 연결 재확인 + 전 계정 라이브 사용량 프로브 강제 + 재스캔.
    // 프로브는 fire-and-forget이라 limits 파일에 쓸 시간을 준 뒤 2차 재스캔으로 최신값 반영.
    func forceRefreshUsage() {
        connectionModel.refresh()
        refresh()   // 1차: 캐시 기준 즉시 갱신
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            forceProbeAllLimits()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self?.refresh() }  // 2차: 프로브 결과 반영
        }
    }

    func applyPower(_ mode: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            applyPowerMode(mode)
            let cur = currentPowerMode()
            DispatchQueue.main.async { self?.popModel.powerMode = cur }
        }
    }

    func submitRouterApproval(routeId: String, approve: Bool) {
        _ = routerAPI?.submitApproval(routeId: routeId, approve: approve)
    }
}

final class PopModel: ObservableObject {
    @Published var snap = Snapshot()
    @Published var powerMode = ""
    @Published var sys = SysStats()
    @Published var launchAgent = LaunchAgentStatus()
    @Published var dispatch: [DispatchEntry] = []
    @Published var pending: [PendingApproval] = []    // exec 게이트 승인 대기 (텔레그램 원탭 대상)
    @Published var burnEta: [String: BurnEta] = [:]   // 계정명 → 구속 창 소진 ETA (제일 먼저 바닥나는 창)
}

func powerIcon(_ mode: String) -> String {
    switch mode {
    case "피시": return "bolt.fill"
    case "맥미니": return "macmini"
    default: return "laptopcomputer"
    }
}

// 팝오버용 압축 한도 — "5h 82%(1h)" 형식으로 한도와 리셋까지 남은 시간을 함께 노출.
func hudCompact(_ a: Account) -> Text? {
    func seg(_ label: String, _ pct: Int?, _ reset: Date?) -> Text? {
        guard let p = pct else { return nil }
        let c: Color = p >= 90 ? DooyouStyle.error : (p >= 70 ? DooyouStyle.warning : DooyouStyle.success)
        var t = Text("\(label) ") + Text("\(p)%").foregroundColor(c).bold()
        if let reset {
            t = t + Text("(\(countdown(reset)))").foregroundColor(.secondary)
        }
        return t
    }
    let parts = [seg("5h", a.fiveHourPct, a.fiveHourResetsAt),
                 seg("wk", a.weeklyPct, a.weeklyResetsAt),
                 seg("Fable", a.fablePct, a.fableResetsAt),
                 seg("mo", a.monthlyPct, a.monthlyResetsAt)].compactMap { $0 }
    if parts.isEmpty, let note = a.limitNote { return Text(note).foregroundColor(.secondary) }
    guard let first = parts.first else { return nil }
    return parts.dropFirst().reduce(first) { $0 + Text("  ·  ").foregroundColor(.secondary) + $1 }
}

// OMC-style per-account limit HUD: "5h 3%(4h38m)  wk 95%(2d18h)" with colored %.
func hudText(_ a: Account) -> Text? {
    func seg(_ label: String, _ pct: Int?, _ reset: Date?) -> Text? {
        guard let p = pct else { return nil }
        let c: Color = p >= 90 ? .red : (p >= 70 ? .orange : .green)
        var t = Text("\(label) ") + Text("\(p)%").foregroundColor(c)
        if let r = reset { t = t + Text("(\(countdown(r)))").foregroundColor(.secondary) }
        return t
    }
    let parts = [seg("5h", a.fiveHourPct, a.fiveHourResetsAt),
                 seg("wk", a.weeklyPct, a.weeklyResetsAt),
                 seg("Fable", a.fablePct, a.fableResetsAt),   // 클로드 Fable 주간 (모든모델 wk와 별개)
                 seg("mo", a.monthlyPct, a.monthlyResetsAt)].compactMap { $0 }
    if parts.isEmpty, let note = a.limitNote { return Text(note).foregroundColor(.secondary) }
    guard let first = parts.first else { return nil }
    return parts.dropFirst().reduce(first) { $0 + Text("  ") + $1 }
}

struct DashView: View {
    @ObservedObject var model: PopModel
    @ObservedObject var connections: ConnectionModel
    @ObservedObject var routerStore: RouterDecisionStore
    var snap: Snapshot { model.snap }
    var sys: SysStats { model.sys }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("dooyou")
                        .font(.headline)
                    Text("오늘 \(eok(snap.today)) · 에이전트 \(snap.activeAgents)개")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button { (NSApp.delegate as? AppDelegate)?.forceRefresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(DooyouStyle.info)
                }
                .buttonStyle(.plain)
                .help("새로고침")
                StatusCapsule(text: snap.activeAgents > 0 ? "활발" : "대기",
                              color: snap.activeAgents > 0 ? DooyouStyle.success : .secondary)
            }
            .padding(12)
            .background(DooyouStyle.surfaceElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))

            CoordinatorOverview(status: model.launchAgent)
            CompactConnectionSection(model: connections, onRefresh: {
                (NSApp.delegate as? AppDelegate)?.forceRefreshUsage()
            }) {
                (NSApp.delegate as? AppDelegate)?.openDashboard()
            }
            RouterStatusStrip(store: routerStore) {
                (NSApp.delegate as? AppDelegate)?.openRouterDashboard()
            }
            DispatchStrip(entries: model.dispatch) {
                (NSApp.delegate as? AppDelegate)?.openDashboard()
            }
            PendingApprovalStrip(pending: model.pending) {
                (NSApp.delegate as? AppDelegate)?.openDashboard()
            }
            SystemOverview(sys: sys)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("사용량").font(.caption).fontWeight(.semibold)
                    Spacer()
                    Text("오늘 \(eok(snap.today))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text(usd(snap.todayCost))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(DooyouStyle.success)
                        .monospacedDigit()
                }
                HStack(spacing: 6) {
                    StatusCapsule(text: "7일 \(eok(snap.week))", color: DooyouStyle.info)
                    StatusCapsule(text: usd(snap.weekCost), color: DooyouStyle.success)
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .background(DooyouStyle.surfaceElevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("계정 한도").font(.caption).fontWeight(.semibold)
                    Text("괄호=리셋까지").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(snap.accounts.count)개")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                VStack(spacing: 6) {
                    ForEach(Array(snap.accounts.prefix(5))) { a in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(a.name).font(.callout).fontWeight(.semibold)
                                if let e = a.email {
                                    Text(e).font(.caption2).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 6)
                                Text("오늘 \(eok(a.today))")
                                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                            }
                            if let hud = hudCompact(a) {
                                hud.font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.78)
                            }
                            if let eta = model.burnEta[a.name] {
                                Text("이 속도면 \(eta.window) 소진 ~\(fmtEtaMin(eta.minutes))")
                                    .font(.caption2)
                                    .foregroundColor(eta.minutes <= 30 ? DooyouStyle.error : DooyouStyle.warning)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(DooyouStyle.surfaceSecondary.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
                        .help("오늘 \(eok(a.today)) \(usd(a.todayCost)) · 7일 \(eok(a.week)) \(usd(a.weekCost))")
                    }
                    if snap.accounts.count > 5 {
                        Text("외 \(snap.accounts.count - 5)개 계정은 대시보드에서 확인")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(DooyouStyle.surfaceElevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))

            Button { (NSApp.delegate as? AppDelegate)?.openDashboard() } label: {
                HStack { Image(systemName: "chart.bar.xaxis"); Text("대시보드 열기"); Spacer() }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(DooyouStyle.info.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(DooyouStyle.info)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("전원 모드").font(.caption).fontWeight(.semibold)
                    if !snap.accounts.isEmpty, !model.powerMode.isEmpty {
                        Spacer()
                        Text("현재 \(model.powerMode)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(powerModes, id: \.self) { m in
                        let on = model.powerMode == m
                        Button { (NSApp.delegate as? AppDelegate)?.applyPower(m) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: powerIcon(m)).font(.title3)
                                Text(m).font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(on ? DooyouStyle.accent : .primary)
                            .background(on ? DooyouStyle.accent.opacity(0.16) : DooyouStyle.surfaceSecondary.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? DooyouStyle.accent.opacity(0.55) : Color.primary.opacity(0.06), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .background(DooyouStyle.surfaceElevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))
        }
        .padding(12)
        .frame(width: 340)
        .background(
            LinearGradient(colors: [DooyouStyle.surfacePrimary, DooyouStyle.surfaceSecondary.opacity(0.45)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct CoordinatorOverview: View {
    let status: LaunchAgentStatus

    var body: some View {
        let tone = status.isPersistent ? DooyouStyle.success : DooyouStyle.warning
        HStack(spacing: 8) {
            Image(systemName: status.isPersistent ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tone)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(status.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let pid = status.pid {
                StatusCapsule(text: "PID \(pid)", color: tone)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tone.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tone.opacity(0.20), lineWidth: 1))
        .help(status.program.isEmpty ? status.detail : status.program)
    }
}

struct SystemOverview: View {
    let sys: SysStats

    // 팝오버 밀도 조정(2026-07-03): 바 2줄+칩 3개 → 요약 1줄. 상세는 대시보드가 담당.
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("시스템").font(.caption).fontWeight(.semibold)
                    StatusCapsule(text: systemSummary, color: summaryColor)
                }
                (Text("CPU ") + Text("\(Int(sys.cpu.rounded()))%").foregroundColor(loadColor(sys.cpu))
                 + Text("  메모리 ") + Text("\(Int(sys.memPct.rounded()))%").foregroundColor(loadColor(sys.memPct))
                 + Text("  SSD \(String(format: "%.0f", sys.diskFreeGB))G").foregroundColor(sys.diskFreeGB < 25 ? DooyouStyle.warning : .secondary)
                 + (sys.swap >= 0.05 ? Text("  메모리 스왑 \(String(format: "%.1f", sys.swap))G").foregroundColor(sys.swap >= 1 ? DooyouStyle.warning : .secondary) : Text(""))
                 + Text("  ↓\(rate(sys.netDownBytesPerSec))↑\(rate(sys.netUpBytesPerSec))").foregroundColor(.secondary))
                    .font(.caption2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DooyouStyle.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(summaryColor.opacity(0.16), lineWidth: 1))
        .help("상세 그래프는 대시보드에서")
    }

    private var maxPressure: Double { max(sys.cpu, sys.memPct, sys.swap >= 1 ? 75 : 0) }
    private var systemSummary: String {
        if maxPressure >= 90 { return "높음" }
        if maxPressure >= 70 { return "주의" }
        return "여유"
    }
    private var summaryColor: Color { loadColor(maxPressure) }
}

func rate(_ bytesPerSec: Double) -> String {
    if bytesPerSec >= 1_048_576 { return String(format: "%.1fM", bytesPerSec / 1_048_576) }
    if bytesPerSec >= 1024 { return String(format: "%.0fK", bytesPerSec / 1024) }
    return "\(Int(bytesPerSec))B"
}

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "emit" {
    let path = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : defaultMiniEmitPath
    emitSnapshot(to: path)
    exit(0)
}

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "dump" {
    let s = scanAll()
    print("agents=\(s.activeAgents)  today=\(eok(s.today)) \(usd(s.todayCost))  week=\(eok(s.week)) \(usd(s.weekCost))")
    for a in s.accounts {
        var line = "  \(a.name): 오늘 \(eok(a.today)) \(usd(a.todayCost)) · 7일 \(eok(a.week)) \(usd(a.weekCost))"
        if let p = a.fiveHourPct { line += " · 5h \(p)%" + (a.fiveHourResetsAt.map { "(\(countdown($0)))" } ?? "") }
        if let p = a.weeklyPct { line += " · wk \(p)%" + (a.weeklyResetsAt.map { "(\(countdown($0)))" } ?? "") }
        if let p = a.fablePct { line += " · Fable \(p)%" + (a.fableResetsAt.map { "(\(countdown($0)))" } ?? "") }
        if let p = a.monthlyPct { line += " · mo \(p)%" + (a.monthlyResetsAt.map { "(\(countdown($0)))" } ?? "") }
        if let note = a.limitNote { line += " · \(note)" }
        print(line)
    }
    let d = scan(daysWindow: 1095)
    let w7 = windowSum(d.agg.byDay, lastDays: 7), w30 = windowSum(d.agg.byDay, lastDays: 30), wAll = windowSum(d.agg.byDay, lastDays: nil)
    print("--- API 환산 비용 --- cacheHit=\(d.agg.cacheHitPct)%  (\(d.agg.byDay.count)일 데이터)")
    print("  7일 : \(eok(w7.tokens)) → \(usd(w7.cost))")
    print("  30일: \(eok(w30.tokens)) → \(usd(w30.cost))")
    print("  전체: \(eok(wAll.tokens)) → \(usd(wAll.cost))")
    print("models:"); for (k, v) in d.agg.byModel.sorted(by: { $0.value.tokens > $1.value.tokens }).prefix(8) { print("  \(k): \(eok(v.tokens)) \(usd(v.cost))") }
    print("projects:"); for (k, v) in d.agg.byProject.sorted(by: { $0.value.tokens > $1.value.tokens }).prefix(6) { print("  \(k): \(eok(v.tokens)) \(usd(v.cost))") }
    exit(0)
}

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "launch-status" {
    let status = sampleLaunchAgent()
    print("title=\(status.title)")
    print("detail=\(status.detail)")
    print("plist=\(status.plistExists ? "yes" : "no") runAtLoad=\(status.runAtLoad ? "yes" : "no") keepAlive=\(status.keepAlive ? "yes" : "no")")
    print("loaded=\(status.loaded ? "yes" : "no") running=\(status.running ? "yes" : "no") pid=\(status.pid.map(String.init) ?? "-")")
    if !status.program.isEmpty { print("program=\(status.program)") }
    if let error = status.error { print("error=\(error)") }
    exit(0)
}

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "router-self-test" {
    do {
        try RouterAPISelfTest.run()
        print("router-self-test ok")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("router-self-test failed: \(error)\n".utf8))
        exit(1)
    }
}
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "router-integration-self-test" {
    do {
        let out = try RouterIntegrationSelfTest.run(decisionPath: CommandLine.arguments[2])
        print(out)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("router-integration-self-test failed: \(error)\n".utf8))
        exit(1)
    }
}
if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "router-ui-self-test" {
    do {
        try RouterUISelfTest.run()
        print("router-ui-self-test ok")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("router-ui-self-test failed: \(error)\n".utf8))
        exit(1)
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
