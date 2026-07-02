import AppKit
import Foundation
import Security
import SwiftUI

enum ConnectorKind: String, CaseIterable, Identifiable, Codable {
    case cli = "CLI"
    case api = "API"
    case mcp = "MCP"

    var id: String { rawValue }
}

struct ConnectorDefinition: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var symbol: String
    var cliCommand: String
    var loginCommand: String
    var apiEnvName: String
    var apiConsoleURL: String
    var mcpCommand: String
    var mcpURL: String
    var dataRoots: [String]
    var dataNeedle: String
    var enabled: Bool
    var isBuiltin = false

    var hasCLI: Bool { !cliCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasAPI: Bool { !apiEnvName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasMCP: Bool {
        !mcpCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !mcpURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case id, title, symbol, cliCommand, loginCommand, apiEnvName, apiConsoleURL
        case mcpCommand, mcpURL, dataRoots, dataNeedle, enabled
    }
}

struct ConnectorDraft {
    var kind: ConnectorKind = .cli
    var title = ""
    var command = ""
    var loginCommand = ""
    var apiEnvName = ""
    var apiConsoleURL = ""
    var dataRoot = ""
}

struct ConnectorStatus: Identifiable {
    let connector: ConnectorDefinition
    let cliPath: String?
    let mcpAvailable: Bool
    let hasLocalData: Bool
    let email: String?
    let hasAPIKey: Bool

    var id: String { connector.id }
    var isCustom: Bool { !connector.isBuiltin }
    var isReady: Bool { email != nil || hasAPIKey || hasLocalData || cliPath != nil || mcpAvailable }
    var cliLabel: String { connector.hasCLI ? (cliPath == nil ? "CLI 없음" : "CLI") : "CLI -" }
    var apiLabel: String { connector.hasAPI ? (hasAPIKey ? "API" : "API 없음") : "API -" }
    var mcpLabel: String {
        guard connector.hasMCP else { return "MCP -" }
        return mcpAvailable ? "MCP" : "MCP 확인"
    }
    var dataLabel: String { hasLocalData ? "데이터" : "데이터 없음" }
    var subtitle: String {
        email ?? connector.apiEnvName.nonEmpty ?? connector.cliCommand.nonEmpty ?? connector.mcpCommand.nonEmpty ?? connector.mcpURL.nonEmpty ?? "커스텀 커넥터"
    }
}

struct CLIProbe: Identifiable, Hashable {
    let title: String
    let command: String
    let loginCommand: String
    let symbol: String
    let path: String?

    var id: String { command }
    var isInstalled: Bool { path != nil }
}

final class ConnectionModel: ObservableObject {
    @Published private(set) var connectors: [ConnectorDefinition] = []
    @Published private(set) var statuses: [ConnectorStatus] = []
    @Published private(set) var discoveredCLIs: [CLIProbe] = []
    @Published var lastAction = ""

    init() {
        connectors = Self.loadConnectors()
        refresh()
    }

    var readyCount: Int { statuses.filter(\.isReady).count }
    var cliCount: Int { statuses.filter { $0.cliPath != nil }.count }
    var apiCount: Int { statuses.filter(\.hasAPIKey).count }
    var mcpCount: Int { statuses.filter(\.mcpAvailable).count }
    var dataCount: Int { statuses.filter(\.hasLocalData).count }
    var customCount: Int { connectors.filter { !$0.isBuiltin }.count }
    var installedDiscoveryCount: Int { discoveredCLIs.filter(\.isInstalled).count }

    func refresh() {
        statuses = connectors.filter(\.enabled).map { connector in
            ConnectorStatus(
                connector: connector,
                cliPath: connector.hasCLI ? commandPath(connector.cliCommand) : nil,
                mcpAvailable: mcpAvailable(connector),
                hasLocalData: connectorHasLocalData(connector),
                email: primaryEmail(connector),
                hasAPIKey: connector.hasAPI && hasStoredAPIKey(for: connector)
            )
        }
        discoveredCLIs = cliCatalog.map { probe in
            CLIProbe(title: probe.title, command: probe.command, loginCommand: probe.loginCommand,
                     symbol: probe.symbol, path: commandPath(probe.command))
        }
    }

    func addConnector(from draft: ConnectorDraft) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let id = uniqueConnectorID(title)
        let command = draft.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let login = draft.loginCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let envName = draft.apiEnvName.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiURL = draft.apiConsoleURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let dataRoot = draft.dataRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let connector = ConnectorDefinition(
            id: id,
            title: title,
            symbol: symbol(for: draft.kind),
            cliCommand: draft.kind == .cli ? command : "",
            loginCommand: draft.kind == .cli ? (login.nonEmpty ?? "\(command) login") : "",
            apiEnvName: draft.kind == .api ? envName : "",
            apiConsoleURL: draft.kind == .api ? apiURL : "",
            mcpCommand: draft.kind == .mcp ? command : "",
            mcpURL: draft.kind == .mcp ? apiURL : "",
            dataRoots: dataRoot.isEmpty ? [] : [dataRoot],
            dataNeedle: "",
            enabled: true,
            isBuiltin: false
        )
        connectors.append(connector)
        saveCustomConnectors()
        lastAction = "\(title) 커넥터 추가됨"
        refresh()
    }

    func addDiscoveredCLI(_ probe: CLIProbe) {
        guard probe.isInstalled, !connectors.contains(where: { $0.cliCommand == probe.command }) else { return }
        let connector = ConnectorDefinition(
            id: uniqueConnectorID(probe.title),
            title: probe.title,
            symbol: probe.symbol,
            cliCommand: probe.command,
            loginCommand: probe.loginCommand,
            apiEnvName: "",
            apiConsoleURL: "",
            mcpCommand: "",
            mcpURL: "",
            dataRoots: [],
            dataNeedle: "",
            enabled: true,
            isBuiltin: false
        )
        connectors.append(connector)
        saveCustomConnectors()
        lastAction = "\(probe.title) CLI 추가됨"
        refresh()
    }

    func openCLIProbeLogin(_ probe: CLIProbe) {
        guard probe.isInstalled else { return }
        openTerminal(command: probe.loginCommand.nonEmpty ?? probe.command)
        lastAction = "\(probe.title) CLI 로그인을 열었습니다."
    }

    func removeConnector(_ connector: ConnectorDefinition) {
        guard !connector.isBuiltin else { return }
        connectors.removeAll { $0.id == connector.id }
        deleteStoredAPIKey(for: connector)
        saveCustomConnectors()
        lastAction = "\(connector.title) 커넥터 삭제됨"
        refresh()
    }

    func openCLILogin(_ connector: ConnectorDefinition) {
        let command = connector.loginCommand.nonEmpty ?? "\(connector.cliCommand) login"
        openTerminal(command: command)
        lastAction = "\(connector.title) CLI 터미널을 열었습니다."
    }

    func openAPIConsole(_ connector: ConnectorDefinition) {
        guard let url = URL(string: connector.apiConsoleURL.nonEmpty ?? "") else { return }
        NSWorkspace.shared.open(url)
        lastAction = "\(connector.title) API 페이지를 열었습니다."
    }

    func openMCP(_ connector: ConnectorDefinition) {
        if let url = URL(string: connector.mcpURL.nonEmpty ?? "") {
            NSWorkspace.shared.open(url)
            lastAction = "\(connector.title) MCP URL을 열었습니다."
            return
        }
        if let command = connector.mcpCommand.nonEmpty {
            openTerminal(command: command)
            lastAction = "\(connector.title) MCP 명령을 열었습니다."
        }
    }

    func openConnectorFolder() {
        NSWorkspace.shared.open(connectorsDirectoryURL())
    }

    func saveAPIKey(_ raw: String, for connector: ConnectorDefinition) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard connector.hasAPI, !key.isEmpty else { return }
        if saveStoredAPIKey(key, for: connector) {
            lastAction = "\(connector.apiEnvName) 저장됨"
            refresh()
        } else {
            lastAction = "API 키 저장 실패"
        }
    }

    func deleteAPIKey(for connector: ConnectorDefinition) {
        deleteStoredAPIKey(for: connector)
        lastAction = "\(connector.apiEnvName) 삭제됨"
        refresh()
    }

    private func uniqueConnectorID(_ title: String) -> String {
        let base = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let clean = base.isEmpty ? "connector" : base
        var candidate = clean
        var idx = 2
        let existing = Set(connectors.map(\.id))
        while existing.contains(candidate) {
            candidate = "\(clean)-\(idx)"
            idx += 1
        }
        return candidate
    }

    private func saveCustomConnectors() {
        let custom = connectors.filter { !$0.isBuiltin }
        let url = connectorsFileURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder.pretty.encode(custom) {
            try? data.write(to: url)
        }
    }

    private static func loadConnectors() -> [ConnectorDefinition] {
        let custom: [ConnectorDefinition]
        if let data = try? Data(contentsOf: connectorsFileURL()),
           let decoded = try? JSONDecoder().decode([ConnectorDefinition].self, from: data) {
            custom = decoded.map { c in
                var copy = c
                copy.isBuiltin = false
                return copy
            }
        } else {
            custom = []
        }
        return defaultConnectors + custom
    }
}

