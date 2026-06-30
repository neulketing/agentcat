import Foundation

// pmset power-mode toggle — commands cloned verbatim from ~/Desktop/맥미니모드.app
// (NOPASSWD sudoers rule /etc/sudoers.d/macmini-mode makes `sudo -n pmset` work).
let powerModes = ["기본", "피시", "맥미니"]
let powerModeArgs: [String: [String]] = [
    "기본": ["-a disablesleep 0", "-c displaysleep 10 sleep 10", "-b displaysleep 5 sleep 10"],
    "피시": ["-a disablesleep 0", "-c displaysleep 0 sleep 0", "-b displaysleep 5 sleep 10"],
    "맥미니": ["-c displaysleep 0 sleep 0", "-a disablesleep 1"],
]

@discardableResult
private func sh(_ cmd: String) -> (code: Int32, out: String) {
    let p = Process(); p.launchPath = "/bin/sh"; p.arguments = ["-c", cmd]
    let o = Pipe(); p.standardOutput = o; p.standardError = Pipe()
    try? p.run(); p.waitUntilExit()
    let s = String(data: o.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (p.terminationStatus, s.trimmingCharacters(in: .whitespacesAndNewlines))
}

func currentPowerMode() -> String {
    let sd = sh("/usr/bin/pmset -g | /usr/bin/awk 'tolower($0) ~ /sleepdisabled/ {print $2}'").out
    if sd == "1" { return "맥미니" }
    let ac = sh("/usr/bin/pmset -g custom | /usr/bin/awk '/AC Power/{f=1} f&&/displaysleep/{print $2; exit}'").out
    return ac == "0" ? "피시" : "기본"
}

// passwordless sudo first; on failure fall back to one admin password prompt.
func applyPowerMode(_ mode: String) {
    guard let args = powerModeArgs[mode] else { return }
    var ok = true
    for a in args { if sh("/usr/bin/sudo -n /usr/bin/pmset \(a)").code != 0 { ok = false; break } }
    if !ok {
        let joined = args.map { "/usr/bin/pmset \($0)" }.joined(separator: "; ")
        sh("/usr/bin/osascript -e 'do shell script \"\(joined)\" with administrator privileges'")
    }
}
