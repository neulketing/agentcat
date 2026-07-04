import SwiftUI

final class DashModel: ObservableObject {
    @Published var dash = Dashboard()
    @Published var sys = SysStats()
    @Published var launchAgent = LaunchAgentStatus()
    @Published var loading = true
    @Published var requestedRoute: DashboardRoute?
    @Published var dispatch: [DispatchEntry] = []
    func refresh() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let d = scan(daysWindow: 1095)   // all-time (within ~3y cache)
            let disp = loadDispatchLog()
            DispatchQueue.main.async { self?.dash = d; self?.dispatch = disp; self?.loading = false }
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
    case home, router, connectors, analytics, accounts, mascot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "홈"
        case .router: return "라우터"
        case .connectors: return "커넥터"
        case .analytics: return "분석"
        case .accounts: return "계정"
        case .mascot: return "마스코트"
        }
    }

    var subtitle: String {
        switch self {
        case .home: return "지금 상태"
        case .router: return "승인·상태"
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
        case .router: return "point.topleft.down.curvedto.point.bottomright.up"
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
    @ObservedObject var routerStore: RouterDecisionStore
    @AppStorage("dooyou.dashboardRoute") private var route: DashboardRoute = .home   // 마지막 탭 영속(창 재오픈 시 복원)
    var snapshotRoute: DashboardRoute? = nil
    var snapshotMode = false

    private var activeRoute: DashboardRoute { snapshotRoute ?? route }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            Divider()
            if snapshotMode {
                dashboardStack
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    dashboardStack
                        .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(dashboardBackground)
        .frame(minWidth: 860, minHeight: 640)
        .overlay(alignment: .top) {
            if model.loading { Text("불러오는 중…").font(.caption).padding(6)
                .background(.thinMaterial, in: Capsule()).padding(.top, 6) }
        }
        .onAppear {
            guard !snapshotMode else { return }
            if let requested = model.requestedRoute {
                route = requested
                model.requestedRoute = nil
            }
            connections.refresh()
            model.refresh()
            model.refreshSystem()
            model.refreshLaunchAgent()
        }
        .onReceive(model.$requestedRoute) { requested in
            guard !snapshotMode, let requested else { return }
            route = requested
            model.requestedRoute = nil
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if !snapshotMode { model.refreshSystem() }
        }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            if !snapshotMode { model.refreshLaunchAgent() }
        }
    }

    private var dashboardStack: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleBar
            routeContent
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                                .foregroundStyle(activeRoute == item ? DooyouStyle.accent : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.callout)
                                    .fontWeight(activeRoute == item ? .semibold : .medium)
                                Text(item.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(activeRoute == item ? DooyouStyle.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
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
        switch activeRoute {
        case .home:
            heroBand
            OnboardingCard(preferences: preferences, connections: connections)
            summaryGrid
            ROIPanel(preferences: preferences, cost30: w30.cost)
            ConnectionHealthStrip(model: connections)
            RouterStatusStrip(store: routerStore) { route = .router }
            DispatchSection(entries: model.dispatch)
        case .router:
            routeHeader("라우터 / 승인", "PUG Brain Router 결정과 DOOYOU 승인 상태를 봅니다.")
            RouterDashboardSection(store: routerStore)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.callout)
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
                Text("로컬 에이전트 사용량, 커넥터, 시스템 압력을 조용히 정리합니다.")
                    .font(.callout)
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
            Image(nsImage: dooyouImage(1, height: 48, tier: snap.activeAgents > 0 ? .run : .rest, mascot: preferences.mascot, background: preferences.backgroundTheme))
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 56)
                .padding(12)
                .background(DooyouStyle.surfaceElevated.opacity(0.70), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07), lineWidth: 1))
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
                colors: [DooyouStyle.accent.opacity(0.14), DooyouStyle.surfaceElevated.opacity(0.56), DooyouStyle.info.opacity(0.07)],
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
        .background(DooyouStyle.surfaceElevated.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
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
                dashboardEmptyState(
                    systemImage: model.loading ? "clock" : "link.badge.plus",
                    title: model.loading ? "계정 사용량을 불러오는 중" : "계정 사용량 데이터가 없습니다",
                    message: model.loading ? "로컬 Claude, Codex, GLM 기록을 모아 계정별 한도와 리셋 시간을 표시합니다." : "커넥터를 연결하면 오늘, 7일 사용량과 한도 리셋 시간이 여기에 나타납니다."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(snap.accounts) { a in
                        accountUsageRow(a)
                    }
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
            if days.isEmpty {
                dashboardEmptyState(
                    systemImage: model.loading ? "clock" : "chart.bar.xaxis",
                    title: model.loading ? "일별 사용량을 불러오는 중" : "최근 30일 사용량이 없습니다",
                    message: model.loading ? "로컬 캐시를 읽어 토큰과 비용 흐름을 계산합니다." : "사용 기록이 쌓이면 Claude, Codex, GLM 막대가 여기에 나타납니다."
                )
            } else {
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
    }

    private func breakdown(_ title: String, _ data: [String: TokCost]) -> some View {
        let rows = data.sorted { $0.value.tokens > $1.value.tokens }.prefix(8)
        let total = max(1, data.values.reduce(0) { $0 + $1.tokens })
        return DooyouPanel(title) {
            if rows.isEmpty {
                dashboardEmptyState(
                    systemImage: model.loading ? "clock" : "chart.pie",
                    title: model.loading ? "분포를 계산하는 중" : "\(title) 데이터가 없습니다",
                    message: model.loading ? "최근 사용 기록을 모델과 프로젝트로 묶고 있습니다." : "사용 기록이 쌓이면 상위 항목과 비율이 여기에 표시됩니다."
                )
            } else {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var limitsSection: some View {
        DooyouPanel("한도") {
            let limitedAccounts = snap.accounts.filter { hasTrackedLimit($0) }
            if limitedAccounts.isEmpty {
                dashboardEmptyState(
                    systemImage: model.loading ? "clock" : "gauge.with.dots.needle.bottom.50percent",
                    title: model.loading ? "한도 정보를 확인하는 중" : "표시할 한도가 없습니다",
                    message: model.loading ? "한도 퍼센트와 다음 리셋 시간을 함께 불러옵니다." : "계정에서 5시간, 주간, Fable 주간 한도를 찾으면 리셋 시각까지 같이 표시합니다."
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(limitedAccounts) { a in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(a.name)
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                Spacer()
                                if let email = a.email {
                                    Text(email)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            limitBar("5시간", a.fiveHourPct, a.fiveHourResetsAt)
                            limitBar("주간", a.weeklyPct, a.weeklyResetsAt)
                            limitBar("Fable 주간", a.fablePct, a.fableResetsAt)   // 클로드 Fable 주간 (claude.ai 대응, 클로드만 렌더)
                            limitBar("월간", a.monthlyPct, a.monthlyResetsAt)
                        }
                        .padding(10)
                        .background(DooyouStyle.surfaceElevated.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    }
                }
            }
        }
    }

    private func accountUsageRow(_ account: Account) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.callout)
                    .fontWeight(.semibold)
                if let email = account.email {
                    Text(email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let note = account.limitNote, !hasTrackedLimit(account) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("오늘 \(eok(account.today)) · \(usd(account.todayCost))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text("7일 \(eok(account.week)) · \(usd(account.weekCost))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if hasTrackedLimit(account) {
                    Text(limitSummary(account))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .background(DooyouStyle.surfaceElevated.opacity(0.52), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.05), lineWidth: 1))
    }

    private func hasTrackedLimit(_ account: Account) -> Bool {
        account.fiveHourPct != nil || account.weeklyPct != nil || account.fablePct != nil || account.monthlyPct != nil
    }

    private func limitSummary(_ account: Account) -> String {
        [
            limitSummaryPart("5시간", account.fiveHourPct, account.fiveHourResetsAt),
            limitSummaryPart("주간", account.weeklyPct, account.weeklyResetsAt),
            limitSummaryPart("Fable 주간", account.fablePct, account.fableResetsAt),
            limitSummaryPart("월간", account.monthlyPct, account.monthlyResetsAt),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func limitSummaryPart(_ label: String, _ pct: Int?, _ reset: Date?) -> String? {
        guard let pct else { return nil }
        return "\(label) \(pct)% · \(resetDescription(reset))"
    }

    private func resetDescription(_ reset: Date?) -> String {
        guard let reset else { return "리셋 시간 없음" }
        return "리셋 \(countdown(reset))"
    }

    private func dashboardEmptyState(systemImage: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(DooyouStyle.surfaceSecondary.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func limitBar(_ label: String, _ pct: Int?, _ reset: Date?) -> some View {
        if let p = pct {
            HStack(spacing: 8) {
                Text(label).font(.caption2).frame(width: 62, alignment: .leading)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(usedColor(p)).frame(width: max(2, g.size.width * Double(p) / 100))
                    }
                }.frame(height: 6)
                Text("\(p)%").font(.caption2).fontWeight(.semibold).foregroundStyle(usedColor(p)).frame(width: 36, alignment: .trailing)
                Text(resetDescription(reset)).font(.caption2).foregroundStyle(.secondary).frame(width: 96, alignment: .trailing)
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
        .background(DooyouStyle.surfaceElevated.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
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
