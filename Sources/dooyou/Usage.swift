import Foundation

struct Account: Identifiable {
    enum Kind { case claude, codex, glm }
    let id = UUID()
    let name: String
    let kind: Kind
    var today = 0
    var week = 0
    var todayCost = 0.0              // API-equivalent USD (per-model pricing)
    var weekCost = 0.0
    // OMC-style HUD limits (USED %). Claude: from statusline-stdin cache;
    // Codex: primary(300m)=5h, secondary(10080m)=weekly.
    var fiveHourPct: Int? = nil
    var fiveHourResetsAt: Date? = nil
    var weeklyPct: Int? = nil
    var weeklyResetsAt: Date? = nil
    var monthlyPct: Int? = nil       // GLM (Z.ai) only — monthly window
    var monthlyResetsAt: Date? = nil
    var email: String? = nil         // logged-in account (oauth / id_token)
    var limitNote: String? = nil
}

struct Snapshot {
    var accounts: [Account] = []
    var activeAgents = 0
    var today: Int { accounts.reduce(0) { $0 + $1.today } }
    var week: Int { accounts.reduce(0) { $0 + $1.week } }
    var todayCost: Double { accounts.reduce(0) { $0 + $1.todayCost } }
    var weekCost: Double { accounts.reduce(0) { $0 + $1.weekCost } }
}

// ---- dashboard aggregates (richer than the menu-bar Snapshot) ----
struct TokCost { var tokens = 0; var cost = 0.0
    mutating func add(_ t: Int, _ c: Double) { tokens += t; cost += c } }
struct DayTok { var claude = 0; var codex = 0; var glm = 0; var cost = 0.0
    var total: Int { claude + codex + glm } }
struct Aggregates {
    var byModel: [String: TokCost] = [:]
    var byProject: [String: TokCost] = [:]
    var byDay: [String: DayTok] = [:]      // keyed "yyyy-MM-dd" (KST)
    var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
    var cacheHitPct: Int {
        let d = input + cacheRead + cacheWrite
        return d > 0 ? Int((Double(cacheRead) / Double(d) * 100).rounded()) : 0
    }
}
struct Dashboard { var snap = Snapshot(); var agg = Aggregates() }

func projectName(_ cwd: String?) -> String {
    guard let c = cwd, !c.isEmpty else { return "기타" }
    let base = (c as NSString).lastPathComponent
    return base.isEmpty ? "기타" : base
}

func eok(_ n: Int) -> String { String(format: "%.2f억", Double(n) / 1e8) }
func usd(_ d: Double) -> String {
    if d >= 100 { return String(format: "$%.0f", d) }
    if d >= 1 { return String(format: "$%.2f", d) }
    return String(format: "$%.3f", d)
}

// Sum (tokens, cost) over the most recent `lastDays` day-buckets; nil = all-time.
func windowSum(_ byDay: [String: DayTok], lastDays: Int?) -> (tokens: Int, cost: Double) {
    let keys = byDay.keys.sorted()
    let sel = lastDays.map { Array(keys.suffix($0)) } ?? keys
    var t = 0, c = 0.0
    for k in sel { if let d = byDay[k] { t += d.total; c += d.cost } }
    return (t, c)
}

// ---- pricing: USD per 1M tokens, sourced from the trappist pricing cache
// (auto-refreshed) with a builtin fallback so cost never silently zeroes out. ----
struct Price {
    var input = 0.0, output = 0.0, cacheWrite = 0.0, cacheRead = 0.0
    // 롱컨텍스트 티어 (예: gpt-5.5 입력 272k 초과 시 단가 상승). threshold 0 = 티어 없음.
    var tierThreshold = 0
    var tierInput = 0.0, tierOutput = 0.0, tierCacheRead = 0.0
    private func rates(_ promptTok: Int) -> (i: Double, o: Double, r: Double) {
        tierThreshold > 0 && promptTok > tierThreshold
            ? (tierInput, tierOutput, tierCacheRead) : (input, output, cacheRead)
    }
    func claudeCost(in inp: Int, out: Int, cw: Int, cr: Int) -> Double {
        let t = rates(inp + cw + cr)
        return (Double(inp) * t.i + Double(out) * t.o + Double(cw) * cacheWrite + Double(cr) * t.r) / 1e6
    }
    func codexCost(in inp: Int, cached: Int, out: Int) -> Double {
        let t = rates(inp)
        return (Double(max(0, inp - cached)) * t.i + Double(cached) * t.r + Double(out) * t.o) / 1e6
    }
}

