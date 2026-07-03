import SwiftUI
import AppKit

// ---- 배차 피드 — omf-route가 남기는 ~/.dooyou/route-log.jsonl의 뷰 ----

struct DispatchEntry: Identifiable {
    let ts: Date
    let task: String?
    let cls: String?
    let worker: String
    let headroom: Int?
    let fallback: Bool
    let waitForResetMin: Int?
    var id: String { "\(ts.timeIntervalSince1970)-\(worker)" }
}

private let dispatchISO: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func loadDispatchLog(limit: Int = 40) -> [DispatchEntry] {
    let path = NSHomeDirectory() + "/.dooyou/route-log.jsonl"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").suffix(limit).compactMap { line in
        guard let d = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let tsStr = o["ts"] as? String, let worker = o["worker"] as? String,
              let ts = dispatchISO.date(from: tsStr) ?? ISO8601DateFormatter().date(from: tsStr)
        else { return nil }
        return DispatchEntry(
            ts: ts,
            task: o["task"] as? String,
            cls: o["class"] as? String,
            worker: worker,
            headroom: (o["headroom"] as? NSNumber)?.intValue,
            fallback: (o["fallback"] as? Bool) ?? false,
            waitForResetMin: (o["waitForResetMin"] as? NSNumber)?.intValue)
    }.reversed()
}

func relTime(_ d: Date) -> String {
    let s = Int(-d.timeIntervalSinceNow)
    if s < 60 { return "방금" }
    if s < 3600 { return "\(s / 60)분 전" }
    if s < 86400 { return "\(s / 3600)시간 전" }
    return "\(s / 86400)일 전"
}

// 팝오버 한 줄 스트립: 최근 배차 결정 요약
struct DispatchStrip: View {
    let entries: [DispatchEntry]
    var openDashboard: () -> Void

    private var todayCount: Int {
        entries.filter { Calendar.current.isDateInToday($0.ts) }.count
    }

    var body: some View {
        Button(action: openDashboard) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(entries.isEmpty ? Color.secondary : DooyouStyle.info)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text("배차").font(.caption).fontWeight(.semibold)
                    Text(summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                StatusCapsule(text: entries.isEmpty ? "기록 없음" : "오늘 \(todayCount)건",
                              color: entries.isEmpty ? .secondary : DooyouStyle.info)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(DooyouStyle.info.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.07), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("좌석 배차(omf-route) 결정 피드")
    }

    private var summary: String {
        guard let e = entries.first else { return "아직 배차 결정 없음 — omf-route 사용 시 기록" }
        let head = e.headroom.map { " \($0)%" } ?? ""
        let cls = e.cls.map { "\($0) → " } ?? ""
        return "\(cls)\(e.worker)\(head) · \(relTime(e.ts))"
    }
}

// 대시보드 섹션: 최근 배차 결정 목록
struct DispatchSection: View {
    let entries: [DispatchEntry]