private let keychainService = "local.dooyou.api-key"

private let defaultConnectors: [ConnectorDefinition] = {
    let h = NSHomeDirectory()
    return [
        ConnectorDefinition(
            id: "claude",
            title: "Claude",
            symbol: "sparkles",
            cliCommand: "claude",
            loginCommand: "claude login",
            apiEnvName: "ANTHROPIC_API_KEY",
            apiConsoleURL: "https://console.anthropic.com/settings/keys",
            mcpCommand: "",
            mcpURL: "",
            dataRoots: [h + "/.claude/projects", h + "/.claude-account2/projects", h + "/.claude-account3/projects"],
            dataNeedle: "",
            enabled: true,
            isBuiltin: true
        ),
        ConnectorDefinition(
            id: "codex",
            title: "Codex",
            symbol: "terminal",
            cliCommand: "codex",
            loginCommand: "codex login",
            apiEnvName: "OPENAI_API_KEY",
            apiConsoleURL: "https://platform.openai.com/api-keys",
            mcpCommand: "",
            mcpURL: "",
            dataRoots: [h + "/.codex/sessions", h + "/.codex-account2/sessions"],
            dataNeedle: "",
            enabled: true,
            isBuiltin: true
        ),
        ConnectorDefinition(
            id: "glm",
            title: "GLM",
            symbol: "bolt.horizontal",
            cliCommand: "",
            loginCommand: "",
            apiEnvName: "ZAI_API_KEY",
            apiConsoleURL: "https://docs.z.ai/guides/overview/quick-start",
            mcpCommand: "",
            mcpURL: "",
            dataRoots: [h + "/.claude/projects"],
            dataNeedle: "\"model\":\"glm",
            enabled: true,
            isBuiltin: true
        ),
    ]
}()

