#!/usr/bin/env node
// Leak scan for the Jev trial rows (task jev-file-context-note). Measures what expanding the repo files a row names
// would add to its state: how many rows name a path, how large the files are against the oracle caps, which files carry
// the row's own label (a leak) or another label (a decoy), and whether a row scores differently when it names files.
// The rows are read from a path argument and never copied here; the files are read from git at fixed commits.
//
// Usage: node scripts/jev-leak.mjs --rows <dir with rows-d1.json, rows-d2.json> [--clean <dir>] [--json <out>]
//   --clean: a results/jev-arms-clean directory; its d1/d2 Haiku and Sonnet answers are scored as extra arms.
// Read-only: no Jev send, no claude -p call, no write except --json.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Source commits. d1: the ledger commit the D1 rows were built from. d2: main when the trial counts were written; D2
// rows come from review journals, which have no ledger commit.
export const SRC = { d1: 'ecdc0787', d2: 'c31e0848' };

// A repo path: a top-level repo dir, a slash, then path characters. ':' is not a path character, so a `:N` line
// suffix is cut off. Trailing '.' and ',' are stripped; a leading '../' is kept in the count and dropped to resolve.
const TOPS = ['research', 'docs', 'lean', 'lean-math', 'apps', 'packages', 'scripts', '\\.github', '\\.claude',
  '\\.circleci', 'refs', 'results', 'snapshot', '\\.cache', '\\.local'];
export const PATH_RE = new RegExp(
  `(?<![A-Za-z0-9_./-])(?:\\.\\./)?(?:${TOPS.join('|')})/[A-Za-z0-9_.@*{}<>,/+-]*[A-Za-z0-9_*}>]`, 'g');

// The code-only allowlist used to count the rows a pinned expansion would change (Option A).
const CODE_PREFIXES = ['apps/', 'packages/', 'scripts/', 'lean/Fw/'];
const CODE_DENY = ['lean/Fw/Oracle/'];
const CODE_EXTS = ['.lean', '.ts', '.tsx', '.mjs', '.js', '.sh', '.yaml'];

const BLOB_MAX = 3e6;
const STATE_CAP = 32768;
const BODY_CAP = 65536;

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, xs) =>
  a.startsWith('--') ? [...acc, [a.slice(2), xs[i + 1]]] : acc, []));
if (!args.rows) { console.error('usage: jev-leak.mjs --rows <dir> [--clean <dir>] [--json <out>]'); process.exit(2); }

const git = (...a) => {
  try { return execFileSync('git', ['-C', REPO, ...a], { maxBuffer: 1 << 28, stdio: ['ignore', 'pipe', 'ignore'] }).toString(); }
  catch { return null; }
};
const flat = v => typeof v === 'string' ? [v] : Array.isArray(v) ? v.flatMap(flat)
  : v && typeof v === 'object' ? Object.values(v).flatMap(flat) : [];
const median = xs => { const s = [...xs].sort((a, b) => a - b); return s.length ? s[Math.floor((s.length - 1) / 2)] : 0; };
const pct = (xs, q) => { const s = [...xs].sort((a, b) => a - b); return s.length ? s[Math.min(s.length - 1, Math.ceil(q * s.length) - 1)] : 0; };
const kb = n => `${(n / 1024).toFixed(1)} KiB`;

