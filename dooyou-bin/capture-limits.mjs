// dooyou statusline-limits capture.
// Reads Claude Code statusline stdin JSON and persists the per-account
// rate_limits (5h / weekly usage + reset) so the dooyou menu bar app can show
// live limits without depending on OMC's internal cache.
//
// Account key = the config dir basename derived from transcript_path
// (".../<configDir>/projects/..."), e.g. ".claude" or ".claude-account2".
// Written atomically (tmp + rename) so a backgrounded/interrupted render never
// leaves a half-written file for the reader.
import { readFileSync, writeFileSync, renameSync, mkdirSync } from 'fs';
import { join, basename } from 'path';

try {
  const raw = readFileSync(0, 'utf8');
  const d = JSON.parse(raw);
  const tp = d.transcript_path;
  const rl = d.rate_limits;
  if (!tp || !rl || (rl.five_hour == null && rl.seven_day == null)) process.exit(0);

  const i = tp.indexOf('/projects/');
  if (i < 0) process.exit(0);
  const key = basename(tp.slice(0, i));            // .claude / .claude-account2
  if (!key) process.exit(0);

  const dir = join(process.env.HOME, '.dooyou', 'limits');
  mkdirSync(dir, { recursive: true });
  const dest = join(dir, key + '.json');

  // Statusline stdin carries five_hour/seven_day but NOT the Fable-scoped weekly
  // (that comes only from the probe's /api/oauth/usage). Carry a prior probe's
  // fable_weekly forward so a statusline render doesn't blank it — it self-ages via
  // its own captured_at, so quota drops it once stale.
  if (rl.fable_weekly == null) {
    try {
      const prev = JSON.parse(readFileSync(dest, 'utf8'));
      if (prev.rate_limits?.fable_weekly) rl.fable_weekly = prev.rate_limits.fable_weekly;
    } catch { /* no prior file */ }
  }

  const out = {
    schema: 1,                                      // additive contract version (omf CONTRACT.md)
    transcript_path: tp,
    captured_at: Math.floor(Date.now() / 1000),
    rate_limits: rl,                                // stored raw; dooyou reads five_hour/seven_day/fable_weekly
  };
  const tmp = dest + '.' + process.pid + '.tmp';
  writeFileSync(tmp, JSON.stringify(out));
  renameSync(tmp, dest);
} catch {
  // Best-effort; never disturb the statusline render.
}