    var body: some View {
        DooyouPanel("배차 피드 · 최근") {
            if entries.isEmpty {
                Text("아직 배차 결정이 없습니다. omf-route가 좌석을 고르면 여기에 쌓입니다.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(entries.prefix(10)) { e in
                    HStack(spacing: 8) {
                        Image(systemName: e.fallback ? "arrow.uturn.down" : "checkmark.circle")
                            .foregroundStyle(e.fallback ? DooyouStyle.warning : DooyouStyle.success)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(e.worker).font(.caption).fontWeight(.semibold).monospaced()
                                if let h = e.headroom {
                                    Text("잔량 \(h)%").font(.caption2)
                                        .foregroundStyle(h > 30 ? DooyouStyle.success : DooyouStyle.warning)
                                }
                                if let w = e.waitForResetMin {
                                    Text("리셋 대기 \(w)m").font(.caption2).foregroundStyle(DooyouStyle.warning)
                                }
                                if e.fallback { Text("폴백").font(.caption2).foregroundStyle(DooyouStyle.warning) }
                            }
                            if let t = e.task, !t.isEmpty {
                                Text(t).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(relTime(e.ts)).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// ---- 번레이트 모니터 — 구속(binding) 창 소진 예측 + 90% 임계 알림 ----
// 기준 = "제일 먼저 바닥나는 창" (2026-07-03, 5h 고정 기준 폐지 — wk 97%가 5h 41%보다
// 급한데 5h만 경고하던 문제). 각 창(5h/wk/mo)별 기울기로 소진 ETA를 구하되,
// **리셋이 소진보다 먼저 오는 창은 위기가 아니므로 제외**하고 남은 창 중 가장 이른 것을 보고.

struct BurnEta { let window: String; let minutes: Int }

final class BurnMonitor {
    static let shared = BurnMonitor()
    private var history: [String: [(ts: Date, pct: Int)]] = [:]   // "계정|창" → 관측
    private var notified = Set<String>()
    private let queue = DispatchQueue(label: "dooyou.burn")

    // 매 refresh(30s)마다 호출. 관측 축적 + 임계 알림 + 계정별 구속 창 ETA 반환.
    func record(_ accounts: [Account]) -> [String: BurnEta] {
        queue.sync {
            var etas: [String: BurnEta] = [:]
            let now = Date()
            for a in accounts {
                let windows: [(name: String, pct: Int?, reset: Date?)] = [
                    ("5h", a.fiveHourPct, a.fiveHourResetsAt),
                    ("wk", a.weeklyPct, a.weeklyResetsAt),
                    ("mo", a.monthlyPct, a.monthlyResetsAt)]
                var best: BurnEta? = nil
                for w in windows {
                    guard let pct = w.pct else { continue }
                    let key = "\(a.name)|\(w.name)"
                    var h = history[key] ?? []
                    // 창 리셋(퍼센트 하락) 감지 시 히스토리 초기화 — 리셋 직후 음의 기울기 방지
                    if let last = h.last, pct < last.pct - 5 { h = [] }
                    h.append((now, pct))
                    // 느린 창(wk/mo)은 기울기가 완만해 관측 창을 6h로 넓힘
                    let span: Double = w.name == "5h" ? 3600 : 6 * 3600
                    h.removeAll { $0.ts < now.addingTimeInterval(-span) }
                    history[key] = h

                    if pct >= 90, pct < 100 {
                        let nkey = "\(a.name)-\(w.name)-\(Int(w.reset?.timeIntervalSince1970 ?? 0))"
                        if !notified.contains(nkey) {
                            notified.insert(nkey)
                            notify("\(a.name) \(w.name) 창 \(pct)% — 소진 임박",
                                   body: w.reset.map { "리셋까지 \(countdown($0))" } ?? "")
                        }
                    }

                    // 기울기: ≥10분 간격 관측 2개 이상일 때만
                    guard pct < 100, let first = h.first, h.count >= 2,
                          now.timeIntervalSince(first.ts) >= 600 else { continue }
                    let hours = now.timeIntervalSince(first.ts) / 3600
                    let slope = Double(pct - first.pct) / hours          // %/h
                    guard slope > 0.1 else { continue }                   // 정체 창 제외
                    let etaMin = Int(Double(100 - pct) / slope * 60)      // 분
                    // 리셋이 먼저 오면 이 창은 소진되지 않는다 — 경고 대상 아님
                    if let reset = w.reset, Double(etaMin) * 60 >= reset.timeIntervalSince(now) { continue }
                    guard etaMin <= 48 * 60 else { continue }             // 48h 밖 외삽은 노이즈
                    if best == nil || etaMin < best!.minutes { best = BurnEta(window: w.name, minutes: etaMin) }
                }
                if let b = best { etas[a.name] = b }
            }
            return etas
        }
    }

    // osascript 알림 — 권한 프롬프트·번들 의존 없음 (비번들 debug 실행에서도 동작)
    private func notify(_ title: String, body: String) {
        let esc = { (s: String) in s.replacingOccurrences(of: "\"", with: "\\\"") }
        let p = Process()
        p.launchPath = "/usr/bin/osascript"
        p.arguments = ["-e", "display notification \"\(esc(body))\" with title \"dooyou\" subtitle \"\(esc(title))\""]
        try? p.run()
    }
}

// ---- ROI 패널 — 구독료 대비 API 환산 배수 ----

struct ROIPanel: View {
    @ObservedObject var preferences: PreferencesModel
    let cost30: Double
    @State private var draft = ""

    private var monthly: Double { preferences.monthlySubscriptionUSD ?? 0 }

    var body: some View {
        DooyouPanel("구독 ROI · 30일") {
            HStack(spacing: 14) {
                if monthly > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("×\(String(format: "%.0f", cost30 / monthly))")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(DooyouStyle.success)
                        Text("API 환산 \(usd(cost30)) ÷ 구독료 \(usd(monthly))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("월 구독료를 입력하면 구독 대비 몇 배를 뽑아냈는지 보여줍니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("월 구독료 $").font(.caption).foregroundStyle(.secondary)
                    TextField("400", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .onSubmit { save() }
                    Button("저장") { save() }.controlSize(.small)
                }
            }
        }
        .onAppear { if monthly > 0 { draft = String(format: "%.0f", monthly) } }
    }

    private func save() {
        if let v = Double(draft.trimmingCharacters(in: .whitespaces)), v > 0 {
            preferences.setMonthlySubscription(v)
        }
    }
}
