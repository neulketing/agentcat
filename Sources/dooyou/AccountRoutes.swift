import AppKit
import Foundation

struct AccountRouteProvider: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var provider: String
    var accountName: String
    var email: String
    var cliCommand: String
    var apiEnvName: String
    var symbol: String
}

struct AccountRouteProfile: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var providers: [AccountRouteProvider]
    var note: String
}

let defaultAccountRoutes: [AccountRouteProfile] = [
    AccountRouteProfile(
        id: "piolabs",
        title: "Piolabs",
        subtitle: "피오랩스 운영 계정",
        providers: [
            AccountRouteProvider(
                id: "piolabs-claude",
                title: "Claude",
                provider: "claude",
                accountName: "Claude 1",
                email: "inc.polabs@gmail.com",
                cliCommand: "claude",
                apiEnvName: "ANTHROPIC_API_KEY",
                symbol: "sparkles"
            ),
            AccountRouteProvider(
                id: "piolabs-codex",
                title: "Codex",
                provider: "codex",
                accountName: "Codex 1",
                email: "inc.polabs@gmail.com",
                cliCommand: "codex",
                apiEnvName: "OPENAI_API_KEY",
                symbol: "terminal"
            ),
        ],
        note: "기본 로컬 경로: ~/.claude, ~/.codex"
    ),
    AccountRouteProfile(
        id: "nudgespace",
        title: "NudgeSpace",
        subtitle: "넛지스페이스 운영 계정",
        providers: [
            AccountRouteProvider(
                id: "nudgespace-claude",
                title: "Claude",
                provider: "claude",
                accountName: "Claude 2",
                email: "ceo@nudge-space.com",
                cliCommand: "claude",
                apiEnvName: "ANTHROPIC_API_KEY",
                symbol: "sparkles"
            ),
            AccountRouteProvider(
                id: "nudgespace-codex",
                title: "Codex",
                provider: "codex",
                accountName: "Codex 2",
                email: "ceo@nudge-space.com",
                cliCommand: "codex",
                apiEnvName: "OPENAI_API_KEY",
                symbol: "terminal"
            ),
        ],
        note: "기본 로컬 경로: ~/.claude-account2, ~/.codex-account2"
    ),
    AccountRouteProfile(
        id: "neulketing",
        title: "Neulketing",
        subtitle: "늘케팅 모델/검색 계정",
        providers: [
            AccountRouteProvider(
                id: "neulketing-glm",
                title: "GLM",
                provider: "glm",
                accountName: "GLM",
                email: "ZAI_API_KEY",
                cliCommand: "glm",
                apiEnvName: "ZAI_API_KEY",
                symbol: "bolt.horizontal"
            ),
            AccountRouteProvider(
                id: "neulketing-gemini",
                title: "Gemini",
                provider: "gemini",
                accountName: "Gemini",
                email: "neulketing",
                cliCommand: "gemini",
                apiEnvName: "GEMINI_API_KEY",
                symbol: "diamond.fill"
            ),
        ],
        note: "Gemini는 CLI 자동 발견과 로그인 라우트만 표시합니다."
    ),
]

func accountRoutesFileURL() -> URL {
    appSupportDirectoryURL().appendingPathComponent("account-routes.json")
}

func loadAccountRoutes() -> [AccountRouteProfile] {
    let url = accountRoutesFileURL()
    guard let data = try? Data(contentsOf: url),
          let routes = try? JSONDecoder().decode([AccountRouteProfile].self, from: data),
          !routes.isEmpty else {
        return defaultAccountRoutes
    }
    return routes
}

func ensureAccountRoutesFile() {
    let url = accountRoutesFileURL()
    guard !FileManager.default.fileExists(atPath: url.path) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(defaultAccountRoutes) {
        try? data.write(to: url)
    }
}

func openAccountRoutesFile() {
    ensureAccountRoutesFile()
    NSWorkspace.shared.activateFileViewerSelecting([accountRoutesFileURL()])
}