private let builtinPrices: [String: Price] = [
    "claude-fable-5": Price(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 1.0),
    "claude-opus-4-8": Price(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5),
    "claude-opus-4-7": Price(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5),
    "claude-opus-4-6": Price(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5),
    "claude-opus-4-5": Price(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5),
    "claude-sonnet-4-6": Price(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3),
    "claude-sonnet-4-5": Price(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3),
    "gpt-5.1-codex": Price(input: 1.25, output: 10, cacheRead: 0.125),
    "gpt-5-codex": Price(input: 1.25, output: 10, cacheRead: 0.125),
    "gpt-5.1": Price(input: 1.25, output: 10, cacheRead: 0.125),
    "gpt-5.3-codex": Price(input: 1.75, output: 14, cacheRead: 0.175),
    "gpt-5.4": Price(input: 2.5, output: 15, cacheRead: 0.25,
                     tierThreshold: 272_000, tierInput: 5, tierOutput: 22.5, tierCacheRead: 0.5),
    "gpt-5.5": Price(input: 5, output: 30, cacheRead: 0.5,
                     tierThreshold: 272_000, tierInput: 10, tierOutput: 45, tierCacheRead: 1.0),
    "glm-5.2": Price(input: 1.4, output: 4.4, cacheRead: 0.26),
]

private let priceTable: [String: Price] = {
    var table = builtinPrices
    let path = firstExistingPath([
        NSHomeDirectory() + "/.dooyou/pricing-cache.json",
        NSHomeDirectory() + "/.agentcat/pricing-cache.json",
    ])
    if let data = FileManager.default.contents(atPath: path),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let models = obj["models"] as? [String: Any] {
        for (k, v) in models {
            guard let m = v as? [String: Any] else { continue }
            func d(_ key: String) -> Double { (m[key] as? NSNumber)?.doubleValue ?? 0 }
            var p = Price(input: d("input"), output: d("output"),
                          cacheWrite: d("cache_write"), cacheRead: d("cache_read"))
            if let t0 = (m["tiers"] as? [[String: Any]])?.first {
                func td(_ key: String) -> Double { (t0[key] as? NSNumber)?.doubleValue ?? 0 }
                p.tierThreshold = (t0["threshold"] as? NSNumber)?.intValue ?? 0
                p.tierInput = td("input"); p.tierOutput = td("output"); p.tierCacheRead = td("cache_read")
            }
            table[k] = p
        }
    }
    return table
}()

func price(_ model: String) -> Price? {
    if model.isEmpty { return nil }
    if let p = priceTable[model] { return p }
    // "claude-opus-4-8[1m]" -> "claude-opus-4-8"
    let base = model.firstIndex(of: "[").map { String(model[..<$0]) } ?? model
    return priceTable[base] ?? priceTable[base.lowercased()]
}

// 소진 ETA 분 표기 — 짧으면 "294분", 길면(≥2h) "8h34m" (wk/mo 창 ETA는 시간 단위가 자연스러움)
func fmtEtaMin(_ m: Int) -> String {
    if m < 120 { return "\(m)분" }
    let days = m / 1440, hours = (m % 1440) / 60, mins = m % 60
    if days > 0 { return "\(days)d\(hours)h" }
    return "\(hours)h\(mins)m"
}

// "4h38m" / "2d21h" / "12m" — OMC-style reset countdown.
func countdown(_ d: Date) -> String {
    let s = Int(d.timeIntervalSinceNow)
    if s <= 0 { return "now" }
    let days = s / 86400, hours = (s % 86400) / 3600, mins = (s % 3600) / 60
    if days > 0 { return "\(days)d\(hours)h" }
    if hours > 0 { return "\(hours)h\(mins)m" }
    return "\(mins)m"
}

