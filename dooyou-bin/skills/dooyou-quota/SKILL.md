---
name: dooyou-quota
description: Check dooyou's live per-account AI rate limits before routing heavy work, choosing a model/provider, or after a rate-limit error — so you route to an account with headroom instead of a maxed one. Triggers on "which account", "quota", "rate limit", "route to", "provider is maxed", "429".
---

# dooyou-quota

`dooyou` (the menu-bar monitor) already tracks live rate limits for every AI
account on this machine — Claude 1/2, Codex 1/2, GLM — with 5h / weekly / (GLM)
monthly windows, in `~/.dooyou/limits/*.json`. dooyou is the single source of
truth. **Do not re-probe providers yourself — read dooyou's numbers via `quota`.**

## When to use

- Before starting heavy / long work → pick the account with the most headroom.
- After a provider returns a rate-limit / 429 error → switch to an account with room.
- When deciding which provider/model to route a task to.

## How

Run `quota` (it's in PATH — use the bash tool):

```
quota                 # ranked table: headroom + 5h/wk/mo used% per account
quota --best          # the single highest-headroom account right now
quota --best claude   # best account for a provider (claude | codex | glm)
quota --json          # machine-readable, for scripting a routing decision
```

Headroom = 100 − max(5h, weekly, monthly used%). Higher = safer. An account at
0% headroom is maxed — avoid it until its window resets (it will fail with a
rate-limit error otherwise).

## Rules

- Prefer the highest-headroom account for the provider you need; map GJC providers
  to dooyou accounts (openai-codex→codex, anthropic→claude, zai→glm).
- Never route to a maxed (0% headroom) account.
- If `quota` is stale (`m!` marker) or errors, fall back to normal routing and
  note it — never block on it.
