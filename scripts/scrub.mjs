#!/usr/bin/env node
// scrub.mjs: privacy check on STAGED content (added lines of `git diff --cached`). Node stdlib only.
//   node scripts/scrub.mjs          scan the staged diff (pre-commit)
//   node scripts/scrub.mjs --range <a> <b>   scan the lines added between two revisions (fw land, before a ci/land push)
//   node scripts/scrub.mjs --tree   scan every tracked file (git ls-files), print counts by rule only
//   node scripts/scrub.mjs --self-check   print {"generic":[...],"account":true|false} (never the name), exit 0
// Rules: email, home-path, session-path, encoded-home, account-name, lan-ip, device-id, secret. Skips snapshot/** and binary files.
// Matched values are never printed (only file:line:col and rule). Allowlist: scripts/scrub-allow.json,
// a JSON array of {"rule","path","reason"}; path is an exact file or a "dir/" prefix; reason is mandatory.
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { userInfo } from 'node:os';

const top = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
const git = (args) => execFileSync('git', ['-c', 'core.quotepath=false', ...args],
  { cwd: top, maxBuffer: 1 << 29 });
const EXCL = ':(exclude)snapshot';

const OKMAIL = ['example.com', 'example.invalid', 'example.org', 'example.net'];
const OKMAILFULL = new Set(['noreply@anthropic.com']);
const FILEEXT = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'avif', 'svg', 'ico', 'css', 'js', 'mjs', 'json',
  'ts', 'tsx', 'woff', 'woff2', 'ttf', 'otf', 'mp4', 'webm', 'html', 'map', 'lean', 'md', 'zip', 'gz', 'tar', 'tgz']);
const OKHOME = new Set(['runner', 'user', 'you', 'name', 'me', 'username', 'Shared', 'example', 'x']);

// The account name is read at run time, never written to a file. FW_SCRUB_ACCOUNT overrides it only together with
// FW_SCRUB_TEST=1 (tests inject a name); alone it is ignored with a stderr note.
// Generic CI/service names are not personal and would flag every `runner` directory.
const GENERIC = new Set(['runner', 'root', 'user', 'admin', 'ubuntu', 'circleci', 'node', 'nobody', 'name', 'me', 'you']);
function accountName() {
  let n = process.env.FW_SCRUB_ACCOUNT;
  if (n !== undefined && process.env.FW_SCRUB_TEST !== '1') {
    console.error('scrub: FW_SCRUB_ACCOUNT ignored (it needs FW_SCRUB_TEST=1)');
    n = undefined;
  }
  if (n === undefined) { try { n = userInfo().username; } catch { n = ''; } }
  n = String(n).trim();
  return n.length >= 3 && !GENERIC.has(n.toLowerCase()) ? n : '';
}
const ACCOUNT = accountName();
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const ACCOUNT_RE = ACCOUNT ? new RegExp('(?<![A-Za-z0-9])' + esc(ACCOUNT) + '(?![A-Za-z0-9])', 'gi') : null;

if (process.argv.includes('--self-check')) {
  console.log(JSON.stringify({ generic: [...GENERIC].sort(), account: ACCOUNT !== '' }));
  process.exit(0);
}

