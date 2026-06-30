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
    private var isSprinting = false
    private var dashWindow: NSWindow?
    private let dashModel = DashModel()
    private let popModel = PopModel()
    private let connectionModel = ConnectionModel()
    private let preferencesModel = PreferencesModel()

    private func updateStatusImage() {
        statusItem.button?.image = dooyouImage(frameIdx, isSprinting: isSprinting, mascot: preferencesModel.mascot, background: preferencesModel.backgroundTheme)
    }

    @objc func openDashboard() {
        popover.performClose(nil)
        if let w = dashWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); dashModel.refresh(); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "DOOYOU"
        w.center()
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: DashboardView(model: dashModel, connections: connectionModel, preferences: preferencesModel))
        dashWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        _selfCheck()
        NSApp.setActivationPolicy(.accessory)   // menu-bar only, no dock icon
        statusItem = NSStatusBar.system.statusItem(withLength: statusItemLength)
        if let b = statusItem.button {
            b.image = dooyouImage(0, isSprinting: false, mascot: preferencesModel.mascot, background: preferencesModel.backgroundTheme)
            b.imagePosition = .imageLeading
            b.imageScaling = .scaleProportionallyDown
            b.action = #selector(togglePopover)
            b.target = self
        }
        preferencesModel.didChange = { [weak self] in self?.updateStatusImage() }
        popover.behavior = .transient
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

    private func speed(load: Double) -> Double { max(0.05, 0.5 - load / 100 * 0.45) }

    private func sampleStats() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let s = sampleSys()
            DispatchQueue.main.async {
                guard let self else { return }
                self.popModel.sys = s
                let load = max(s.cpu, s.memPct > 85 ? s.memPct : 0)   // CPU, or memory when under pressure
                let want = self.speed(load: load)
                let sprinting = want <= 0.18
                if sprinting != self.isSprinting {
                    self.isSprinting = sprinting
                    self.updateStatusImage()
                }
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
            self.frameIdx = (self.frameIdx + 1) % dooyouFrames.count
            self.updateStatusImage()
        }
    }

    @objc private func togglePopover() {
        guard let b = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        if popover.contentViewController == nil {   // build once; updates flow via popModel
            let hc = NSHostingController(rootView: DashView(model: popModel, connections: connectionModel))
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
            DispatchQueue.main.async {
                guard let self else { return }
                self.snap = s
                self.popModel.snap = s   // SwiftUI updates the popover in place — no controller swap
                self.popModel.powerMode = pm
                self.popModel.launchAgent = launchAgent
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

    func applyPower(_ mode: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            applyPowerMode(mode)
            let cur = currentPowerMode()
            DispatchQueue.main.async { self?.popModel.powerMode = cur }
        }
    }
}

final class PopModel: ObservableObject {
    @Published var snap = Snapshot()
    @Published var powerMode = ""
    @Published var sys = SysStats()
    @Published var launchAgent = LaunchAgentStatus()
}

func powerIcon(_ mode: String) -> String {
    switch mode {
    case "피시": return "bolt.fill"
    case "맥미니": return "macmini"
    default: return "laptopcomputer"
    }
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
                 seg("wk", a.weeklyPct, a.weeklyResetsAt)].compactMap { $0 }
    if parts.isEmpty, let note = a.limitNote { return Text(note).foregroundColor(.secondary) }
    guard let first = parts.first else { return nil }
    return parts.dropFirst().reduce(first) { $0 + Text("  ") + $1 }
}

