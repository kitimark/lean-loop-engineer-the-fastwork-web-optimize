// Engine premise verdicts (task engine-premise-measure). A TS port of Fw.Ops.EnginePremise (lean/Fw/Ops/EnginePremise.lean):
// the cell and verdict functions below are checked against the Lean-generated golden vectors in
// packages/contracts/golden/ops/engine-premises.jsonl (test/premise.test.mjs). The expectations are NOT written here: every
// step's expected presence per stage comes from the golden, which Lean computes from the engine models.
//
//   node src/premise-verdict.mjs --engine chromium|webkit --out verdict.json  counts-r1.json counts-r2.json ...
//
// A pass is one run on its own CI job: its counts.json (fw.counts/1) holds frames[n].counts, frame n = step n of the golden.
// Pure module apart from the CLI at the bottom.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
export const GOLDEN_PATH = resolve(HERE, '..', '..', 'contracts', 'golden', 'ops', 'engine-premises.jsonl');

/** Parse the golden: rows by kind. */
export function loadGolden(path = GOLDEN_PATH) {
  const rows = readFileSync(path, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
  const by = (k) => rows.filter((r) => r.kind === k);
  const eng = (k, e) => by(k).filter((r) => r.engine === e);
  return {
    page: by('page')[0],
    observers: { chromium: eng('observer', 'chromium'), webkit: eng('observer', 'webkit') },
    steps: { chromium: eng('step', 'chromium').sort((a, b) => a.step - b.step), webkit: eng('step', 'webkit').sort((a, b) => a.step - b.step) },
    excluded: { chromium: eng('excluded', 'chromium'), webkit: eng('excluded', 'webkit') },
    cellVectors: by('cell'),
    verdictVectors: by('verdict'),
  };
}

/** Lean `cell`: the model's expected presence against the observed presences of all passes. */
export function cell(expect, observed) {
  if (observed.length === 0) return 'missing';
  if (observed.every((o) => o === expect)) return 'agree';
  if (observed.every((o) => o !== expect)) return 'mismatch';
  return 'unstable';
}

/** Lean `verdict`: fails if some cell is a mismatch; holds if there is a cell and all agree; else inconclusive. */
export function verdict(cells) {
  if (cells.some((c) => c === 'mismatch')) return 'fails';
  if (cells.length > 0 && cells.every((c) => c === 'agree')) return 'holds';
  return 'inconclusive';
}

/** Observed presence of an observer in one frame: the sum of its counters is positive. */
export function present(observer, counts) {
  let s = 0;
  for (const k of observer.counters) s += +(counts?.[k] ?? 0);
  return s > 0;
}

/**
 * Evaluate one engine. `passes` is a list of runs; each run is a list of per-step counts objects (index = step).
 * Returns { stages: { <stage>: { verdict, cells: {agree, mismatch, unstable, missing}, offending: [...] } } }.
 */
export function evaluate(golden, engine, passes) {
  const steps = golden.steps[engine];
  const stages = {};
  for (const o of golden.observers[engine]) {
    const tally = { agree: 0, mismatch: 0, unstable: 0, missing: 0 };
    const offending = [];
    const cells = [];
    for (const st of steps) {
      const expect = st.expect[o.stage];
      const observed = passes.filter((p) => p[st.step] !== undefined).map((p) => present(o, p[st.step]));
      const c = cell(expect, observed);
      cells.push(c);
      tally[c]++;
      if (c !== 'agree') offending.push({ step: st.step, case: st.case, act: st.act, expect, observed, cell: c });
    }
    stages[o.stage] = { verdict: verdict(cells), cells: tally, counters: o.counters, offending };
  }
  return { engine, passes: passes.length, steps: steps.length, stages };
}

/** A pass file to per-step counts objects: Chromium counts.json (fw.counts/1) and WKTR counts-live-<pass>.json (fw.wktr.scroll/1) both hold frames[n].counts, frame n = step n. */
export function chromiumPass(countsJson) {
  return countsJson.frames.filter((f) => f.phase !== 'warm').map((f) => f.counts); // 'warm' frames (profile segment) are the driver's, not steps
}

/** A markdown report of one evaluation (the CI step summary): a verdict table, then the cells that do not agree. */
export function toMarkdown(r) {
  const out = [`### ${r.engine}: ${r.passes} passes, ${r.steps} steps`, '', '| stage | verdict | agree | mismatch | unstable | missing |', '|---|---|---|---|---|---|'];
  for (const [s, v] of Object.entries(r.stages)) out.push(`| ${s} | ${v.verdict} | ${v.cells.agree} | ${v.cells.mismatch} | ${v.cells.unstable} | ${v.cells.missing} |`);
  for (const [s, v] of Object.entries(r.stages)) {
    if (v.offending.length === 0) continue;
    out.push('', `#### ${s} (${v.counters.join(', ')}): cells that do not agree`, '', '| step | case | act | model | observed (per pass) | cell |', '|---|---|---|---|---|---|');
    for (const o of v.offending) out.push(`| ${o.step} | ${o.case} | ${o.act} | ${o.expect ? 'runs' : 'absent'} | ${o.observed.map((x) => (x ? 'runs' : 'absent')).join(', ')} | ${o.cell} |`);
  }
  return out.join('\n') + '\n';
}

// ---- CLI
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const argv = process.argv.slice(2);
  const opt = (n, d) => { const i = argv.indexOf(`--${n}`); return i >= 0 ? argv[i + 1] : d; };
  const engine = opt('engine', 'chromium');
  const out = opt('out', null);
  const golden = loadGolden(opt('golden', GOLDEN_PATH));
  const files = argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1].startsWith('--')));
  if (!['chromium', 'webkit'].includes(engine)) { console.error('--engine must be chromium or webkit'); process.exit(2); }
  if (files.length === 0) { console.error('no counts.json given'); process.exit(2); }
  const passes = files.map((f) => chromiumPass(JSON.parse(readFileSync(f, 'utf8'))));
  for (const [i, p] of passes.entries()) if (p.length !== golden.steps[engine].length) { console.error(`${files[i]}: ${p.length} frames, golden has ${golden.steps[engine].length} steps`); process.exit(3); }
  const r = evaluate(golden, engine, passes);
  const lines = Object.entries(r.stages).map(([s, v]) => `${engine}.${s}: ${v.verdict} (agree ${v.cells.agree}, mismatch ${v.cells.mismatch}, unstable ${v.cells.unstable}, missing ${v.cells.missing})`);
  console.log(lines.join('\n'));
  if (out) writeFileSync(out, JSON.stringify(r, null, 1) + '\n');
  const md = opt('md', null);
  if (md) writeFileSync(md, toMarkdown(r));
}