// ---- date helpers: KST day from a UTC ISO timestamp (ignore fractional secs) ----
private let dayParse: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX"); return f
}()
private let dayOut: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX"); return f
}()
private let kstShift: TimeInterval = 9 * 3600
private func kstDay(_ utcISO: String) -> String? {
    guard let d = dayParse.date(from: String(utcISO.prefix(19))) else { return nil }
    return dayOut.string(from: d.addingTimeInterval(kstShift))
}
private func kstDay(_ date: Date) -> String { dayOut.string(from: date.addingTimeInterval(kstShift)) }

// daysWindow drives the file mtime cutoff + aggregate floor; account today/week
// are always 7-day. Menu bar uses 8 (fast); dashboard uses ~31 (30-day history).
func scan(daysWindow: Int = 8, includeMini: Bool = true) -> Dashboard {
    let now = Date()
    let today = kstDay(now)
    let sevenAgo = kstDay(now.addingTimeInterval(-7 * 86400))
    let aggFloor = kstDay(now.addingTimeInterval(-Double(daysWindow) * 86400))
    let maxAge = Double(daysWindow + 1) * 86400
    var dash = Dashboard()
    let h = NSHomeDirectory()
    let claude1 = h + "/.claude/projects", claude2 = h + "/.claude-account2/projects"
    let claude3 = h + "/.claude-account3/projects"
    let codex1 = h + "/.codex/sessions", codex2 = h + "/.codex-account2/sessions"

    // aggregates: each transcript file merged exactly once (independent of accounts)
    for (root, isCodex) in [(claude1, false), (claude2, false), (claude3, false), (codex1, true), (codex2, true)] {
        for (path, mtime) in filesIn(root, now, maxAge, rollout: isCodex) {
            aggAdd(fileAggFor(path, mtime, codex: isCodex), aggFloor, &dash.agg)
        }
    }

    // accounts: pick one provider bucket (0=claude 1=codex 2=glm) per dir.
    // GLM shares Claude 1's dir (~/.claude) but counts only glm-* models → split out.
    let specs: [(String, Account.Kind, String, Int, Bool)] = [
        ("Claude 1", .claude, claude1, 0, false),
        ("Claude 2", .claude, claude2, 0, false),
        ("Claude 3", .claude, claude3, 0, false),
        ("Codex 1",  .codex,  codex1,  1, true),
        ("Codex 2",  .codex,  codex2,  1, true),
        ("GLM",      .glm,    claude1, 2, false),
    ]
    for (name, kind, root, bucket, isCodex) in specs {
        var a = Account(name: name, kind: kind)
        let cfg = (root as NSString).deletingLastPathComponent
        switch kind {
        case .claude: loadClaudeLimits(cfg, &a); a.email = claudeEmail(cfg)
        case .codex:  a.email = codexEmail(cfg)
        case .glm:    a.email = nil
        }
        var best = 0.0
        for (path, mtime) in filesIn(root, now, maxAge, rollout: isCodex) {
            let fa = fileAggFor(path, mtime, codex: isCodex)
            accountAdd(fa, bucket, today, sevenAgo, &a)
            if kind == .codex, fa.rlTime > best {
                best = fa.rlTime
                if let p = fa.fhPct { a.fiveHourPct = p }
                if let r = fa.fhReset { a.fiveHourResetsAt = Date(timeIntervalSince1970: r) }
                if let p = fa.wkPct { a.weeklyPct = p }
                if let r = fa.wkReset { a.weeklyResetsAt = Date(timeIntervalSince1970: r) }
            }
        }
        if kind == .codex {
            // Prefer a fresh probe capture over stale session rate_limits; probe when stale.
            if let data = FileManager.default.contents(atPath: dooyouLimitPath(cfg)),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cap = (obj["captured_at"] as? NSNumber)?.doubleValue,
               Date().timeIntervalSince1970 - cap <= 12 * 3600, cap > best,
               let rl = obj["rate_limits"] as? [String: Any] {
                applyRateLimits(rl, &a)
            }
            if (a.fiveHourResetsAt.map { $0 < Date() } ?? true) || (a.weeklyResetsAt.map { $0 < Date() } ?? true) {
                maybeProbeLimits(cfg)
            }
        }
        if kind == .glm {
            // GLM limits come from Z.ai's quota endpoint via the probe helper (no
            // config dir of its own — GLM shares ~/.claude, so it has a fixed file).
            if let data = FileManager.default.contents(atPath: NSHomeDirectory() + "/.dooyou/limits/glm.json"),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cap = (obj["captured_at"] as? NSNumber)?.doubleValue,
               Date().timeIntervalSince1970 - cap <= 12 * 3600,
               let rl = obj["rate_limits"] as? [String: Any] {
                applyRateLimits(rl, &a)
            }
            maybeProbeLimits("glm")
        }
        if kind == .glm, a.week == 0, a.today == 0, a.fiveHourPct == nil { continue }   // hide empty GLM row
        dash.snap.accounts.append(a)
    }
    if includeMini, let mini = loadMiniAccount() { dash.snap.accounts.append(mini) }
    dash.snap.activeAgents = countAgentProcesses()
    persistAggCache()
    return dash
}