const objCache = new Map();
/** {kind: blob|tree|missing|pattern, bytes, text, escaped} for path p at commit sha. */
function obj(sha, p) {
  const key = `${sha}:${p}`;
  if (objCache.has(key)) return objCache.get(key);
  let o;
  if (/[*{}<>]/.test(p)) o = { kind: 'pattern' };
  else {
    const kind = git('cat-file', '-t', key)?.trim();
    if (kind !== 'blob') o = { kind: kind ?? 'missing' };
    else {
      const bytes = Number(git('cat-file', '-s', key));
      o = { kind, bytes };
      if (bytes <= BLOB_MAX) {
        const buf = execFileSync('git', ['-C', REPO, 'cat-file', 'blob', key], { maxBuffer: 1 << 28 });
        if (!buf.subarray(0, 8000).includes(0)) {
          o.text = buf.toString('utf8');
          o.escaped = Buffer.byteLength(JSON.stringify(o.text)) - 2;
        }
      }
    }
  }
  objCache.set(key, o);
  return o;
}
const resolvePath = p => p.replace(/^\.\.\//, '').replace(/@[0-9a-f]{7,40}$/, '');
const isCode = p => CODE_PREFIXES.some(x => p.startsWith(x)) && !CODE_DENY.some(x => p.startsWith(x))
  && CODE_EXTS.some(e => p.endsWith(e));
const taskOf = id => id.split('#')[0];

const ledger = JSON.parse(git('show', `${SRC.d1}:docs/team/incidents/ledger.json`)).incidents;
const incAt = Object.fromEntries(ledger.map(i => [i.id, i.at]));
const pinCache = new Map();
const pinBefore = at => {
  if (!pinCache.has(at)) pinCache.set(at, git('rev-list', '-1', `--before=${at}`, SRC.d1)?.trim() || null);
  return pinCache.get(at);
};
const changedSince = (at, p) => (git('log', '--format=%h', `--since=${at}`, SRC.d1, '--', p) ?? '').trim().split('\n').filter(Boolean).length;

const cleanArms = {};
if (args.clean) for (const set of ['d1', 'd2']) for (const arm of ['haiku', 'sonnet']) {
  const f = path.join(args.clean, `${set}-${arm}.answers.jsonl`);
  if (!fs.existsSync(f)) continue;
  cleanArms[`${set}:${arm}-clean`] = Object.fromEntries(fs.readFileSync(f, 'utf8').trim().split('\n')
    .map(l => JSON.parse(l)).map(a => [a.id, a.choice]));
}

const out = { src: SRC, regex: PATH_RE.source, sets: {} };
const lines = [];
const say = s => lines.push(s);

for (const set of ['d1', 'd2']) {
  const rows = JSON.parse(fs.readFileSync(path.join(args.rows, `rows-${set}.json`), 'utf8'));
  const sha = SRC[set];
  const vocab = Object.keys(rows[0].criteria).filter(k => k !== 'none' && k !== 'unclear');
  const fieldRows = {};
  const per = rows.map(r => {
    const ps = new Set();
    for (const [field, v] of Object.entries(r.state)) {
      const m = new Set((flat(v).join('\n').match(PATH_RE) ?? []).map(p => p.replace(/[.,]+$/, '')));
      if (m.size) fieldRows[field] = (fieldRows[field] ?? 0) + 1;
      m.forEach(p => ps.add(p));
    }
    const files = [...ps].map(p => ({ p, rp: resolvePath(p), ...obj(sha, resolvePath(p)) }));
    const blobs = files.filter(f => f.kind === 'blob');
    const text = blobs.filter(f => f.text !== undefined);
    const row = { id: r.id, label: r.label, paths: [...ps], blobs: blobs.length,
      raw: blobs.reduce((s, f) => s + f.bytes, 0), escaped: text.reduce((s, f) => s + f.escaped, 0) };
    if (set === 'd1') {
      // D1 labels are class ids, so a file holding one is a leak (own label) or a decoy (another class).
      row.labelLeak = text.filter(f => f.text.includes(r.label)).map(f => f.rp);
      row.decoys = text.flatMap(f => vocab.filter(c => c !== r.label && f.text.includes(c)).map(c => `${f.rp}=${c}`));
      row.idLeak = text.filter(f => f.text.includes(r.id)).map(f => f.rp);
      const at = incAt[r.id];
      row.at = at ?? null;
      row.postChanged = at ? blobs.filter(f => changedSince(at, f.rp) > 0).map(f => f.rp) : [];
      const pin = at ? pinBefore(at) : null;
      row.pin = pin;
      const pinned = pin ? files.map(f => ({ rp: f.rp, ...obj(pin, f.rp) })).filter(f => f.text !== undefined) : [];
      row.pinLabelLeak = pinned.filter(f => f.text.includes(r.label)).map(f => f.rp);
      row.pinIdLeak = pinned.filter(f => f.text.includes(r.id)).map(f => f.rp);
      row.optionA = pinned.some(f => isCode(f.rp)
        && !vocab.some(w => f.text.toLowerCase().includes(w)) && !f.text.includes(r.id));
    } else {
      // D2 labels are common words; the label signal is the lead's later triage record of the reviewed task.
      const triage = `${taskOf(r.id)} review follow-up`;
      row.triage = text.filter(f => f.text.includes(triage)).map(f => f.rp);
      row.refusedHandoff = text.filter(f => f.rp.startsWith('docs/team/handoffs/')
        && /round [1-9]/i.test(f.text.split('\n').slice(0, 3).join('\n'))).map(f => f.rp);
      row.optionA = text.some(f => isCode(f.rp)
        && !vocab.some(w => f.text.toLowerCase().includes(w)) && !f.text.includes(taskOf(r.id)));
    }
    const arms = { jev: r.jev?.choice, haiku: r.haiku?.choice, sonnet: r.sonnet?.choice };
    for (const [k, m] of Object.entries(cleanArms)) if (k.startsWith(`${set}:`)) arms[k.slice(3)] = m[r.id];
    row.right = Object.fromEntries(Object.entries(arms).map(([a, c]) => [a, c === undefined ? null : c === r.label]));
    return row;
  });

  const naming = per.filter(r => r.paths.length);
  const withBlob = per.filter(r => r.blobs);
  const distinct = new Set(per.flatMap(r => r.paths));
  const kinds = {};
  for (const p of distinct) { const k = obj(sha, resolvePath(p)).kind; kinds[k] = (kinds[k] ?? 0) + 1; }
  const s = out.sets[set] = { rows: per.length, naming: naming.length, withBlob: withBlob.length,
    distinct: [...distinct], kinds, fieldRows, rowsOut: per };

  say(`== ${set} (files at ${sha}) ==`);
  say(`rows ${per.length}; naming >=1 path ${naming.length}; with >=1 blob at ${sha} ${withBlob.length}; no path ${per.length - naming.length}`);
  say(`distinct paths ${distinct.size}: ${Object.entries(kinds).map(([k, n]) => `${k} ${n}`).join(', ')}`);
  say(`rows naming a path, per field: ${Object.entries(fieldRows).map(([k, n]) => `${k} ${n}`).join(', ')}`);
  const raw = withBlob.map(r => r.raw), esc = withBlob.map(r => r.escaped);
  say(`expansion per row with a blob (raw): median ${kb(median(raw))}, p90 ${kb(pct(raw, 0.9))}, max ${kb(Math.max(...raw))}`);
  say(`expansion per row (JSON-escaped, text blobs): median ${kb(median(esc))}, max ${kb(Math.max(...esc))}`);
  say(`rows over stateCap ${STATE_CAP} B raw: ${withBlob.filter(r => r.raw > STATE_CAP).length}; over bodyCap ${BODY_CAP} B escaped: ${withBlob.filter(r => r.escaped > BODY_CAP).length}`);
  if (set === 'd1') {
    const leaks = per.filter(r => r.labelLeak.length);
    say(`label leak (a named file at ${sha} contains the row's own class id): ${leaks.length} rows`);
    for (const r of leaks) say(`  ${r.id} label=${r.label} files=${r.labelLeak.join(',')} right=${JSON.stringify(r.right)}`);
    const dec = per.filter(r => r.decoys.length && !r.labelLeak.length);
    say(`decoy only (a named file holds another class id, none holds the row's own): ${dec.length} rows`);
    for (const r of dec) say(`  ${r.id} label=${r.label} ${r.decoys.join(' ')} right=${JSON.stringify(r.right)}`);
    say(`own incident id in a named file: ${per.filter(r => r.idLeak.length).length} rows`);
    say(`rows not in the ledger at ${SRC.d1}: ${per.filter(r => !r.at).map(r => r.id).join(',') || 'none'}`);
    const pc = withBlob.filter(r => r.postChanged.length);
    say(`rows with a blob naming a file changed after the incident's at and before ${SRC.d1}: ${pc.length} of ${withBlob.length}`);
    say(`at the per-row pin (last ${SRC.d1} ancestor before at): label leak ${per.filter(r => r.pinLabelLeak.length).length} rows (${per.filter(r => r.pinLabelLeak.length).map(r => `${r.id}:${r.pinLabelLeak.join(',')}`).join(' ')}), own id ${per.filter(r => r.pinIdLeak.length).length} rows`);
  } else {
    const tr = per.filter(r => r.triage.length);
    say(`lead triage record "<task> review follow-up(s)" in a named file: ${tr.length} rows`);
    for (const r of tr) say(`  ${r.id} label=${r.label} files=${r.triage.join(',')} right=${JSON.stringify(r.right)}`);
    say(`named handoff with a 'round N' header (refused review): ${per.filter(r => r.refusedHandoff.length).length} rows`);
    say(`rows with no Jev answer: ${per.filter(r => r.right.jev === null).length}`);
  }
  for (const arm of Object.keys(per[0].right)) {
    const a = naming.filter(r => r.right[arm] !== null), b = per.filter(r => !r.paths.length && r.right[arm] !== null);
    const ra = a.filter(r => r.right[arm]).length, rb = b.filter(r => r.right[arm]).length;
    const f = (n, d) => d ? `${n}/${d} (${(100 * n / d).toFixed(1)} %)` : `${n}/${d}`;
    say(`accuracy ${arm}: naming paths ${f(ra, a.length)} vs none ${f(rb, b.length)}`);
  }
  say(`Option A rows (a code-allowlisted, vocab-free text file kept${set === 'd1' ? ' at the per-row pin' : ` at ${sha}`}): ${per.filter(r => r.optionA).length}`);
}

const d1 = out.sets.d1, d2 = out.sets.d2;
const union = new Set([...d1.distinct, ...d2.distinct]);
const optA = d1.rowsOut.filter(r => r.optionA).length + d2.rowsOut.filter(r => r.optionA).length;
const pending = d2.rowsOut.filter(r => r.right.jev === null).length;
say('== both ==');
say(`distinct paths in both sets: ${union.size}`);
const sig = [d1.rowsOut.filter(r => r.labelLeak.length).length, d1.rowsOut.filter(r => r.decoys.length && !r.labelLeak.length).length,
  d2.rowsOut.filter(r => r.triage.length).length];
say(`rows with label signal in a named file: ${sig[0] + sig[1] + sig[2]} (d1 own class id ${sig[0]}, d1 decoy only ${sig[1]}, d2 triage record ${sig[2]})`);
say(`sends, Option A (changed rows only, + ${pending} pending d2): ${optA + pending}; Option B (every body changes): ${d1.rows + d2.rows}`);

console.log(lines.join('\n'));
if (args.json) {
  for (const s of Object.values(out.sets)) s.rowsOut = s.rowsOut.map(({ paths, ...r }) => ({ ...r, nPaths: paths.length }));
  fs.writeFileSync(args.json, JSON.stringify(out, null, 1));
}