func hasStoredAPIKey(for connector: ConnectorDefinition) -> Bool {
    var query = keychainQuery(for: connector)
    query[kSecReturnData as String] = kCFBooleanFalse
    return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
}

private func saveStoredAPIKey(_ key: String, for connector: ConnectorDefinition) -> Bool {
    deleteStoredAPIKey(for: connector)
    var query = keychainQuery(for: connector)
    query[kSecValueData as String] = Data(key.utf8)
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
}

private func deleteStoredAPIKey(for connector: ConnectorDefinition) {
    SecItemDelete(keychainQuery(for: connector) as CFDictionary)
}

private func keychainQuery(for connector: ConnectorDefinition) -> [String: Any] {
    [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccount(for: connector),
    ]
}

private func keychainAccount(for connector: ConnectorDefinition) -> String {
    connector.isBuiltin ? connector.apiEnvName : "\(connector.id):\(connector.apiEnvName)"
}

private func primaryEmail(_ connector: ConnectorDefinition) -> String? {
    let h = NSHomeDirectory()
    switch connector.id {
    case "claude":
        return claudeEmail(h + "/.claude")
    case "codex":
        return codexEmail(h + "/.codex")
    default:
        return nil
    }
}

private func commandPath(_ command: String) -> String? {
    guard let executable = commandExecutable(command) else { return nil }
    let out = shellOutput("command -v \(shellQuote(executable))")
    return out.isEmpty ? nil : out
}

private func commandExecutable(_ command: String) -> String? {
    command.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: " ")
        .first
        .map(String.init)
}

