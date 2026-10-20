#!/usr/bin/env node
// math-pending.mjs: the declarations whose artifact math still has to be checked, split into batches.
//   node scripts/math-pending.mjs [--batches 4] [--out <dir>] [--json <mathview export>]
// TS stand-in (no Lean golden); the Lean model of a signoff is Fw.Ops.LeanFirst `Signoff.matches` (decl, stmtHash).
//
// Input 1, the export: `lake exe mathview` JSON (name, kind, module, line, stmtHash, ...), from --json <file>, else
//   from a fresh `lake exe mathview --out <tmp>` run in lean/.
// Input 2, the records: every research/notes/**/*-math-review-*.md and *-math-artifact-*.md table row whose first
//   cell is a backticked `Fw.*` name and whose next two cells hold a verdict (agree|disagree) and a stmtHash, in either
//   order: review rows `| decl | verdict | stmtHash | ... |`, artifact rows `| decl | stmtHash | agree | link |`
//   (docs/team/tools/math-artifact.md). Precedence: review records without `round:` (by file name), then numbered
//   review rounds (historical records of the retired per-round review; two records with one round fail), then artifact records (by file name, which starts with the
//   date); within a record the last row wins.
// Decision (per current entry e, latest row r):
//   signed           r.verdict = agree and r.stmtHash = e.stmtHash
//   new              no row
//   stale            r.verdict = agree, r.stmtHash differs (signed earlier, changed since)
//   unhashed         r.verdict = agree, the row lacks a stmtHash
//   disagree         r.verdict = disagree, r.stmtHash equal or missing (fix not landed yet)
//   disagree-changed r.verdict = disagree, r.stmtHash differs (fix landed, needs re-review)
//   pending = every entry that is not signed; the script asserts pending ∪ signed = all, pending ∩ signed = ∅ and
//   that the batches partition pending.
// Batching: group pending by module; a module with more than ceil(|pending| / N) entries is cut into chunks of that
//   size (in source-line order); chunks go largest first to the batch with the fewest entries (ties: module name,
//   then lowest batch). So a module stays in one batch unless it alone exceeds a fair share.
// Output: <out>/batch-<A..>.tsv, one line per entry `module<TAB>name<TAB>kind<TAB>stmtHash` (sorted by module, then
//   line; no header), and <out>/summary.json (HEAD, export source, totals, counts per module, batches, status per
//   pending entry). Default --out: ./math-pending
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

// ---- pure part (tested by scripts/test-math-pending.mjs) ----

