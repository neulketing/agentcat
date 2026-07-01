// dooyou active limits probe (Claude + Codex).
// When an account's passive data (statusline capture / session rollout files) is
// missing or stale, spend one cheap request to read live rate limits and write
// ~/.dooyou/limits/<configDir basename>.json for the dooyou menu bar app.
//
//   Claude (~/.claude*): OAuth token from login keychain
//     "Claude Code-credentials-<first8 sha256(configDir)>" (default ~/.claude is
//     the un-suffixed service under the login username). POST /v1/messages
//     max_tokens=1 -> anthropic-ratelimit-unified-{5h,7d}-{utilization,reset}.
//     A rate-limited account still returns the headers on a 429 (no quota spent).
//
//   Codex (~/.codex*): access_token + account_id from <configDir>/auth.json.
//     POST chatgpt.com/backend-api/codex/responses (model gpt-5.5) ->
//     x-codex-{primary,secondary}-used-percent / -reset-at headers.
//
// SAFE: Claude only USES a non-expired token (never refreshes — a refresh rotates
// the refresh token and could log the account out). Missing/expired -> exit != 0.
//
// Usage: node probe-limits.mjs <configDir>
import { execFileSync } from 'child_process';
import { createHash } from 'crypto';
import { readFileSync, writeFileSync, renameSync, mkdirSync } from 'fs';
import { join, basename } from 'path';
import os from 'os';

function keychainToken(service, account) {
  try {
    const args = ['find-generic-password', '-s', service];
    if (account) args.push('-a', account);
    args.push('-w');
    const raw = execFileSync('security', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    const d = JSON.parse(raw);
    const o = d.claudeAiOauth || d;
    if (!o.accessToken) return null;
    return { token: o.accessToken, expiresAt: o.expiresAt };
  } catch { return null; }
}

async function probeClaude(configDir) {
  const h = createHash('sha256').update(configDir).digest('hex').slice(0, 8);
  const cred = keychainToken(`Claude Code-credentials-${h}`)
            || keychainToken('Claude Code-credentials', os.userInfo().username);
  if (!cred) { console.error('no access token'); process.exitCode = 2; return null; }
  if (cred.expiresAt && cred.expiresAt < Date.now()) { console.error('token expired'); process.exitCode = 3; return null; }

  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      authorization: `Bearer ${cred.token}`,
      'anthropic-version': '2023-06-01',
      'anthropic-beta': 'oauth-2025-04-20',
      'content-type': 'application/json',
    },
    body: JSON.stringify({ model: 'claude-haiku-4-5-20251001', max_tokens: 1, messages: [{ role: 'user', content: 'hi' }] }),
  });
  const g = (k) => res.headers.get(`anthropic-ratelimit-unified-${k}`);
  const u5 = g('5h-utilization'), u7 = g('7d-utilization');
  if (u5 == null && u7 == null) { console.error('no rate-limit headers (status ' + res.status + ')'); process.exitCode = 4; return null; }
  const pct = (u) => (u == null ? null : Math.round(parseFloat(u) * 100));
  const rl = {};
  if (u5 != null) rl.five_hour = { used_percentage: pct(u5), resets_at: g('5h-reset') ? parseInt(g('5h-reset'), 10) : null };
  if (u7 != null) rl.seven_day = { used_percentage: pct(u7), resets_at: g('7d-reset') ? parseInt(g('7d-reset'), 10) : null };
  return rl;
}