private func shellOutput(_ command: String) -> String {
    let p = Process()
    p.launchPath = "/bin/zsh"
    p.arguments = ["-lc", command]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return "" }
    return (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func openTerminal(command: String) {
    let shellCommand = "/usr/bin/env zsh -lc \(shellQuote(command))"
    let script = """
    tell application "Terminal"
      activate
      do script \(appleScriptString("cd ~; \(shellCommand)"))
    end tell
    """
    let p = Process()
    p.launchPath = "/usr/bin/osascript"
    p.arguments = ["-e", script]
    try? p.run()
}

private func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func appleScriptString(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

private func mcpAvailable(_ connector: ConnectorDefinition) -> Bool {
    if connector.mcpURL.nonEmpty != nil { return true }
    if let command = connector.mcpCommand.nonEmpty { return commandPath(command) != nil }
    return false
}

private func connectorHasLocalData(_ connector: ConnectorDefinition) -> Bool {
    hasAnyJSONL(in: connector.dataRoots, containing: connector.dataNeedle.nonEmpty)
}

private func hasAnyJSONL(in roots: [String], containing needle: String? = nil) -> Bool {
    let fm = FileManager.default
    var scanned = 0
    for root in roots {
        guard let en = fm.enumerator(atPath: root) else { continue }
        for case let rel as String in en where rel.hasSuffix(".jsonl") {
            scanned += 1
            let path = (root as NSString).appendingPathComponent(rel)
            if let needle {
                if let text = try? String(contentsOfFile: path, encoding: .utf8), text.contains(needle) {
                    return true
                }
            } else {
                return true
            }
            if scanned >= 200 { return false }
        }
    }
    return false
}

private func symbol(for kind: ConnectorKind) -> String {
    switch kind {
    case .cli: return "terminal"
    case .api: return "key"
    case .mcp: return "point.3.connected.trianglepath.dotted"
    }
}

private let cliCatalog: [CLIProbe] = [
    CLIProbe(title: "Aider", command: "aider", loginCommand: "aider", symbol: "terminal", path: nil),
    CLIProbe(title: "OpenCode", command: "opencode", loginCommand: "opencode auth login", symbol: "chevron.left.forwardslash.chevron.right", path: nil),
    CLIProbe(title: "Gemini", command: "gemini", loginCommand: "gemini auth", symbol: "diamond.fill", path: nil),
    CLIProbe(title: "Antigravity", command: "antigravity", loginCommand: "antigravity", symbol: "sparkles", path: nil),
    CLIProbe(title: "Claude", command: "claude", loginCommand: "claude login", symbol: "sparkles", path: nil),
    CLIProbe(title: "Codex", command: "codex", loginCommand: "codex login", symbol: "terminal", path: nil),
    CLIProbe(title: "GLM", command: "glm", loginCommand: "glm login", symbol: "bolt.horizontal", path: nil),
    CLIProbe(title: "Qwen Code", command: "qwen", loginCommand: "qwen login", symbol: "circle.hexagongrid.fill", path: nil),
    CLIProbe(title: "Cline", command: "cline", loginCommand: "cline", symbol: "cube.transparent", path: nil),
    CLIProbe(title: "Roo Code", command: "roo", loginCommand: "roo", symbol: "square.stack.3d.up", path: nil),
    CLIProbe(title: "Crush", command: "crush", loginCommand: "crush", symbol: "hammer.fill", path: nil),
]

private func connectorsDirectoryURL() -> URL {
    let url = appSupportDirectoryURL()
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func connectorsFileURL() -> URL {
    connectorsDirectoryURL().appendingPathComponent("connectors.json")
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct CompactConnectionSection: View {
    @ObservedObject var model: ConnectionModel
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("커넥터").font(.headline)
                    HStack(spacing: 6) {
                        Text("\(model.readyCount)/\(model.statuses.count)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(model.readyCount > 0 ? DooyouStyle.success : .secondary)
                        Text("연결").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("연결 상태 새로고침")
            }
            HStack(spacing: 6) {
                StatusCapsule(text: "CLI \(model.cliCount)", color: model.cliCount > 0 ? DooyouStyle.success : .secondary)
                StatusCapsule(text: "MCP \(model.mcpCount)", color: model.mcpCount > 0 ? DooyouStyle.info : .secondary)
                StatusCapsule(text: "API \(model.apiCount)", color: model.apiCount > 0 ? DooyouStyle.success : .secondary)
                StatusCapsule(text: "발견 \(model.installedDiscoveryCount)", color: model.installedDiscoveryCount > 0 ? DooyouStyle.accent : .secondary)
                Spacer(minLength: 0)
            }
            if !model.lastAction.isEmpty {
                Text(model.lastAction).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Button { openDashboard() } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("커넥터 설정")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(12)
        .background(DooyouStyle.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

struct ConnectionHealthStrip: View {
    @ObservedObject var model: ConnectionModel

    var body: some View {
        DooyouPanel("연결 상태") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.readyCount)/\(model.statuses.count)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(model.readyCount > 0 ? DooyouStyle.success : .secondary)
                    Text("사용 가능한 커넥터")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 128, alignment: .leading)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        metric("CLI", model.cliCount, model.cliCount > 0 ? DooyouStyle.success : .secondary, "terminal")
                        metric("MCP", model.mcpCount, model.mcpCount > 0 ? DooyouStyle.info : .secondary, "point.3.connected.trianglepath.dotted")
                        metric("API 키", model.apiCount, model.apiCount > 0 ? DooyouStyle.success : .secondary, "key")
                        metric("로컬 데이터", model.dataCount, model.dataCount > 0 ? DooyouStyle.success : .secondary, "externaldrive")
                        metric("발견 CLI", model.installedDiscoveryCount, model.installedDiscoveryCount > 0 ? DooyouStyle.accent : .secondary, "magnifyingglass")
                    }
                    if !model.lastAction.isEmpty {
                        Text(model.lastAction)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(spacing: 8) {
                    Button("새로고침") { model.refresh() }
                    Button("설정 파일") { model.openConnectorFolder() }
                }
            }
        }
    }

    private func metric(_ label: String, _ value: Int, _ color: Color, _ symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(value)").font(.caption).bold().monospacedDigit().foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.10), in: Capsule())
    }
}

struct ConnectionsDashboardSection: View {
    @ObservedObject var model: ConnectionModel
    @State private var apiInputs: [String: String] = [:]
    @State private var draft = ConnectorDraft()
    @State private var showsAdvancedBuilder = false

    var body: some View {
        DooyouPanel("커넥터") {
            HStack {
                Text("기본 설치판은 없어도 조용히 시작하고, 설치된 CLI만 자동 발견해 로그인 버튼을 켭니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.lastAction.isEmpty {
                    Text(model.lastAction).font(.caption).foregroundStyle(.secondary)
                }
            }
            DiscoveredCLISection(model: model)
            ForEach(model.statuses) { c in
                connectorRow(c)
            }
            DisclosureGroup(isExpanded: $showsAdvancedBuilder) {
                Divider()
                ConnectorBuilderView(model: model, draft: $draft)
                    .padding(.top, 4)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("고급 설정")
                        .font(.callout)
                        .fontWeight(.semibold)
                    Text("자동 발견에 없는 CLI/API/MCP만 직접 추가")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private func connectorRow(_ c: ConnectorStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: c.connector.symbol).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(c.connector.title).font(.callout).bold()
                        if c.isCustom {
                            Text("CUSTOM").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Text(c.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                statusBadge(c.cliLabel, ok: c.cliPath != nil)
                statusBadge(c.apiLabel, ok: c.hasAPIKey)
                if c.connector.hasMCP {
                    statusBadge(c.mcpLabel, ok: c.mcpAvailable)
                }
                statusBadge(c.dataLabel, ok: c.hasLocalData)
            }
            HStack(spacing: 8) {
                if c.connector.hasCLI {
                    Button(c.cliPath == nil ? "CLI 없음" : "CLI 로그인") { model.openCLILogin(c.connector) }
                        .disabled(c.cliPath == nil)
                        .help(c.cliPath == nil ? "이 CLI는 아직 설치되지 않았습니다. 설치 후 새로고침하면 로그인할 수 있습니다." : "\(c.connector.title) CLI 로그인")
                }
                if c.connector.hasAPI {
                    Button("API 콘솔") { model.openAPIConsole(c.connector) }
                        .disabled(c.connector.apiConsoleURL.nonEmpty == nil)
                    SecureField(c.connector.apiEnvName, text: binding(for: c.connector.id))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Button("저장") {
                        model.saveAPIKey(apiInputs[c.connector.id] ?? "", for: c.connector)
                        apiInputs[c.connector.id] = ""
                    }
                    .disabled((apiInputs[c.connector.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if c.hasAPIKey {
                        Button("삭제") { model.deleteAPIKey(for: c.connector) }
                    }
                }
                if c.connector.hasMCP {
                    Button("MCP 열기") { model.openMCP(c.connector) }
                }
                Spacer()
                if c.isCustom {
                    Button("커넥터 삭제") { model.removeConnector(c.connector) }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func binding(for id: String) -> Binding<String> {
        Binding(
            get: { apiInputs[id] ?? "" },
            set: { apiInputs[id] = $0 }
        )
    }

    private func statusBadge(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(ok ? DooyouStyle.success : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background((ok ? DooyouStyle.success : Color.secondary).opacity(0.12))
            .clipShape(Capsule())
    }
}

struct DiscoveredCLISection: View {
    @ObservedObject var model: ConnectionModel

    var body: some View {
        let installed = model.discoveredCLIs.filter(\.isInstalled)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("자동 발견 CLI").font(.headline)
                Spacer()
                Text(installed.isEmpty ? "설치된 후보 없음" : "\(installed.count)개 발견")
                    .font(.caption)
                    .foregroundStyle(installed.isEmpty ? Color.secondary : DooyouStyle.success)
            }
            if installed.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text("Claude, Codex, Aider, OpenCode, Gemini, Antigravity 등이 없어도 기본 설치로 시작합니다. 나중에 설치하면 dooyou가 자동으로 찾아 로그인 버튼을 보여줍니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(installed) { probe in
                        let alreadyTracked = model.connectors.contains { $0.cliCommand == probe.command }
                        HStack(spacing: 8) {
                            Image(systemName: probe.symbol).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(probe.title).font(.caption).bold()
                                Text(probe.command).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 5) {
                                Button("로그인") {
                                    model.openCLIProbeLogin(probe)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Button(alreadyTracked ? "추적 중" : "추가") {
                                    model.addDiscoveredCLI(probe)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(alreadyTracked)
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    }
                }
            }
        }
    }
}

struct ConnectorBuilderView: View {
    @ObservedObject var model: ConnectionModel
    @Binding var draft: ConnectorDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("커스텀 커넥터 추가").font(.headline)
            HStack(spacing: 8) {
                Picker("타입", selection: $draft.kind) {
                    ForEach(ConnectorKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                TextField("이름", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                TextField(primaryPlaceholder, text: $draft.command)
                    .textFieldStyle(.roundedBorder)
                Button("추가") {
                    model.addConnector(from: draft)
                    draft = ConnectorDraft()
                }
                .disabled(!canAdd)
            }
            HStack(spacing: 8) {
                if draft.kind == .cli {
                    TextField("로그인 명령 예: aider login", text: $draft.loginCommand)
                        .textFieldStyle(.roundedBorder)
                }
                if draft.kind == .api {
                    TextField("환경변수 예: PERPLEXITY_API_KEY", text: $draft.apiEnvName)
                        .textFieldStyle(.roundedBorder)
                    TextField("API 콘솔 URL", text: $draft.apiConsoleURL)
                        .textFieldStyle(.roundedBorder)
                }
                if draft.kind == .mcp {
                    TextField("MCP URL 또는 문서 URL", text: $draft.apiConsoleURL)
                        .textFieldStyle(.roundedBorder)
                }
                TextField("로컬 데이터 경로 선택 사항", text: $draft.dataRoot)
                    .textFieldStyle(.roundedBorder)
            }
            Text("API 키 값은 설정 JSON에 저장하지 않고 macOS Keychain에만 저장합니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var primaryPlaceholder: String {
        switch draft.kind {
        case .cli: return "CLI 명령 예: aider"
        case .api: return "API 이름/명령 선택 사항"
        case .mcp: return "MCP 명령 예: npx -y @modelcontextprotocol/server-filesystem"
        }
    }

    private var canAdd: Bool {
        let titleOK = !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch draft.kind {
        case .cli, .mcp:
            return titleOK && !draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .api:
            return titleOK && !draft.apiEnvName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