func scanAll(includeMini: Bool = true) -> Snapshot { scan(daysWindow: 8, includeMini: includeMini).snap }

// ---- Mac mini sum: read the snapshot Syncthing carries from the mini ----
let defaultMiniEmitPath = firstExistingPath([
    NSHomeDirectory() + "/hermes/_minibrain/dooyou-mini.json",
    NSHomeDirectory() + "/hermes/_minibrain/agentcat-mini.json",
])

// row. Skip if stale (>24h) so a dead mini can't freeze the displayed total.
private func loadMiniAccount() -> Account? {
    let path = ProcessInfo.processInfo.environment["AGENTCAT_MINI"] ?? defaultMiniEmitPath
    guard let data = FileManager.default.contents(atPath: path),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let ts = obj["ts"] as? String,
          let when = ISO8601DateFormatter().date(from: ts),
          Date().timeIntervalSince(when) <= 24 * 3600 else { return nil }
    var a = Account(name: "맥미니", kind: .claude)
    a.today = obj["today"] as? Int ?? 0
    a.week = obj["week"] as? Int ?? 0
    a.todayCost = (obj["todayCost"] as? NSNumber)?.doubleValue ?? 0
    a.weekCost = (obj["weekCost"] as? NSNumber)?.doubleValue ?? 0
    return a
}

func emitSnapshot(to path: String) {
    let s = scanAll(includeMini: false)   // local only — never re-read our own emit
    let dict: [String: Any] = ["ts": ISO8601DateFormatter().string(from: Date()),
                               "today": s.today, "week": s.week,
                               "todayCost": s.todayCost, "weekCost": s.weekCost]
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    if let d = try? JSONSerialization.data(withJSONObject: dict) { try? d.write(to: url) }
    FileHandle.standardError.write(Data("dooyou emit -> \(path) today=\(s.today) week=\(s.week) cost=\(usd(s.todayCost))\n".utf8))
}

// ===== incremental per-file cache: parse each transcript once per mtime =====
// Only within-file message.id dedup is needed (0 cross-file dups verified), so
// per-file aggregates sum cleanly with no global dedup. In-memory only — the
// long-lived GUI warms up once, then 30s refreshes only re-parse changed files.
// ponytail: no disk persistence; add it if cold-launch warm-up proves annoying.
struct FileAgg: Codable {
    var mtime: Double
    var days: [String: [Double]] = [:]      // day -> [claudeTok, codexTok, cost]
    var models: [String: [Double]] = [:]    // model -> [tok, cost]
    var projects: [String: [Double]] = [:]  // proj  -> [tok, cost]
    var io: [Double] = [0, 0, 0, 0]          // input, output, cacheWrite, cacheRead
    var rlTime = 0.0                          // codex: latest rate_limit timestamp seen
    var fhPct: Int? = nil; var fhReset: Double? = nil
    var wkPct: Int? = nil; var wkReset: Double? = nil
}
private let cacheLock = NSLock()
private let aggCachePath = NSHomeDirectory() + "/.dooyou/dooyou-cache-v2.json"
private let legacyAggCachePath = NSHomeDirectory() + "/.agentcat/agentcat-clone-cache-v2.json"
private var cacheDirty = false
// Disk-persisted so cold parsing happens once ever. Keep up to ~3y so all-time
// cost works; old entries auto-drop when the file ages past that.
private var fileCache: [String: FileAgg] = {
    let cachePath = firstExistingPath([aggCachePath, legacyAggCachePath])
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: cachePath)),
          let c = try? JSONDecoder().decode([String: FileAgg].self, from: d) else { return [:] }
    let cutoff = Date().timeIntervalSince1970 - 1100 * 86400
    return c.filter { $0.value.mtime >= cutoff }
}()

