# DOOYOU Summary

DOOYOU is a native macOS menu bar companion for local AI-agent activity. It
shows live agent usage, connector readiness, local system pressure, and account
cost/limit signals in a compact popover, then gives deeper management views in a
dashboard.

## Product Direction

DOOYOU is intended to become the user's personal coordination layer: always
running on the Mac, watching local AI workflows, surfacing pressure or limits
early, and routing the user to the right CLI, account, machine, or dashboard
without needing to parse terminal output.

The app should stay quiet and native. The menu bar is the glance surface. The
popover is the operational surface. The dashboard is the configuration and
analysis surface.

## Current Shape

- Menu bar mascot and today usage total.
- Fixed-position popover with connector status, system pressure, totals, account
  rows, dashboard entry, and power-mode controls.
- Dashboard with routes for home, connectors, analytics, accounts, and mascot.
- Automatic CLI discovery for installed AI tools.
- API-key setup using macOS Keychain, not JSON files.
- Custom CLI/API/MCP connector definitions.
- Multi-account route cards for the user's current MacBook setup.
- Local Claude/Codex/GLM usage scanning from available transcript caches.
- SwiftPM app bundle build, local install, release zip packaging, and remote
  install scripts.

## Identity

The primary mascot is `두유`, based on a Coton de Tulear puppy. The visible
mascot set is intentionally small:

- `두유`: active executor and friendly work companion.
- `고양이`: calm analyst for usage and system signals.
- `거북이`: long-horizon stability, limits, and budget tracking.

The design target is a clean native utility, not a novelty widget. Motion should
make the app feel alive, but status clarity comes first.

## Main Decisions

- The product name is `DOOYOU`; package, app, bundle, scripts, and local support
  files use `dooyou`.
- The bundle identifier is `local.dooyou`.
- The local app support folder is
  `~/Library/Application Support/dooyou/`.
- API keys are stored in the login Keychain service
  `local.dooyou.api-key`.
- Login persistence is handled by `~/Library/LaunchAgents/local.dooyou.plist`.
- The installer uses a direct binary LaunchAgent with `KeepAlive` so DOOYOU
  stays available as a coordinator.

## Verification Surfaces

- `swift build`
- `./script/build_and_run.sh --verify`
- `./script/install_login_item.sh`
- `launchctl print gui/$(id -u)/local.dooyou`
- `pgrep -ax dooyou`
- `./script/package_release.sh`
- `unzip -l dist/release/dooyou-macos.zip`