function codexModel(configDir) {
  try {
    const m = readFileSync(join(configDir, 'config.toml'), 'utf8').match(/^\s*model\s*=\s*["']?([^"'\s#]+)/m);
    return m ? m[1] : 'gpt-5.5';
  } catch { return 'gpt-5.5'; }
}

async function probeCodex(configDir) {
  let auth;
  try { auth = JSON.parse(readFileSync(join(configDir, 'auth.json'), 'utf8')); } catch { console.error('no auth.json'); process.exitCode = 2; return null; }
  const tok = auth?.tokens?.access_token, acc = auth?.tokens?.account_id;
  if (!tok || !acc) { console.error('no codex token'); process.exitCode = 2; return null; }

  // stream:true so headers arrive up front; read them, then abort — never wait
  // for gpt-5.5 reasoning to finish (that would hang and burn output tokens).
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 15000);
  let res;
  try {
    res = await fetch('https://chatgpt.com/backend-api/codex/responses', {
      method: 'POST',
      headers: {
        authorization: `Bearer ${tok}`,
        'chatgpt-account-id': acc,
        'OpenAI-Beta': 'responses=experimental',
        originator: 'codex_cli_rs',
        'content-type': 'application/json',
      },
      body: JSON.stringify({ model: codexModel(configDir), instructions: '', input: [{ type: 'message', role: 'user', content: [{ type: 'input_text', text: 'hi' }] }], stream: true, store: false }),
      signal: ctrl.signal,
    });
  } catch (e) { clearTimeout(timer); console.error('codex fetch failed: ' + e); process.exitCode = 4; return null; }

  const h = (k) => res.headers.get(`x-codex-${k}`);
  const p5 = h('primary-used-percent'), s7 = h('secondary-used-percent');
  const pr = h('primary-reset-at'), sr = h('secondary-reset-at');
  ctrl.abort();            // headers captured — drop the SSE body
  clearTimeout(timer);
  if (p5 == null && s7 == null) { console.error('no codex rate headers (status ' + res.status + ')'); process.exitCode = 4; return null; }
  const rl = {};
  if (p5 != null) rl.five_hour = { used_percentage: Math.round(parseFloat(p5)), resets_at: pr ? parseInt(pr, 10) : null };
  if (s7 != null) rl.seven_day = { used_percentage: Math.round(parseFloat(s7)), resets_at: sr ? parseInt(sr, 10) : null };
  return rl;
}

// GLM (Z.ai). The `glm` worker runs Claude Code against Z.ai, but Z.ai does NOT
// return per-window usage in message headers. The real quota lives at a dedicated
// endpoint (used by OMC's HUD): GET /api/monitor/usage/quota/limit → data.limits[]
// with unit-coded windows (3 = 5h, 6 = weekly, 5 = monthly) and a 0-100 percentage.
// It's a plain GET — no inference tokens spent.
function readZaiKey() {
  try {
    const m = readFileSync(join(process.env.HOME, '.secrets', 'master.env'), 'utf8')
      .match(/^ZAI_API_KEY=(.+)$/m);
    return m ? m[1].trim().replace(/^["']|["']$/g, '') : null;
  } catch { return null; }
}

async function probeGlm() {
  const key = readZaiKey();
  if (!key) { console.error('no ZAI_API_KEY'); process.exitCode = 2; return null; }
  const res = await fetch('https://api.z.ai/api/monitor/usage/quota/limit', {
    headers: { authorization: `Bearer ${key}` },
  });
  const j = await res.json().catch(() => null);
  const limits = j && j.data && j.data.limits;
  if (!Array.isArray(limits)) { console.error('no glm quota (status ' + res.status + ')'); process.exitCode = 4; return null; }
  const bucketFor = { 3: 'five_hour', 6: 'seven_day', 5: 'monthly' };
  const rl = {};
  for (const l of limits) {
    const bucket = bucketFor[l.unit];
    if (!bucket || l.percentage == null) continue;
    rl[bucket] = { used_percentage: Math.round(l.percentage), resets_at: l.nextResetTime ? Math.floor(l.nextResetTime / 1000) : null };
  }
  return Object.keys(rl).length ? rl : null;
}

async function main() {
  const configDir = process.argv[2];
  if (!configDir) { console.error('usage: probe-limits.mjs <configDir>'); process.exit(64); }
  const isGlm = configDir === 'glm';
  const isCodex = configDir.includes('/.codex');
  const rate_limits = await (isGlm ? probeGlm() : isCodex ? probeCodex(configDir) : probeClaude(configDir));
  if (!rate_limits) return;

  const dir = join(process.env.HOME, '.dooyou', 'limits');
  mkdirSync(dir, { recursive: true });
  const out = {
    // synthetic transcript_path so dooyou's Claude account-prefix check accepts it
    transcript_path: join(configDir, 'projects', '__dooyou_probe__.jsonl'),
    captured_at: Math.floor(Date.now() / 1000),
    source: 'probe',
    rate_limits,
  };
  const dest = join(dir, basename(configDir) + '.json');
  const tmp = dest + '.' + process.pid + '.tmp';
  writeFileSync(tmp, JSON.stringify(out));
  renameSync(tmp, dest);
  const f = rate_limits.five_hour, s = rate_limits.seven_day;
  console.error(`probe ok ${basename(configDir)} 5h=${f ? f.used_percentage : '-'}% wk=${s ? s.used_percentage : '-'}%`);
}

main().catch((e) => { console.error(String(e)); process.exit(1); });