func persistAggCache() {
    cacheLock.lock(); let dirty = cacheDirty; let snap = fileCache; cacheDirty = false; cacheLock.unlock()
    guard dirty, let d = try? JSONEncoder().encode(snap) else { return }
    try? FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/.dooyou", withIntermediateDirectories: true)
    try? d.write(to: URL(fileURLWithPath: aggCachePath))
}

// substring field extractors — avoid JSON-parsing multi-KB transcript lines
private func strAfter(_ s: String, _ key: String) -> String? {
    guard let r = s.range(of: key) else { return nil }
    let rest = s[r.upperBound...]
    guard let end = rest.firstIndex(of: "\"") else { return nil }
    return String(rest[..<end])
}
private func intAfter(_ s: Substring, _ key: String) -> Int {
    guard let r = s.range(of: key) else { return 0 }
    var n = 0, seen = false
    for ch in s[r.upperBound...] {
        if let d = ch.wholeNumberValue, ch.isNumber { n = n * 10 + d; seen = true }
        else if seen || ch != " " { break }
    }
    return n
}
private func msgId(_ line: String) -> String? {
    guard let r = line.range(of: "\"id\":\"msg_") else { return nil }
    let rest = line[r.upperBound...]
    guard let end = rest.firstIndex(of: "\"") else { return nil }
    return "msg_" + rest[..<end]
}
// idx: 0=claude 1=codex 2=glm. days[day] = [cTok,xTok,gTok, cCost,xCost,gCost]
private func addDay(_ fa: inout FileAgg, _ day: String, _ idx: Int, _ tok: Int, _ cost: Double) {
    var v = fa.days[day] ?? [0, 0, 0, 0, 0, 0]
    v[idx] += Double(tok); v[idx + 3] += cost; fa.days[day] = v
}
private func addKV(_ d: inout [String: [Double]], _ k: String, _ tok: Int, _ cost: Double) {
    var v = d[k] ?? [0, 0]; v[0] += Double(tok); v[1] += cost; d[k] = v
}

private func parseClaudeFile(_ text: String, _ mtime: Double) -> FileAgg {
    var fa = FileAgg(mtime: mtime)
    var seen = Set<String>()
    text.enumerateLines { line, _ in
        guard line.contains("\"usage\""), let id = msgId(line), seen.insert(id).inserted,
              let ts = strAfter(line, "\"timestamp\":\""), let day = kstDay(ts) else { return }
        let sub = Substring(line)
        let inp = intAfter(sub, "\"input_tokens\":"), outp = intAfter(sub, "\"output_tokens\":")
        let cc = intAfter(sub, "\"cache_creation_input_tokens\":"), cr = intAfter(sub, "\"cache_read_input_tokens\":")
        let t = inp + outp + cc + cr
        let model = strAfter(line, "\"model\":\"") ?? "unknown"
        let cost = price(model)?.claudeCost(in: inp, out: outp, cw: cc, cr: cr) ?? 0
        addDay(&fa, day, model.hasPrefix("glm") ? 2 : 0, t, cost)   // glm-* → its own provider bucket
        addKV(&fa.models, model, t, cost)
        addKV(&fa.projects, projectName(strAfter(line, "\"cwd\":\"")), t, cost)
        fa.io[0] += Double(inp); fa.io[1] += Double(outp); fa.io[2] += Double(cc); fa.io[3] += Double(cr)
    }
    return fa
}

