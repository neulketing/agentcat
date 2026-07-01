# dooyou-bin — live limits helpers

Deployed to `~/.dooyou/bin/` by `script/install_login_item.sh`. They feed
`~/.dooyou/limits/<configdir-basename>.json`, which the dooyou app reads to show
per-account 5h / weekly limits with reset times.

- **statusline-wrap.sh** — wrap a Claude Code `statusLine` command. Renders the
  existing HUD unchanged and, in the background, captures the statusline stdin's
  `rate_limits` for the active account. Zero-cost, always fresh while in use.
- **capture-limits.mjs** — the capture invoked by the wrapper. Keyed to the
  account by the stdin `transcript_path` (`.../<configdir>/projects/...`).
- **probe-limits.mjs `<configDir>`** — one-shot live probe for an account with no
  fresh capture (idle). The dooyou app runs it (gated 5 min/account) when limits
  are missing or a reset has passed.
  - Claude (`~/.claude*`): OAuth token from the login keychain
    (`Claude Code-credentials-<first8 sha256(configDir)>`; the default `~/.claude`
    is the un-suffixed service under the login username). `POST /v1/messages`
    `max_tokens=1` → `anthropic-ratelimit-unified-{5h,7d}-*` headers. A
    rate-limited account still returns headers on 429 (no quota spent). Never
    refreshes an expired token (that would risk logging the account out).
  - Codex (`~/.codex*`): `tokens.{access_token,account_id}` from
    `<configDir>/auth.json`, model from `<configDir>/config.toml`. `POST
    chatgpt.com/backend-api/codex/responses` (stream, read headers, abort) →
    `x-codex-{primary,secondary}-{used-percent,reset-at}` headers.

## Enable the statusline capture

For each Claude Code config dir, set `settings.json`:

```json
"statusLine": { "type": "command", "command": "sh $HOME/.dooyou/bin/statusline-wrap.sh" }
```

The wrapper calls the real HUD via `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hud/omc-hud.mjs`.
