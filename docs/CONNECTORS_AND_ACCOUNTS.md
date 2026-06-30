# Connectors And Account Routes

## Connector Philosophy

DOOYOU should start quietly on a fresh Mac even when no AI CLIs are installed.
It detects what exists, shows login actions for available CLIs, and lets the user
add API or MCP connectors only when needed.

The default connector experience is automatic discovery. The manual builder is
kept under advanced settings so the dashboard does not feel like a setup form.

## Built-In Connectors

- Claude: CLI-first, API key optional through `ANTHROPIC_API_KEY`.
- Codex: CLI-first, API key optional through `OPENAI_API_KEY`.
- GLM: API-centered through `ZAI_API_KEY`; local `glm-*` usage is detected when
  available.

API keys are stored in the macOS login Keychain under service
`local.dooyou.api-key`. Connector JSON files store metadata only.

## Auto-Discovered CLIs

The current catalog includes:

- Aider
- OpenCode
- Gemini
- Antigravity
- Claude
- Codex
- GLM
- Qwen Code
- Cline
- Roo Code
- Crush

When a supported executable is found on `PATH`, DOOYOU shows it as discovered
and exposes the login or launch command for that tool.

## Custom Connectors

Custom connectors are stored at:

```text
~/Library/Application Support/dooyou/connectors.json
```

Supported connector types:

- CLI: command, login command, optional local data path.
- API: environment key name plus Keychain-backed secret value.
- MCP: local command or MCP/documentation URL.

## Multi-Account Routes

The current MacBook route map is modeled around the user's active accounts:

- Piolabs
  - Claude 1: `inc.polabs@gmail.com`, `~/.claude`
  - Codex 1: `inc.polabs@gmail.com`, `~/.codex`
- NudgeSpace
  - Claude 2: `ceo@nudge-space.com`, `~/.claude-account2`
  - Codex 2: `ceo@nudge-space.com`, `~/.codex-account2`
- Neulketing
  - GLM: `ZAI_API_KEY`
  - Gemini: CLI login route when available

The dashboard can create and open an editable route config at:

```text
~/Library/Application Support/dooyou/account-routes.json
```

This lets other Macs start with default routes and lets this Mac keep its
multi-account setup explicit.

## Local Usage Sources

DOOYOU reads local usage data when these caches exist:

- `~/.claude/projects`
- `~/.claude-account2/projects`
- `~/.codex/sessions`
- `~/.codex-account2/sessions`

If those folders do not exist, the app still runs and shows connector readiness
instead of treating missing local data as an error.