/** Rows from records [{file, text}] -> Map name -> {verdict, stmtHash, file, round}. */
export function parseRecords(records) {
  const recs = records.map(({ file, text }) => {
    const front = /^---\n([\s\S]*?)\n---\n/.exec(text);
    const round = front && /^round:\s*(\d+)\s*$/m.exec(front[1]);
    return { file, text, artifact: /-math-artifact-[^/]*$/.test(file), round: round ? Number(round[1]) : null };
  });
  const seen = new Map();
  for (const r of recs) {
    if (r.round === null) continue;
    if (seen.has(r.round)) throw new Error(`records ${seen.get(r.round)} and ${r.file} both have round: ${r.round}`);
    seen.set(r.round, r.file);
  }
  const rank = (r) => (r.artifact ? Infinity : r.round ?? -1);
  recs.sort((a, b) => (rank(a) === rank(b) ? 0 : rank(a) < rank(b) ? -1 : 1) || (a.file < b.file ? -1 : a.file > b.file ? 1 : 0));
  const digits = (c) => { const h = (c || '').replace(/`/g, ''); return /^\d+$/.test(h) ? h : null; };
  const out = new Map();
  for (const { file, text, round } of recs) {
    for (const line of text.split('\n')) {
      const cells = line.split('|').map((c) => c.trim()).slice(1, -1);
      if (cells.length < 2) continue;
      const name = /^`(Fw\.[^`]+)`$/.exec(cells[0]);
      const verdictOf = (c) => /^\**(agree|disagree)\**$/i.exec(c ?? '');
      const at = verdictOf(cells[1]) ? 1 : verdictOf(cells[2]) ? 2 : 0;
      if (!name || !at) continue;
      const stmtHash = digits(cells[at === 1 ? 2 : 1]);
      out.set(name[1], { verdict: verdictOf(cells[at])[1].toLowerCase(), stmtHash, file, round });
    }
  }
  return out;
}

/** Status of one export entry given its latest row (or undefined). */
export function statusOf(e, r) {
  if (!r) return 'new';
  const same = r.stmtHash !== null && r.stmtHash === String(e.stmtHash);
  const changed = r.stmtHash !== null && r.stmtHash !== String(e.stmtHash);
  if (r.verdict === 'agree') return same ? 'signed' : changed ? 'stale' : 'unhashed';
  return changed ? 'disagree-changed' : 'disagree';
}

/** Split items [{module, line, ...}] into n batches (see the header). Returns arrays of items. */
export function makeBatches(items, n) {
  if (!(n >= 1)) throw new Error('batches must be >= 1');
  const cap = Math.max(1, Math.ceil(items.length / n));
  const byMod = new Map();
  for (const it of items) (byMod.get(it.module) ?? byMod.set(it.module, []).get(it.module)).push(it);
  const chunks = [];
  for (const mod of [...byMod.keys()].sort()) {
    const xs = byMod.get(mod).slice().sort((a, b) => a.line - b.line || (a.name < b.name ? -1 : 1));
    for (let i = 0; i < xs.length; i += cap) chunks.push({ mod, xs: xs.slice(i, i + cap) });
  }
  chunks.sort((a, b) => b.xs.length - a.xs.length || (a.mod < b.mod ? -1 : a.mod > b.mod ? 1 : 0));
  const out = Array.from({ length: n }, () => []);
  for (const c of chunks) {
    let k = 0;
    for (let j = 1; j < n; j++) if (out[j].length < out[k].length) k = j;
    out[k].push(...c.xs);
  }
  for (const b of out) b.sort((a, c) => (a.module < c.module ? -1 : a.module > c.module ? 1 : a.line - c.line));
  return out;
}

/** The whole decision: entries + rows -> {statuses, signed, pending, batches}; throws if an invariant fails. */
export function decide(entries, rows, n) {
  const names = entries.map((e) => e.name);
  if (new Set(names).size !== names.length) throw new Error('duplicate names in the mathview export');
  const status = new Map(entries.map((e) => [e.name, statusOf(e, rows.get(e.name))]));
  const signed = entries.filter((e) => status.get(e.name) === 'signed');
  const pending = entries.filter((e) => status.get(e.name) !== 'signed');
  const batches = makeBatches(pending, n);
  // invariants: pending ∪ signed = all, pending ∩ signed = ∅, batches partition pending
  const S = new Set(signed.map((e) => e.name));
  const P = new Set(pending.map((e) => e.name));
  if (S.size + P.size !== names.length || names.some((x) => S.has(x) === P.has(x))) throw new Error('signed/pending is not a partition');
  const B = batches.flat().map((e) => e.name);
  if (B.length !== P.size || new Set(B).size !== B.length || B.some((x) => !P.has(x))) throw new Error('batches are not a partition of pending');
  return { status, signed, pending, batches };
}

export const batchId = (i) => (i < 26 ? String.fromCharCode(65 + i) : `Z${i - 25}`);
export const tsvLine = (e) => [e.module, e.name, e.kind, e.stmtHash].join('\t');

// ---- I/O ----

function loadExport(jsonArg) {
  if (jsonArg) return { source: relative(root, resolve(jsonArg)) || jsonArg, entries: JSON.parse(readFileSync(jsonArg, 'utf8')) };
  const dir = mkdtempSync(join(tmpdir(), 'math-pending-'));
  try {
    const f = join(dir, 'export.json');
    execFileSync('lake', ['exe', 'mathview', '--out', f], { cwd: join(root, 'lean'), stdio: ['ignore', 'inherit', 'inherit'] });
    return { source: 'lake exe mathview', entries: JSON.parse(readFileSync(f, 'utf8')) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function readRecords() {
  const notes = join(root, 'research/notes');
  const files = [];
  for (const year of existsSync(notes) ? readdirSync(notes).sort() : []) {
    try {
      for (const f of readdirSync(join(notes, year)).sort()) if (/-math-(review|artifact)-.*\.md$/.test(f)) files.push(join(notes, year, f));
    } catch { /* not a folder */ }
  }
  return files.map((f) => ({ file: relative(root, f), text: readFileSync(f, 'utf8') }));
}

function main(argv) {
  const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
  const n = Number(opt('--batches', '4'));
  const out = resolve(opt('--out', 'math-pending'));
  const { source, entries } = loadExport(opt('--json', null));
  const records = readRecords();
  const rows = parseRecords(records);
  const { status, signed, pending, batches } = decide(entries, rows, n);
  const git = (a) => { try { return execFileSync('git', a, { cwd: root, encoding: 'utf8' }).trim(); } catch { return null; } };
  const STATUSES = ['signed', 'new', 'stale', 'unhashed', 'disagree', 'disagree-changed'];
  const zero = () => Object.fromEntries([['all', 0], ...STATUSES.map((s) => [s, 0]), ['pending', 0]]);
  const totals = zero();
  const modules = {};
  for (const e of entries) {
    const s = status.get(e.name);
    const m = (modules[e.module] ??= zero());
    for (const t of [totals, m]) { t.all++; t[s]++; if (s !== 'signed') t.pending++; }
  }
  mkdirSync(out, { recursive: true });
  const bs = batches.map((b, i) => {
    const id = batchId(i);
    writeFileSync(join(out, `batch-${id}.tsv`), b.map((e) => `${tsvLine(e)}\n`).join(''));
    return { id, file: `batch-${id}.tsv`, count: b.length, modules: [...new Set(b.map((e) => e.module))] };
  });
  const summary = {
    head: git(['rev-parse', 'HEAD']),
    dirty: Boolean(git(['status', '--porcelain', '--', 'lean', 'research/notes'])),
    export: source, records: records.map((r) => r.file), batchesRequested: n,
    totals, signed: signed.length,
    modules: Object.fromEntries(Object.entries(modules).sort(([a], [b]) => (a < b ? -1 : 1))),
    batches: bs,
    pending: pending.map((e) => ({ name: e.name, module: e.module, status: status.get(e.name), lastRecord: rows.get(e.name)?.file ?? null })),
  };
  writeFileSync(join(out, 'summary.json'), `${JSON.stringify(summary, null, 1)}\n`);
  const t = totals;
  console.log(`${t.all} entries: ${t.signed} signed, ${t.pending} pending (new ${t.new}, stale ${t.stale}, unhashed ${t.unhashed}, disagree ${t.disagree}, disagree-changed ${t['disagree-changed']})`);
  const shown = relative(process.cwd(), out); console.log(`batches: ${bs.map((b) => `${b.id}=${b.count}`).join(' ')} -> ${shown.startsWith('..') ? out : shown || '.'}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