private func parseCodexFile(_ text: String, _ mtime: Double) -> FileAgg {
    var fa = FileAgg(mtime: mtime)
    var model = "", proj = "기타"
    text.enumerateLines { line, _ in
        if model.isEmpty, let m = strAfter(line, "\"model\":\"") { model = m }
        if proj == "기타", let c = strAfter(line, "\"cwd\":\"") { proj = projectName(c) }
        guard line.contains("token_count") else { return }
        if let r = line.range(of: "last_token_usage"), let ts = strAfter(line, "\"timestamp\":\""), let day = kstDay(ts) {
            let tail = line[r.upperBound...]
            let tot = intAfter(tail, "\"total_tokens\":")
            if tot > 0 {
                let inp = intAfter(tail, "\"input_tokens\":"), cached = intAfter(tail, "\"cached_input_tokens\":"), outp = intAfter(tail, "\"output_tokens\":")
                let mdl = model.isEmpty ? "codex" : model
                let cost = price(mdl)?.codexCost(in: inp, cached: cached, out: outp) ?? 0
                addDay(&fa, day, 1, tot, cost)
                addKV(&fa.models, mdl, tot, cost); addKV(&fa.projects, proj, tot, cost)
                fa.io[0] += Double(max(0, inp - cached)); fa.io[1] += Double(outp); fa.io[3] += Double(cached)
            }
        }
        if line.contains("rate_limits"), let d = line.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let p = o["payload"] as? [String: Any], let rl = p["rate_limits"] as? [String: Any],
           let ts = o["timestamp"] as? String, let when = dayParse.date(from: String(ts.prefix(19)))?.timeIntervalSince1970, when > fa.rlTime {
            fa.rlTime = when
            if let prim = rl["primary"] as? [String: Any] {
                fa.fhPct = (prim["used_percent"] as? NSNumber).map { Int($0.doubleValue.rounded()) }
                fa.fhReset = (prim["resets_at"] as? NSNumber)?.doubleValue
            }
            if let s = rl["secondary"] as? [String: Any] {
                fa.wkPct = (s["used_percent"] as? NSNumber).map { Int($0.doubleValue.rounded()) }
                fa.wkReset = (s["resets_at"] as? NSNumber)?.doubleValue
            }
        }
    }
    return fa
}

private func fileAggFor(_ path: String, _ mtime: Double, codex: Bool) -> FileAgg {
    cacheLock.lock(); let cached = fileCache[path]; cacheLock.unlock()
    if let c = cached, c.mtime == mtime { return c }
    guard let data = FileManager.default.contents(atPath: path),
          let text = String(data: data, encoding: .utf8) else { return FileAgg(mtime: mtime) }
    let fa = codex ? parseCodexFile(text, mtime) : parseClaudeFile(text, mtime)
    cacheLock.lock(); fileCache[path] = fa; cacheDirty = true; cacheLock.unlock()
    return fa
}

private func filesIn(_ root: String, _ now: Date, _ maxAge: Double, rollout: Bool) -> [(String, Double)] {
    let fm = FileManager.default; var out: [(String, Double)] = []
    guard let en = fm.enumerator(atPath: root) else { return out }
    for case let rel as String in en {
        guard rel.hasSuffix(".jsonl") else { continue }
        if rollout && !rel.contains("rollout-") { continue }
        let path = (root as NSString).appendingPathComponent(rel)
        guard let m = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
              now.timeIntervalSince(m) <= maxAge else { continue }
        out.append((path, m.timeIntervalSince1970))
    }
    return out
}

// Merge a file's aggregate into the dashboard totals (once per file).
private func aggAdd(_ fa: FileAgg, _ aggFloor: String, _ agg: inout Aggregates) {
    for (day, v) in fa.days where day >= aggFloor {
        var d = agg.byDay[day] ?? DayTok()
        d.claude += Int(v[0]); d.codex += Int(v[1]); d.glm += Int(v[2]); d.cost += v[3] + v[4] + v[5]
        agg.byDay[day] = d
    }
    for (m, v) in fa.models { var t = agg.byModel[m] ?? TokCost(); t.add(Int(v[0]), v[1]); agg.byModel[m] = t }
    for (p, v) in fa.projects { var t = agg.byProject[p] ?? TokCost(); t.add(Int(v[0]), v[1]); agg.byProject[p] = t }
    agg.input += Int(fa.io[0]); agg.output += Int(fa.io[1]); agg.cacheWrite += Int(fa.io[2]); agg.cacheRead += Int(fa.io[3])
}