struct DashView: View {
    @ObservedObject var model: PopModel
    @ObservedObject var connections: ConnectionModel
    var snap: Snapshot { model.snap }
    var sys: SysStats { model.sys }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("dooyou").font(.headline)
                Spacer()
                Button { (NSApp.delegate as? AppDelegate)?.forceRefresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.plain).help("새로고침")
                Text(snap.activeAgents > 0 ? "활발" : "대기")
                    .font(.caption2).padding(.horizontal, 7).padding(.vertical, 2)
                    .background(snap.activeAgents > 0 ? Color.green.opacity(0.25) : Color.gray.opacity(0.2))
                    .clipShape(Capsule())
            }
            HStack(spacing: 6) {
                Text("에이전트 \(snap.activeAgents)개 동작 중")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("오늘 \(eok(snap.today))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            CoordinatorOverview(status: model.launchAgent)
            CompactConnectionSection(model: connections) {
                (NSApp.delegate as? AppDelegate)?.openDashboard()
            }
            SystemOverview(sys: sys)
            Divider()
            HStack { Text("합계 · 오늘").bold(); Spacer(); Text(eok(snap.today)).bold() }
            HStack { Text("합계 · 7일").foregroundStyle(.secondary); Spacer(); Text(eok(snap.week)).foregroundStyle(.secondary) }
            HStack { Text("API 환산 · 오늘").font(.subheadline); Spacer(); Text(usd(snap.todayCost)).font(.subheadline).foregroundStyle(.green) }
            HStack { Text("API 환산 · 7일").font(.caption).foregroundStyle(.secondary); Spacer(); Text(usd(snap.weekCost)).font(.caption).foregroundStyle(.secondary) }
            Divider()
            ForEach(snap.accounts) { a in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(a.name).font(.callout)
                        if let e = a.email { Text(e).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("오늘 \(eok(a.today)) · \(usd(a.todayCost))").font(.caption)
                        Text("7일 \(eok(a.week)) · \(usd(a.weekCost))").font(.caption2).foregroundStyle(.secondary)
                        if let hud = hudText(a) { hud.font(.caption2) }
                    }
                }
            }
            Divider()
            Button { (NSApp.delegate as? AppDelegate)?.openDashboard() } label: {
                HStack { Image(systemName: "chart.bar.xaxis"); Text("대시보드 열기"); Spacer() }
            }
            .buttonStyle(.plain).font(.callout)
            HStack { Text("전원 모드").font(.caption).foregroundStyle(.secondary)
                if !snap.accounts.isEmpty, !model.powerMode.isEmpty {
                    Spacer(); Text("현재 \(model.powerMode)").font(.caption2).foregroundStyle(.secondary)
                } }
            HStack(spacing: 6) {
                ForEach(powerModes, id: \.self) { m in
                    let on = model.powerMode == m
                    Button { (NSApp.delegate as? AppDelegate)?.applyPower(m) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: powerIcon(m)).font(.title3)
                            Text(m).font(.caption2)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(on ? Color.accentColor.opacity(0.22) : Color.gray.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.accentColor : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct CoordinatorOverview: View {
    let status: LaunchAgentStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.isPersistent ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(status.isPersistent ? DooyouStyle.success : DooyouStyle.warning)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
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
                Text("PID \(pid)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background((status.isPersistent ? DooyouStyle.success : DooyouStyle.warning).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke((status.isPersistent ? DooyouStyle.success : DooyouStyle.warning).opacity(0.18), lineWidth: 1))
        .help(status.program.isEmpty ? status.detail : status.program)
    }
}

struct SystemOverview: View {
    let sys: SysStats

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("시스템").font(.headline)
                Spacer()
                Text(systemSummary)
                    .font(.caption2)
                    .foregroundStyle(summaryColor)
            }
            SystemLoadRow(
                label: "CPU",
                value: "\(Int(sys.cpu.rounded()))%",
                detail: "실시간",
                pct: sys.cpu
            )
            SystemLoadRow(
                label: "메모리",
                value: "\(Int(sys.memPct.rounded()))%",
                detail: String(format: "%.1f/%.0fGB", sys.memUsed, sys.memTotal),
                pct: sys.memPct
            )
            HStack(spacing: 8) {
                ResourceChip(
                    label: "SSD 여유",
                    value: String(format: "%.0fGB", sys.diskFreeGB),
                    color: sys.diskFreeGB < 25 ? DooyouStyle.warning : .primary
                )
                ResourceChip(
                    label: "NET",
                    value: "↓\(rate(sys.netDownBytesPerSec)) ↑\(rate(sys.netUpBytesPerSec))",
                    color: DooyouStyle.info
                )
                ResourceChip(
                    label: "메모리 스왑",
                    value: sys.swap < 0.05 ? "0" : String(format: "%.1fGB", sys.swap),
                    color: sys.swap >= 1 ? DooyouStyle.warning : .primary
                )
                .help("RAM이 부족할 때 macOS가 디스크로 밀어낸 임시 메모리입니다.")
            }
        }
        .padding(12)
        .background(DooyouStyle.surfaceElevated.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private var maxPressure: Double { max(sys.cpu, sys.memPct, sys.swap >= 1 ? 75 : 0) }
    private var systemSummary: String {
        if maxPressure >= 90 { return "높음" }
        if maxPressure >= 70 { return "주의" }
        return "여유"
    }
    private var summaryColor: Color { loadColor(maxPressure) }
}

struct SystemLoadRow: View {
    let label: String
    let value: String
    let detail: String
    let pct: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(loadColor(pct))
                    .frame(width: 48, alignment: .leading)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(pressureWord(pct))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(loadColor(pct))
            }
            MiniProgressBar(value: pct / 100, color: loadColor(pct))
        }
        .padding(.vertical, 2)
    }
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
