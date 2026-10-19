// Refuses a new literal millisecond bound in a land-selected test file unless scripts/wallclock-allow.json whitelists it
// with a reason. Decision: Lean `Fw.Console.WallClock` (`refuse`, golden packages/contracts/golden/console/wallclock.jsonl);
// this file is the lexing (which site a number sits in) plus I/O. Task land-wallclock-off-gate.
//   node scripts/lint-wallclock.mjs            lint the tracked test files
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const root = join(dirname(new URL(import.meta.url).pathname), '..');

export const SCOPE = [/^apps\/(runner|console-api|console-web)\/test\/.*\.test\.(ts|tsx|mjs)$/, /^scripts\/[^/]*\.test\.mjs$/];

const LIMITS = new Set(['assertLt', 'timeoutOpt', 'deadlineArg', 'elapsedCmp']);
// Lean `isBound` and `refuse`: a bound is n > 0 at a limiting site; refused when no non-blank reason.
export const isBound = (site, n) => LIMITS.has(site) && n > 0;
export const reasonOk = (r) => /\S/.test(r);
export const refuse = (site, n, reason) => isBound(site, n) && !reasonOk(reason);

const NUM = String.raw`(\d[\d_]*)`;
const TIMEY = /Date\.now|performance\.now|\b\w*[mM]s\b|elapsed|duration/;
const RULES = [
  // [site, regex with the number in group 1, extra line condition]
  ['assertLt', new RegExp(String.raw`toBeLessThan(?:OrEqual)?\(\s*` + NUM), TIMEY],
  ['timeoutOpt', new RegExp(String.raw`\b(?:test|hook)?[tT]imeout:\s*` + NUM)],
  ['timeoutOpt', new RegExp(String.raw`^\s*\}\s*,\s*` + NUM + String.raw`\s*\)\s*;?\s*(?://.*)?$`)],
  ['deadlineArg', new RegExp(String.raw`\w*[tT]imeout\w*\(\s*` + NUM)],
  ['deadlineArg', new RegExp(String.raw`\bask\(.*,\s*` + NUM + String.raw`\s*\)`)],
  ['deadlineArg', new RegExp(String.raw`selectCore\(.*,\s*` + NUM + String.raw`\s*\)\s*;?\s*$`)],
  ['elapsedCmp', new RegExp(String.raw`[<>]=?\s*` + NUM), /Date\.now\(\)|performance\.now\(\)/],
];
const SLEEP = new RegExp(String.raw`(?:setTimeout\([^)]*?,|\bwait\(|\bsleep\()\s*` + NUM);

const num = (s) => Number(s.replaceAll('_', ''));

/** Literal numbers of one line with their site. A line that reads an env knob (`process.env.X ?? 5000`) is the knob. */
export function sites(line) {
  if (/^\s*(\/\/|\*|\/\*)/.test(line) || /process\.env\./.test(line)) return [];
  const out = [];
  const sleep = SLEEP.exec(line);
  if (sleep) out.push({ site: 'sleep', ms: num(sleep[1]) });
  for (const [site, re, cond] of RULES) {
    if (cond && !cond.test(line)) continue;
    const m = re.exec(line);
    if (m) out.push({ site, ms: num(m[1]) });
  }
  return out;
}

export function loadAllow(rootDir = root) {
  const p = join(rootDir, 'scripts/wallclock-allow.json');
  return existsSync(p) ? JSON.parse(readFileSync(p, 'utf8')).allow : [];
}

/** reason of the allow entry covering `file` and `text` (the trimmed line), or "" */
export function reasonFor(allow, file, text) {
  return allow.find((a) => a.file === file && text.includes(a.text))?.reason ?? '';
}

/** findings of one file's text: refused literals with their line */
export function lintText(file, text, allow) {
  const found = [];
  text.split('\n').forEach((line, i) => {
    for (const { site, ms } of sites(line)) {
      const reason = reasonFor(allow, file, line.trim());
      if (refuse(site, ms, reason)) found.push({ file, line: i + 1, site, ms, text: line.trim() });
    }
  });
  return found;
}

/** allow entries that match no bound any more: a stale whitelist hides nothing but rots */
export function staleAllow(allow, texts) {
  return allow.filter((a) => {
    const t = texts.get(a.file);
    return !t || !t.split('\n').some((l) => l.includes(a.text) && sites(l).some((s) => isBound(s.site, s.ms)));
  });
}

export function run(rootDir = root) {
  const files = execFileSync('git', ['ls-files'], { cwd: rootDir, encoding: 'utf8' }).split('\n').filter((f) => SCOPE.some((re) => re.test(f)));
  const allow = loadAllow(rootDir);
  const texts = new Map(files.map((f) => [f, readFileSync(join(rootDir, f), 'utf8')]));
  const problems = [];
  for (const a of allow) if (!reasonOk(a.reason ?? '')) problems.push(`allow entry without a reason: ${a.file} ${a.text}`);
  for (const [f, t] of texts) for (const x of lintText(f, t, allow)) problems.push(`${x.file}:${x.line}: literal ${x.ms} ms (${x.site}) is an absolute wall-clock bound; use an ordering, call count, fake timers or a ratio, or whitelist it in scripts/wallclock-allow.json with a reason: ${x.text}`);
  for (const a of staleAllow(allow, texts)) problems.push(`stale allow entry (no bound matches): ${a.file} ${a.text}`);
  return problems;
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const problems = run();
  for (const p of problems) console.error(p);
  if (problems.length) process.exit(1);
  console.log('lint-wallclock: ok');
}