const rules = [
  ['email', (l) => {
    const out = [];
    for (const m of l.matchAll(/[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.([A-Za-z]{2,}))/g)) {
      const dom = m[1].toLowerCase();
      if (OKMAILFULL.has(m[0].toLowerCase()) || FILEEXT.has(m[2].toLowerCase())) continue;
      if (OKMAIL.some((d) => dom === d || dom.endsWith('.' + d))) continue;
      out.push(m.index);
    }
    return out;
  }],
  ['home-path', (l) => {
    const out = [];
    for (const m of l.matchAll(/\/(?:Users|home)\/([A-Za-z0-9._-]+)\//g))
      if (!OKHOME.has(m[1])) out.push(m.index);
    return out;
  }],
  // Claude scratch/project dirs: /private/tmp/claude-<uid>/-Users-<name>-... encode the home path in one segment.
  ['session-path', (l) => {
    const out = [];
    for (const m of l.matchAll(/\/(?:private\/)?tmp\/claude-\d+\/-(?:Users|home)-([A-Za-z0-9._]+)(?=[-\/]|$)/g))
      if (!OKHOME.has(m[1])) out.push(m.index);
    return out;
  }],
  // Any encoded home path (slashes turned into dashes), as in ~/.claude/projects/-Users-<name>-source-...; the name may
  // end the text or precede '/', and the prefix may be glued (claude-501-Users-<name>-, %2F-Users-, C--Users-).
  // Lowercase -home- is also an English word in kebab-case, so only that branch needs a clean left edge.
  ['encoded-home', (l) => {
    const out = [];
    for (const m of l.matchAll(/(?:-Users-|(?<![A-Za-z0-9-])-home-)([A-Za-z0-9._]+)(?=[-\/]|$)/g))
      if (!OKHOME.has(m[1])) out.push(m.index);
    return out;
  }],
  ['account-name', (l) => (ACCOUNT_RE ? [...l.matchAll(ACCOUNT_RE)].map((m) => m.index) : [])],
  ['lan-ip', (l) => {
    const out = [];
    for (const m of l.matchAll(/(?<![\d.])(?:10(?:\.\d{1,3}){3}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2}|192\.168(?:\.\d{1,3}){2})(?!\d)/g))
      out.push(m.index);
    return out;
  }],
  ['device-id', (l) => {
    const out = [];
    for (const m of l.matchAll(/(?<![0-9A-Za-z-])(?:[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}|[0-9A-F]{8}-[0-9A-F]{16})(?![0-9A-Za-z-])/g))
      if (/[A-F]/.test(m[0]) && /\d/.test(m[0])) out.push(m.index);
    return out;
  }],
  ['secret', (l) => {
    const m = /-----BEGIN [A-Z ]*PRIVATE KEY-----/.exec(l);
    return m ? [m.index] : [];
  }],
];
const pathRules = [['secret', (p) => /(^|\/)\.fw-console\//.test(p) && /secret/i.test(p)]];

const PATH_TEXT_RULES = new Set(['encoded-home', 'account-name']);

let allow = [];
const af = join(top, 'scripts/scrub-allow.json');
if (existsSync(af)) {
  allow = JSON.parse(readFileSync(af, 'utf8'));
  for (const a of allow) if (!a.rule || !a.path || !String(a.reason || '').trim()) {
    console.error('scrub: scripts/scrub-allow.json entries need rule, path and a non-empty reason');
    process.exit(2);
  }
}
const allowed = (rule, p) => allow.some((a) => a.rule === rule && (a.path.endsWith('/') ? p.startsWith(a.path) : p === a.path));
const skip = (p) => p === 'snapshot' || p.startsWith('snapshot/');

const hits = [];
function scanLine(p, n, text) {
  for (const [rule, f] of rules) {
    if (allowed(rule, p)) continue;
    for (const idx of f(text)) hits.push({ path: p, line: n, col: idx + 1, rule });
  }
}
function scanPath(p) {
  for (const [rule, f] of pathRules) if (!allowed(rule, p) && f(p)) hits.push({ path: p, line: 0, col: 0, rule });
  // Text rules that also run on the path itself (a file named after the account or an encoded home).
  for (const [rule, f] of rules)
    if (PATH_TEXT_RULES.has(rule) && !allowed(rule, p) && f(p).length) hits.push({ path: p, line: 0, col: 0, rule });
}

const tree = process.argv.includes('--tree');
const nul = (b) => b.toString('utf8').split('\0').filter(Boolean);
if (tree) {
  for (const p of nul(git(['ls-files', '-z', '--', '.', EXCL]))) {
    if (skip(p)) continue;
    scanPath(p);
    let buf;
    try { buf = readFileSync(join(top, p)); } catch { continue; }
    if (buf.includes(0)) continue;
    buf.toString('utf8').split('\n').forEach((t, i) => scanLine(p, i + 1, t));
  }
} else {
  const ri = process.argv.indexOf('--range');
  const revs = ri >= 0 ? [process.argv[ri + 1], process.argv[ri + 2]] : ['--cached'];
  for (const p of nul(git(['diff', ...revs, '--name-only', '--diff-filter=ACMR', '-z', '--', '.', EXCL])))
    if (!skip(p)) scanPath(p);
  const diff = git(['diff', ...revs, '-U0', '--no-color', '--no-ext-diff', '--no-renames', '--', '.', EXCL]).toString('utf8');
  let p = null, n = 0;
  for (const l of diff.split('\n')) {
    if (l.startsWith('+++ ')) { p = l.startsWith('+++ b/') ? l.slice(6).replace(/\t.*$/, '') : null; continue; }
    if (l.startsWith('--- ') || l.startsWith('diff ')) continue;
    const h = /^@@ -\S+ \+(\d+)/.exec(l);
    if (h) { n = Number(h[1]); continue; }
    if (p && !skip(p) && l.startsWith('+')) { scanLine(p, n, l.slice(1)); n++; }
  }
}

if (tree) {
  const c = {};
  for (const h of hits) c[h.rule] = (c[h.rule] || 0) + 1;
  console.log(JSON.stringify(c));
  if (process.argv.includes("--where")) for (const h of hits) console.log(`${h.path}:${h.line} ${h.rule}`);
  process.exit(0);
}
if (hits.length) {
  console.error('scrub: privacy check failed (values hidden on purpose):');
  for (const h of hits) console.error(`  ${h.path}:${h.line}:${h.col}  rule=${h.rule}`);
  console.error('Fix the content, or add {"rule","path","reason"} to scripts/scrub-allow.json (reviewed in the commit).');
  process.exit(1);
}
