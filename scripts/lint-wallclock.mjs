// Refuses a new literal millisecond bound in a land-selected test file unless scripts/wallclock-allow.json whitelists it
// with a reason. Decision: Lean `Fw.Console.WallClock` (`refuse`, golden packages/contracts/golden/console/wallclock.jsonl);
// this file is the lexing (which site a number sits in) plus I/O. Task land-wallclock-off-gate.
// LISTED TS STAND-IN (follow-up task wallclock-lint-lean): the site classification (line regexes), the allow-entry matching
// and the stale rule are TS only; only the decision on a classified literal is Lean. Line-based: a bound split across lines
// is missed. The test fixtures live in scripts/lint-wallclock-cases/*.txt so that this lint passes on its own test.
//   node scripts/lint-wallclock.mjs            lint the tracked test files
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const root = join(dirname(new URL(import.meta.url).pathname), '..');

// Every test file a land can select: app and package test dirs, the CI script tests, the scripts tests, and the co-located
// tests of apps/site (parts, engine, registry, shells, stage) and the premise tests.
export const SCOPE = [
  /^(apps|packages)\/[^/]+\/test\/.*\.(test\.)?(ts|tsx|mjs)$/,
  /^\.github\/scripts\/[^/]*\.test\.mjs$/,
  /^scripts\/[^/]*\.test\.mjs$/,
  /^apps\/site\/(src|scripts)\/.*\.test\.(ts|tsx|mjs)$/,
];

const LIMITS = new Set(['assertLt', 'timeoutOpt', 'deadlineArg', 'elapsedCmp', 'loopCap']);
// Lean `isBound` and `refuse`: a bound is n > 0 at a limiting site; refused when no non-blank reason.
export const isBound = (site, n) => LIMITS.has(site) && n > 0;
// Lean `String.isWhitespace` is exactly these four characters (not JS `\s`: \v, no-break space and others count as text).
export const reasonOk = (r) => /[^ \t\r\n]/.test(r);
export const refuse = (site, n, reason) => isBound(site, n) && !reasonOk(reason);

const NUM = String.raw`(\d[\d_]*)(?![\d_.eE])`;
const TIMEY = /Date\.now|performance\.now|\b\w*[mM]s\b|elapsed|duration/;
const RULES = [
  // [site, regex with the number in group 1, extra line condition]
  ['assertLt', new RegExp(String.raw`toBeLessThan(?:OrEqual)?\(\s*` + NUM), TIMEY],
  ['timeoutOpt', new RegExp(String.raw`\b(?:(?:test|hook)Timeout|timeout):\s*` + NUM)],
  ['timeoutOpt', new RegExp(String.raw`^\s*\}\s*,\s*` + NUM + String.raw`\s*\)\s*;?\s*(?://.*)?$`)],
  ['deadlineArg', new RegExp(String.raw`\w*[tT]imeout\w*\(\s*` + NUM)],
  ['deadlineArg', new RegExp(String.raw`\bask\(.*,\s*` + NUM + String.raw`\s*\)`)],
  ['deadlineArg', new RegExp(String.raw`selectCore\(.*,\s*` + NUM + String.raw`\s*\)\s*;?\s*$`)],
  ['elapsedCmp', new RegExp(String.raw`[<>]=?\s*` + NUM), /Date\.now\(\)|performance\.now\(\)/],
];
const LOOP = /\bfor\s*\([^;)]*;\s*\w+\s*<=?\s*(\d[\d_]*)\s*;/;
const SLEEPY = /\bwait\(|\bsleep\(|setTimeout\(/;
const SLEEP = new RegExp(String.raw`(?:setTimeout\([^)]*?,|\bwait\(|\bsleep\()\s*` + NUM);

const num = (s) => Number(s.replaceAll('_', ''));

/** The body of the block a line opens: up to 8 following lines, ending at the first line that closes at the line's indent. */
export function bodyAfter(lines, i) {
  const open = (lines[i].match(/\{/g) ?? []).length - (lines[i].match(/\}/g) ?? []).length;
  if (open <= 0) return '';
  const ind = /^\s*/.exec(lines[i])[0].length;
  const out = [];
  for (const l of lines.slice(i + 1, i + 9)) {
    if (/^\s*\}/.test(l) && /^\s*/.exec(l)[0].length <= ind) break;
    out.push(l);
  }
  return out.join('\n');
}

/** Literal numbers of one line with their site. A line that reads an env knob (`process.env.X ?? 5000`) is the knob.
 *  `ahead` is the text of the next few lines: a counted `for (...; i < N; ...)` loop with a sleep in it is a cap of N polls. */
export function sites(line, ahead = '') {
  if (/^\s*(\/\/|\*|\/\*)/.test(line) || /process\.env\./.test(line)) return [];
  const out = [];
  const loop = LOOP.exec(line);
  if (loop && SLEEPY.test(line + '\n' + ahead)) out.push({ site: 'loopCap', ms: num(loop[1]) });
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
  const lines = text.split('\n');
  lines.forEach((line, i) => {
    for (const { site, ms } of sites(line, bodyAfter(lines, i))) {
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
    if (!t) return true;
    const ls = t.split('\n');
    return !ls.some((l, i) => l.includes(a.text) && sites(l, bodyAfter(ls, i)).some((s) => isBound(s.site, s.ms)));
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
