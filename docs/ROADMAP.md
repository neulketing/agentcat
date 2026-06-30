# DOOYOU Roadmap

## North Star

DOOYOU should become a personal AI-work coordinator for the user's Mac setup:
always-on, low-noise, local-first, and aware of account routes, machine state,
tool logins, usage pressure, and next actions.

## Product Lanes

### 1. Always-On Coordinator

- Keep the LaunchAgent managed with `KeepAlive`.
- Add a user-facing status for whether the app is launchd-managed.
- Add a clear dashboard action for stop/restart/reinstall so persistent mode is
  understandable.
- Keep logs readable under `~/Library/Logs/dooyou/`.

### 2. Connector Intelligence

- Continue improving automatic CLI detection.
- Group connectors by role: coding, research, design, browser, local MCP.
- Show missing-login vs missing-install vs data-unavailable as separate states.
- Make API key health checks explicit without exposing secret values.

### 3. Account Routing

- Make route cards the main place to understand which account is used for which
  tool.
- Support per-route notes, local cache paths, and launch commands.
- Keep the MacBook default routes explicit while allowing other Macs to start
  with a clean default configuration.

### 4. Multi-Mac Setup

- Use the release zip for first install.
- Use Remote Login plus Tailscale for future automatic updates.
- Show remote reachability and install readiness inside the dashboard later.
- Keep remote actions gated because they change another machine.

### 5. Dashboard UX

- Keep the popover compact and glanceable.
- Move connector detail and account routing into dashboard routes.
- Preserve the satisfying dense account-cost rows.
- Keep system metrics readable with labels, color, and stable tile sizes.

### 6. Mascot Quality

- Keep exactly three visible mascots until all three meet the Dooyou quality bar.
- Replace vector fallback cat/turtle with authored transparent bitmap frame sets
  when available.
- Preserve the menu-bar capsule theme as a small background signal, not a full
  dashboard theme system.

## Not Yet Public-Distribution Ready

Before public release:

- Developer ID signing.
- Hardened runtime.
- Notarization.
- Stapling.
- Update channel and rollback story.
- Privacy note explaining local transcript/cache reads.