// Add only one provider bucket's tokens/cost to an account (7-day window).
private func accountAdd(_ fa: FileAgg, _ bucket: Int, _ today: String, _ sevenAgo: String, _ a: inout Account) {
    for (day, v) in fa.days where day >= sevenAgo {
        guard v.count >= 6 else { continue }
        let tok = Int(v[bucket]); let cost = v[bucket + 3]
        a.week += tok; a.weekCost += cost
        if day == today { a.today += tok; a.todayCost += cost }
    }
}

// dooyou's own statusline capture (~/.dooyou/limits/<configDirName>.json),
// written by the statusline wrapper. Independent of OMC internals.
private func dooyouLimitPath(_ configDir: String) -> String {
    NSHomeDirectory() + "/.dooyou/limits/" + (configDir as NSString).lastPathComponent + ".json"
}

// When a Claude account has no fresh statusline capture, ask the probe helper to
// spend one cheap token and refresh its limits (writes the same limits file).
// Gated per account so a scan loop never spawns more than one probe / 5 min; the
// helper itself no-ops safely on an expired/absent token (idle accounts).
private let probeLock = NSLock()
private var lastProbe: [String: Date] = [:]
// Resolve node by absolute path — the launchd-managed app has no interactive
// shell PATH, so `zsh -lc node` can't be relied on. Prefer Homebrew, then nvm.
private func resolveNode() -> String? {
    let fm = FileManager.default
    for c in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        where fm.isExecutableFile(atPath: c) { return c }
    let nvm = NSHomeDirectory() + "/.nvm/versions/node"
    if let vers = try? fm.contentsOfDirectory(atPath: nvm) {
        for v in vers.sorted().reversed() {
            let p = nvm + "/" + v + "/bin/node"
            if fm.isExecutableFile(atPath: p) { return p }
        }
    }
    return nil
}
private func maybeProbeLimits(_ configDir: String) {
    let helper = NSHomeDirectory() + "/.dooyou/bin/probe-limits.mjs"
    let fm = FileManager.default
    guard fm.fileExists(atPath: helper), let node = resolveNode() else { return }
    probeLock.lock()
    if let last = lastProbe[configDir], Date().timeIntervalSince(last) < 300 { probeLock.unlock(); return }
    lastProbe[configDir] = Date()
    probeLock.unlock()
    let p = Process()
    p.executableURL = URL(fileURLWithPath: node)
    p.arguments = [helper, configDir]
    p.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()   // fire-and-forget; result is read on the next scan
}

private func loadClaudeLimits(_ configDir: String, _ a: inout Account) {
    let fm = FileManager.default
    let expectedPrefix = (configDir as NSString).appendingPathComponent("projects") + "/"

    guard let data = fm.contents(atPath: dooyouLimitPath(configDir)),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cap = (obj["captured_at"] as? NSNumber)?.doubleValue,
          Date().timeIntervalSince1970 - cap <= 12 * 3600,
          (obj["transcript_path"] as? String)?.hasPrefix(expectedPrefix) ?? false,
          let rl = obj["rate_limits"] as? [String: Any] else {
        maybeProbeLimits(configDir)
        a.limitNote = "HUD 미확인"
        return
    }
    applyRateLimits(rl, &a)
}

