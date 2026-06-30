import SwiftUI

final class DashModel: ObservableObject {
    @Published var dash = Dashboard()
    @Published var sys = SysStats()
    @Published var launchAgent = LaunchAgentStatus()
    @Published var loading = true
    func refresh() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let d = scan(daysWindow: 1095)   // all-time (within ~3y cache)
            DispatchQueue.main.async { self?.dash = d; self?.loading = false }
        }
    }
    func refreshSystem() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let s = sampleSys()
            DispatchQueue.main.async { self?.sys = s }
        }
    }
    func refreshLaunchAgent() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = sampleLaunchAgent()
            DispatchQueue.main.async { self?.launchAgent = status }
        }
    }
}

struct OnboardingCard: View {
    @ObservedObject var preferences: PreferencesModel
    @ObservedObject var connections: ConnectionModel

    var body: some View {
        if preferences.shouldShowOnboarding {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "pawprint.fill").foregroundStyle(DooyouStyle.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("dooyou에 오신 걸 환영해요").font(.headline)
                        Text("CLI 자동 탐지, API 키, MCP, 마스코트를 이 대시보드에서 바로 설정합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("완료") { preferences.finishOnboarding() }
                }
                HStack(spacing: 10) {
                    onboardingStep("1", "커넥터", "\(connections.installedDiscoveryCount)개 CLI 발견")
                    onboardingStep("2", "둘러보기", "오늘/7일/30일 사용량")
                    onboardingStep("3", "마스코트", preferences.mascot.title)
                }
            }
            .padding(12)
            .background(DooyouStyle.accent.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func onboardingStep(_ n: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 8) {
            Text(n).font(.caption).bold()
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(DooyouStyle.accent, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).bold()
                Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.white.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private let claudeColor = DooyouStyle.accent
private let codexColor = DooyouStyle.info
private let glmColor = Color(red: 0.20, green: 0.62, blue: 0.50)
private func usedColor(_ p: Int) -> Color { p >= 90 ? DooyouStyle.error : (p >= 70 ? DooyouStyle.warning : DooyouStyle.success) }

enum DashboardRoute: String, CaseIterable, Identifiable {
    case home, connectors, analytics, accounts, mascot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "홈"
        case .connectors: return "커넥터"
        case .analytics: return "분석"
        case .accounts: return "계정"
        case .mascot: return "마스코트"
        }
    }

    var subtitle: String {
        switch self {
        case .home: return "지금 상태"
        case .connectors: return "CLI/API/MCP"
        case .analytics: return "토큰·비용"
        case .accounts: return "사용량·한도"
        case .mascot: return "아이콘·배경"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .connectors: return "link"
        case .analytics: return "chart.bar.xaxis"
        case .accounts: return "person.2"
        case .mascot: return "pawprint"
        }
    }
}

struct DashboardView: View {
    @ObservedObject var model: DashModel
    @ObservedObject var connections: ConnectionModel
    @ObservedObject var preferences: PreferencesModel
    @State private var route: DashboardRoute = .home

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleBar
                    routeContent
                }
                .padding(20)
            }
        }
        .background(dashboardBackground)
        .frame(minWidth: 980, minHeight: 700)
        .overlay(alignment: .top) {
            if model.loading { Text("불러오는 중…").font(.caption).padding(6)
                .background(.thinMaterial, in: Capsule()).padding(.top, 6) }
        }
        .onAppear {
            connections.refresh()
            model.refresh()
            model.refreshSystem()
            model.refreshLaunchAgent()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in model.refreshSystem() }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in model.refreshLaunchAgent() }
    }

    private var snap: Snapshot { model.dash.snap }
    private var agg: Aggregates { model.dash.agg }

    private var w7: (tokens: Int, cost: Double) { windowSum(agg.byDay, lastDays: 7) }
    private var w30: (tokens: Int, cost: Double) { windowSum(agg.byDay, lastDays: 30) }
    private var wAll: (tokens: Int, cost: Double) { windowSum(agg.byDay, lastDays: nil) }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                MascotPreview(mascot: preferences.mascot, background: preferences.backgroundTheme, height: 22)
                    .frame(width: 42, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("dooyou")
                        .font(.headline)
                    Text(preferences.mascot.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)

            VStack(spacing: 4) {
                ForEach(DashboardRoute.allCases) { item in
                    Button {
                        route = item
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: item.symbol)
                                .frame(width: 16)
                                .foregroundStyle(route == item ? DooyouStyle.accent : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.callout)
                                    .fontWeight(route == item ? .semibold : .medium)
                                Text(item.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(route == item ? DooyouStyle.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                StatusCapsule(text: "연결 \(connections.readyCount)/\(connections.statuses.count)", color: connections.readyCount > 0 ? DooyouStyle.success : .secondary)
                StatusCapsule(text: "에이전트 \(snap.activeAgents)", color: snap.activeAgents > 0 ? DooyouStyle.success : .secondary)
            }
            .padding(12)
        }
        .frame(width: 170)
        .background(DooyouStyle.surfaceElevated.opacity(0.40))
    }

    @ViewBuilder private var routeContent: some View {
        switch route {
        case .home:
            heroBand
            OnboardingCard(preferences: preferences, connections: connections)
            summaryGrid
            ConnectionHealthStrip(model: connections)
        case .connectors:
            routeHeader("커넥터", "다른 컴퓨터에서도 CLI, API, MCP를 자동 발견하거나 직접 추가합니다.")
            ConnectionHealthStrip(model: connections)
            ConnectionsDashboardSection(model: connections)
        case .analytics:
            routeHeader("분석", "오늘, 최근 7일, 30일, 전체 사용 흐름을 나눠 봅니다.")
            summaryGrid
            dailySection
            HStack(alignment: .top, spacing: 20) {
                breakdown("모델 분포 · 30일", model.dash.agg.byModel)
                breakdown("프로젝트별 · 30일", model.dash.agg.byProject)
            }
        case .accounts:
            routeHeader("계정", "Piolabs, NudgeSpace, Neulketing 라우트별로 계정을 묶어 봅니다.")
            accountRoutesSection
            accountsSection
            limitsSection
        case .mascot:
            routeHeader("마스코트", "메뉴바에서 움직이는 dooyou 캐릭터와 작은 배경을 고릅니다.")
            PreferencesDashboardSection(preferences: preferences)
        }
    }

    private func routeHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dashboardBackground: some View {
        LinearGradient(
            colors: [
                DooyouStyle.surfacePrimary,
                DooyouStyle.surfaceSecondary.opacity(0.46),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var titleBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DOOYOU")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("로컬 에이전트 사용량, 커넥터, 시스템 압력을 한곳에서 봅니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusCapsule(text: model.launchAgent.title, color: model.launchAgent.isPersistent ? DooyouStyle.success : DooyouStyle.warning)
            StatusCapsule(text: preferences.mascot.title, color: DooyouStyle.accent)
            Button("새로고침") {
                connections.refresh()
                model.refresh()
                model.refreshSystem()
                model.refreshLaunchAgent()
            }
        }
    }

    private var heroBand: some View {
        HStack(spacing: 18) {
            Image(nsImage: dooyouImage(1, height: 48, isSprinting: snap.activeAgents > 0, mascot: preferences.mascot, background: preferences.backgroundTheme))
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 56)
                .padding(12)
                .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.45), lineWidth: 1))
            VStack(alignment: .leading, spacing: 8) {
                Text(snap.activeAgents > 0 ? "활발하게 일하는 중" : "조용히 대기 중")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    StatusCapsule(text: "에이전트 \(snap.activeAgents)", color: snap.activeAgents > 0 ? DooyouStyle.success : .secondary)
                    StatusCapsule(text: "오늘 \(eok(snap.today))", color: DooyouStyle.success)
                    StatusCapsule(text: "연결 \(connections.readyCount)/\(connections.statuses.count)", color: connections.readyCount > 0 ? DooyouStyle.info : .secondary)
                    StatusCapsule(text: model.launchAgent.title, color: model.launchAgent.isPersistent ? DooyouStyle.success : DooyouStyle.warning)
                }
                Text(model.launchAgent.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    dashboardSystemChip("CPU", "\(Int(model.sys.cpu.rounded()))%", loadColor(model.sys.cpu))
                    dashboardSystemChip("MEM", "\(Int(model.sys.memPct.rounded()))%", loadColor(model.sys.memPct))
                }
                HStack(spacing: 6) {
                    dashboardSystemChip("SSD", String(format: "%.0fGB", model.sys.diskFreeGB), model.sys.diskFreeGB < 25 ? DooyouStyle.warning : .primary)
                    dashboardSystemChip("NET", "↓\(rate(model.sys.netDownBytesPerSec)) ↑\(rate(model.sys.netUpBytesPerSec))", DooyouStyle.info)
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [DooyouStyle.accent.opacity(0.16), Color.white.opacity(0.30), DooyouStyle.info.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func dashboardSystemChip(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 84, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
            DashboardStatTile(label: "오늘", value: eok(snap.today), sub: usd(snap.todayCost), color: DooyouStyle.success, systemImage: "calendar")
            DashboardStatTile(label: "7일", value: eok(w7.tokens), sub: usd(w7.cost), color: .primary, systemImage: "chart.line.uptrend.xyaxis")
            DashboardStatTile(label: "30일", value: eok(w30.tokens), sub: usd(w30.cost), color: .primary, systemImage: "calendar.badge.clock")
            DashboardStatTile(label: "전체", value: eok(wAll.tokens), sub: usd(wAll.cost), color: .primary, systemImage: "sum")
            DashboardStatTile(label: "캐시 적중", value: "\(agg.cacheHitPct)%", sub: "\(agg.byDay.count)일", color: DooyouStyle.success, systemImage: "memorychip")
        }
    }

    private var accountRoutesSection: some View {
        DooyouPanel(
            "계정 라우트",
            action: AnyView(Button("설정 파일") { openAccountRoutesFile() })
        ) {
            Text("우리 맥북 기준: Piolabs는 Claude/Codex 1번, NudgeSpace는 Claude/Codex 2번, Neulketing은 GLM/Gemini를 묶습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(loadAccountRoutes()) { route in
                    AccountRouteCard(route: route, accounts: snap.accounts, connections: connections)
                }
            }
        }
    }

    private var accountsSection: some View {
        DooyouPanel("계정별 사용량") {
            if snap.accounts.isEmpty {
                HStack {
                    Image(systemName: "link.badge.plus").foregroundStyle(.secondary)
                    Text("연결된 로컬 사용량 데이터가 없습니다.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                ForEach(snap.accounts) { a in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.name).font(.callout).bold()
                            if let e = a.email { Text(e).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("오늘 \(eok(a.today)) · \(usd(a.todayCost))").font(.caption)
                            Text("7일 \(eok(a.week)) · \(usd(a.weekCost))").font(.caption2).foregroundStyle(.secondary)
                            if let h = hudText(a) { h.font(.caption2) }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var dailySection: some View {
        let days = agg.byDay.keys.sorted().suffix(30)
        let maxTok = max(1, days.map { agg.byDay[$0]!.total }.max() ?? 1)
        return DooyouPanel {
            HStack { Text("일별 · 최근 30일").font(.headline); Spacer()
                Label("Claude", systemImage: "circle.fill").font(.caption2).foregroundStyle(claudeColor)
                Label("Codex", systemImage: "circle.fill").font(.caption2).foregroundStyle(codexColor)
                Label("GLM", systemImage: "circle.fill").font(.caption2).foregroundStyle(glmColor) }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(days), id: \.self) { d in
                    let v = agg.byDay[d]!
                    let h = 90.0
                    VStack(spacing: 0) {
                        Rectangle().fill(glmColor).frame(height: h * Double(v.glm) / Double(maxTok))
                        Rectangle().fill(codexColor).frame(height: h * Double(v.codex) / Double(maxTok))
                        Rectangle().fill(claudeColor).frame(height: h * Double(v.claude) / Double(maxTok))
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(String(d.suffix(5)))  \(eok(v.total))  \(usd(v.cost))")
                }
            }
            .frame(height: 90)
        }
    }

    private func breakdown(_ title: String, _ data: [String: TokCost]) -> some View {
        let rows = data.sorted { $0.value.tokens > $1.value.tokens }.prefix(8)
        let total = max(1, data.values.reduce(0) { $0 + $1.tokens })
        return DooyouPanel(title) {
            ForEach(Array(rows), id: \.key) { k, v in
                let frac = Double(v.tokens) / Double(total)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(k).font(.caption).lineLimit(1)
                        Spacer()
                        Text(eok(v.tokens)).font(.caption2).foregroundStyle(.secondary)
                        Text(usd(v.cost)).font(.caption2).bold()
                        Text("\(Int((frac * 100).rounded()))%").font(.caption2).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule().fill(claudeColor).frame(width: max(2, g.size.width * frac))
                        }
                    }.frame(height: 5)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var limitsSection: some View {
        DooyouPanel("한도") {
            ForEach(snap.accounts.filter { $0.fiveHourPct != nil || $0.weeklyPct != nil }) { a in
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.name).font(.callout).bold()
                    limitBar("5h", a.fiveHourPct, a.fiveHourResetsAt)
                    limitBar("주간", a.weeklyPct, a.weeklyResetsAt)
                }.padding(.vertical, 2)
            }
        }
    }
    @ViewBuilder private func limitBar(_ label: String, _ pct: Int?, _ reset: Date?) -> some View {
        if let p = pct {
            HStack(spacing: 8) {
                Text(label).font(.caption2).frame(width: 32, alignment: .leading)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(usedColor(p)).frame(width: max(2, g.size.width * Double(p) / 100))
                    }
                }.frame(height: 6)
                Text("\(p)%").font(.caption2).foregroundStyle(usedColor(p)).frame(width: 36, alignment: .trailing)
                Text(reset.map { "리셋 \(countdown($0))" } ?? "-").font(.caption2).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
            }
        }
    }
}

struct AccountRouteCard: View {
    let route: AccountRouteProfile
    let accounts: [Account]
    @ObservedObject var connections: ConnectionModel

    var body: some View {
        let routeAccounts = route.providers.compactMap { account(for: $0) }
        let today = routeAccounts.reduce(0) { $0 + $1.today }
        let week = routeAccounts.reduce(0) { $0 + $1.week }
        let todayCost = routeAccounts.reduce(0) { $0 + $1.todayCost }

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.title)
                        .font(.headline)
                    Text(route.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(eok(today))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("\(eok(week)) 7일 · \(usd(todayCost))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            VStack(spacing: 7) {
                ForEach(route.providers) { provider in
                    providerRow(provider)
                }
            }

            Text(route.note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 166, alignment: .topLeading)
        .padding(12)
        .background(routeTint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(routeTint.opacity(0.18), lineWidth: 1))
    }

    private var routeTint: Color {
        switch route.id {
        case "piolabs": return DooyouStyle.accent
        case "nudgespace": return DooyouStyle.info
        case "neulketing": return glmColor
        default: return .secondary
        }
    }

    private func account(for provider: AccountRouteProvider) -> Account? {
        accounts.first { $0.name == provider.accountName }
    }

    private func displayEmail(_ account: Account?, fallback: String) -> String {
        let value = account?.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }

    private func providerRow(_ provider: AccountRouteProvider) -> some View {
        let matched = account(for: provider)
        let installed = cliInstalled(provider.cliCommand)
        let tint = providerColor(provider.provider)
        return HStack(spacing: 8) {
            Image(systemName: provider.symbol)
                .font(.caption)
                .frame(width: 16)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(provider.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(provider.accountName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(displayEmail(matched, fallback: provider.email))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let matched {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(eok(matched.today))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text(matched.week > 0 ? "추적 중" : "대기")
                        .font(.caption2)
                        .foregroundStyle(matched.week > 0 ? DooyouStyle.success : .secondary)
                }
            } else {
                Text(installed ? "로그인 가능" : "설치 전")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(installed ? DooyouStyle.success : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background((installed ? DooyouStyle.success : Color.secondary).opacity(0.12), in: Capsule())
            }
        }
    }

    private func providerColor(_ provider: String) -> Color {
        switch provider {
        case "claude": return claudeColor
        case "codex": return codexColor
        case "glm": return glmColor
        case "gemini": return DooyouStyle.info
        default: return .secondary
        }
    }

    private func cliInstalled(_ command: String) -> Bool {
        guard !command.isEmpty else { return false }
        return connections.discoveredCLIs.contains { $0.command == command && $0.isInstalled }
    }
}
