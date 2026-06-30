import Foundation

struct LaunchAgentStatus {
    var plistExists = false
    var runAtLoad = false
    var keepAlive = false
    var program = ""
    var loaded = false
    var running = false
    var pid: Int?
    var error: String?

    var isPersistent: Bool {
        plistExists && loaded && running && keepAlive
    }

    var title: String {
        if isPersistent { return "상시 실행" }
        if running { return "실행 중" }
        if loaded { return "등록됨" }
        if plistExists { return "미등록" }
        return "수동 실행"
    }

    var detail: String {
        if isPersistent { return "로그인 후 자동 시작 · 종료 시 재실행" }
        if running { return "앱은 켜져 있지만 KeepAlive 상태가 아닙니다" }
        if loaded { return "LaunchAgent는 등록됐지만 프로세스가 멈춰 있습니다" }
        if plistExists { return "plist 파일은 있지만 launchd에 올라가지 않았습니다" }
        if let error { return error }
        return "설치 스크립트로 상시 실행을 켤 수 있습니다"
    }
}

private let dooyouLaunchLabel = "local.dooyou"

func sampleLaunchAgent() -> LaunchAgentStatus {
    var status = LaunchAgentStatus()
    let plistURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(dooyouLaunchLabel).plist")

    status.plistExists = FileManager.default.fileExists(atPath: plistURL.path)
    if status.plistExists {
        do {
            let data = try Data(contentsOf: plistURL)
            if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                status.runAtLoad = plist["RunAtLoad"] as? Bool ?? false
                status.keepAlive = plist["KeepAlive"] as? Bool ?? false
                if let args = plist["ProgramArguments"] as? [String], let first = args.first {
                    status.program = first
                }
            }
        } catch {
            status.error = "LaunchAgent plist를 읽을 수 없습니다"
        }
    }

    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["print", "gui/\(getuid())/\(dooyouLaunchLabel)"]
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            status.loaded = false
            if status.error == nil, !output.isEmpty {
                status.error = "launchd에 아직 등록되지 않았습니다"
            }
            return status
        }
        status.loaded = true
        status.running = output.contains("state = running") || output.contains("job state = running")
        status.keepAlive = status.keepAlive || output.contains("properties = keepalive") || output.contains("properties = keepalive |")
        if status.program.isEmpty, let parsed = parseLaunchLine(output, prefix: "program = ") {
            status.program = parsed
        }
        if let parsedPID = parseLaunchLine(output, prefix: "pid = "), let pid = Int(parsedPID) {
            status.pid = pid
        }
    } catch {
        status.error = "launchctl 상태를 확인할 수 없습니다"
    }

    return status
}

private func parseLaunchLine(_ output: String, prefix: String) -> String? {
    output
        .split(separator: "\n")
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .first { $0.hasPrefix(prefix) }
        .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
}
