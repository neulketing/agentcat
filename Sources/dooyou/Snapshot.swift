import Cocoa
import SwiftUI

// Fable(및 CLI 헤드리스 에이전트)이 두유 UI를 "볼 수 있게" — 팝오버/대시보드 뷰를 PNG로 렌더한다.
// GUI 스크린샷과 달리 실제 창을 띄우지 않고 뷰 트리를 오프스크린 렌더(ImageRenderer, macOS 13+).
// 앱 실행 컨텍스트(applicationDidFinishLaunching) 안에서 호출해야 MainActor·WindowServer가 성립.
// 사용: dooyou snapshot [outDir]  (기본 ~/.dooyou/snapshots). 렌더 후 즉시 종료.
@MainActor
enum SnapshotRenderer {
    static func run(args: [String]) {
        let outDir = args.dropFirst().first { !$0.hasPrefix("-") } ?? (NSHomeDirectory() + "/.dooyou/snapshots")
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        // 모델을 동기 스캔으로 채운다 — 스냅샷은 정적 렌더라 async refresh를 기다리지 않는다.
        let dashModel = DashModel()
        dashModel.dash = scan(daysWindow: 1095)
        dashModel.sys = sampleSys()
        dashModel.launchAgent = sampleLaunchAgent()
        dashModel.dispatch = loadDispatchLog()
        dashModel.loading = false

        let popModel = PopModel()
        popModel.snap = dashModel.dash.snap
        popModel.sys = dashModel.sys
        popModel.launchAgent = dashModel.launchAgent
        popModel.dispatch = dashModel.dispatch
        popModel.powerMode = currentPowerMode()
        popModel.burnEta = BurnMonitor.shared.record(dashModel.dash.snap.accounts)

        let connections = ConnectionModel()
        let preferences = PreferencesModel()
        let routerStore = RouterDecisionStore()

        let popover = DashView(model: popModel, connections: connections, routerStore: routerStore)
        var wrote: [String] = []
        if render(popover, to: outDir + "/popover.png") { wrote.append(outDir + "/popover.png") }

        // 대시보드 각 탭도 렌더 — onAppear refresh 없이 정적 모델을 그대로 캡처한다.
        for route in [DashboardRoute.home, .analytics, .accounts, .connectors] {
            let view = DashboardView(model: dashModel, connections: connections, preferences: preferences, routerStore: routerStore,
                                     snapshotRoute: route, snapshotMode: true)
                .padding(.top, 28)
                .frame(width: 1040, height: 720, alignment: .topLeading)
                .clipped()
            let path = outDir + "/dashboard-\(route.rawValue).png"
            if render(view, to: path) { wrote.append(path) }
        }

        FileHandle.standardError.write(Data("dooyou snapshot -> \(wrote.count) files in \(outDir)\n".utf8))
        for w in wrote { print(w) }
        exit(0)
    }

    static func render<V: View>(_ view: V, to path: String, scale: CGFloat = 2) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: URL(fileURLWithPath: path)); return true } catch { return false }
    }
}