// Parse a {five_hour, seven_day} × {used_percentage, resets_at} dict into an account.
private func applyRateLimits(_ rl: [String: Any], _ a: inout Account) {
    func window(_ key: String) -> (Int, Date?)? {
        guard let w = rl[key] as? [String: Any],
              let used = (w["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
        let reset = (w["resets_at"] as? NSNumber)?.doubleValue
        return (Int(used.rounded()), reset.map { Date(timeIntervalSince1970: $0) })
    }
    if let (p, r) = window("five_hour") { a.fiveHourPct = p; a.fiveHourResetsAt = r }
    if let (p, r) = window("seven_day") { a.weeklyPct = p; a.weeklyResetsAt = r }
    if let (p, r) = window("monthly")   { a.monthlyPct = p; a.monthlyResetsAt = r }
}

// ---- logged-in account email (cached; never changes within a session) ----
private var emailCache: [String: String?] = [:]
private func cachedEmail(_ key: String, _ compute: () -> String?) -> String? {
    cacheLock.lock(); if let e = emailCache[key] { cacheLock.unlock(); return e }; cacheLock.unlock()
    let v = compute()
    cacheLock.lock(); emailCache[key] = v; cacheLock.unlock()
    return v
}
func claudeEmail(_ configDir: String) -> String? {
    cachedEmail("c:" + configDir) {
        for p in [configDir + "/.claude.json", NSHomeDirectory() + "/.claude.json"] {
            if let d = FileManager.default.contents(atPath: p),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let oa = o["oauthAccount"] as? [String: Any],
               let e = oa["emailAddress"] as? String { return e }
        }
        return nil
    }
}
func codexEmail(_ configDir: String) -> String? {
    cachedEmail("x:" + configDir) {
        guard let d = FileManager.default.contents(atPath: configDir + "/auth.json"),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let tok = o["tokens"] as? [String: Any], let jwt = tok["id_token"] as? String else { return nil }
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let pd = Data(base64Encoded: b),
              let claims = try? JSONSerialization.jsonObject(with: pd) as? [String: Any] else { return nil }
        return claims["email"] as? String
    }
}


private func countAgentProcesses() -> Int {
    let p = Process()
    p.launchPath = "/bin/sh"
    p.arguments = ["-c", "pgrep -fl 'claude|codex' | grep -ivE 'dooyou|agentcat|pgrep' | wc -l"]
    let pipe = Pipe(); p.standardOutput = pipe
    try? p.run(); p.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "0"
    return Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
}

private func firstExistingPath(_ paths: [String]) -> String {
    paths.first { FileManager.default.fileExists(atPath: $0) } ?? paths[0]
}

// ponytail: self-check — token math + KST bucketing. asserts at launch (DEBUG).
func _selfCheck() {
    let u: [String: Any] = ["input_tokens": 10, "output_tokens": 5,
                            "cache_creation_input_tokens": 2, "cache_read_input_tokens": 3]
    let t = (u["input_tokens"] as? Int ?? 0) + (u["output_tokens"] as? Int ?? 0)
        + (u["cache_creation_input_tokens"] as? Int ?? 0) + (u["cache_read_input_tokens"] as? Int ?? 0)
    assert(t == 20, "token sum broken")
    assert(kstDay("2026-06-29T13:04:14.045Z") == "2026-06-29", "KST 13:04Z -> 22:04 KST same day")
    assert(kstDay("2026-06-29T16:00:00Z") == "2026-06-30", "KST 16:00Z -> 01:00 KST next day")
    // pricing loaded + cost math: 1M opus output tokens = $25
    if let p = price("claude-opus-4-8") { assert(abs(1_000_000 * p.output / 1e6 - 25) < 1e-6, "opus price wrong") }
    else { assertionFailure("pricing table empty") }
    assert(price("claude-opus-4-8[1m]") != nil, "model suffix normalization broken")
    // fable-5 단가($10/$50, opus의 2배) + gpt-5.5 롱컨텍스트 티어(272k 초과 시 output $30→$45)
    if let f = price("claude-fable-5") { assert(abs(f.output - 50) < 1e-6, "fable price wrong") }
    else { assertionFailure("fable-5 missing from pricing") }
    if let g = price("gpt-5.5"), g.tierThreshold > 0 {
        let base = g.codexCost(in: 100_000, cached: 0, out: 1_000)
        let tier = g.codexCost(in: 300_000, cached: 0, out: 1_000)
        assert(tier > base * 1.5, "gpt-5.5 long-context tier not applied")
    }
}
