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
  const out = {
    transcript_path: tp,
    captured_at: Math.floor(Date.now() / 1000),
    rate_limits: rl,                                // stored raw; dooyou reads five_hour/seven_day
  };
  const dest = join(dir, key + '.json');
  const tmp = dest + '.' + process.pid + '.tmp';
  writeFileSync(tmp, JSON.stringify(out));
  renameSync(tmp, dest);
} catch {
  // Best-effort; never disturb the statusline render.
}
