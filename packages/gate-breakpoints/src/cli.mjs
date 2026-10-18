// node src/cli.mjs run     --engine chromium|playwright-webkit|both --out out/<label> [--concurrency 4] [--probes id,block,...] [--sweeps id,...|none]
//                          [--parts engine.scroll,nav.hitTest,hero.countdown,hero.exit]   (pilot part ids of src/anchors.json; default all)
// node src/cli.mjs gaps    run|summary|device-serve|device-judge --out out/<label>   (the Q33 gaps lane; src/gaps/README.md)
// node src/cli.mjs summary --out out/<label> [--parts id,...]   (reads <engine>.json files there, writes summary.json and summary.md;
//   --parts narrows the verdict to those parts, which the run must have covered; a narrowed run names covered and skipped parts)
//   `summary` prints one verdict line per engine and exits 0 only when every engine passed (Lean Fw.Gate.Exit): an engine passes
//   only if EVERY cell passed or is excused by a Lean-registered exemption, and no sample is unsettled. The exemptions are printed.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { PKG } from './serve.mjs';

// TS stand-in for Lean Fw.Gate.Exit (lean/Fw/Gate/Exit.lean): checked against packages/contracts/golden/gate/exit.jsonl
// by test/exit.test.mjs. Replace by an fwcore op when one is wired. It holds no list of its own: the exemptions are read from
// the golden bytes Lean generates (Fw.Gate.Exit.exemptions).
export const EXIT_GOLDEN = resolve(PKG, '../contracts/golden/gate/exit.jsonl');
let registry = null;
/** The allowlist and the narrowed-run excuse, from the Lean-generated golden file (Lean exemptionLine, narrowedLine). */
export function loadRegistry(path = EXIT_GOLDEN) {
  if (path === EXIT_GOLDEN && registry) return registry;
  const lines = readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  const r = { exemptions: lines.filter((l) => l.kind === 'exemption'), narrowedId: lines.find((l) => l.kind === 'narrowed')?.id };
  if (r.exemptions.length === 0 || r.narrowedId === undefined) throw new Error(`no exemption registry in ${path}`);
  if (path === EXIT_GOLDEN) registry = r;
  return r;
}
const VERDICT_NAMES = (n) => ['pass', 'fail', 'not-comparable'].includes(n) || /^unreachable:(primary-pair|whole-width|width-dpr)$/.test(n);
/** Lean Fw.Gate.Exit.tableCellOfWire: a cell from its wire names; an unknown verdict name is an error, never a pass. */
export function tableCellOfWire(row, col, name) {
  if (name === 'not-run') return { row, col, v: null };
  if (!VERDICT_NAMES(name)) throw new Error(`unknown verdict ${name}`);
  return { row, col, v: name };
}
/** Lean Fw.Gate.Exit.excuse: the id that excuses a cell, or null. A not-run cell is excused only by a narrowed run. */
export function excuse(engine, narrowed, c, reg = loadRegistry()) {
  if (c.v === null) return narrowed ? reg.narrowedId : null;
  const x = reg.exemptions.find((e) => e.engine === engine && e.col === c.col && e.verdict === c.v && (e.row === null || e.row === c.row));
  return x ? x.id : null;
}
/** Lean Fw.Gate.Exit.TableCell.ok: a cell passed or is excused. */
export const cellOk = (engine, narrowed, c, reg) => c.v === 'pass' || excuse(engine, narrowed, c, reg) !== null;
/** The exit code from the verdicts of the judged engines: 0 only when there is one and every one passed (Lean exitCode). */
export function exitCode(verdicts) {
  return verdicts.length > 0 && verdicts.every((v) => v === 'pass') ? 0 : 1;
}
/** Lean Fw.Gate.Exit.outcomeOfWire: a wait outcome is unsettled when it is 'unsettled' or 'missing' (no wait was recorded). */
export function waitUnsettled(o) {
  if (o === 'unsettled' || o === 'missing') return true;
  if (/^settled@[0-9]+$/.test(o)) return false;
  throw new Error(`unknown outcome ${o}`);
}
/**
 * Lean Fw.Gate.Exit.engineVerdictCW: the verdict of one engine from the wire names of its table cells ([row, col, verdict]) and
 * of its samples' wait outcomes (one [orig, rewrite] pair per probe or sweep stop). The cells are read first, in order, then the
 * waits; the first unknown name throws. Unsettled samples are counted from the waits themselves, never from a flag the page set.
 * Returns the verdict, the unsettled count, the excused cells ([id, 'row|col']) and the cells that are neither a pass nor excused.
 */
export function engineVerdictCells(engine, narrowed, cells, waits, reg = loadRegistry()) {
  const cs = cells.map(([row, col, name]) => tableCellOfWire(row, col, name));
  const ws = waits.map(([a, b]) => { const x = waitUnsettled(a); return waitUnsettled(b) || x; });
  const unsettled = ws.filter(Boolean).length;
  const exempt = cs.flatMap((c) => { const id = excuse(engine, narrowed, c, reg); return id === null ? [] : [[id, `${c.row}|${c.col}`]]; });
  const bad = cs.filter((c) => !cellOk(engine, narrowed, c, reg)).map((c) => `${c.row}|${c.col}: ${c.v ?? 'not-run'}`);
  let verdict;
  if (cs.some((c) => c.v === 'fail')) verdict = 'fail';
  else if (unsettled > 0) verdict = 'unsettled';
  else if (bad.length > 0) verdict = 'incomplete';
  else if (cs.some((c) => c.v === 'pass')) verdict = 'pass';
  else verdict = 'notRendered';
  return { verdict, unsettled, exempt, bad };
}
/**
 * Verdict of one engine of summary.json: its table cells, and its samples (probes and sweep stops) whose settle wait ended
 * unsettled on an arm or was not recorded. A row without `wait` (a summary from before the wait) is read as missing, so as unsettled.
 * The run is narrowed when the engine record carries `parts`.
 */
export function engineOfSummary(name, e, reg = loadRegistry()) {
  const cells = Object.entries(e.table).flatMap(([row, cols]) => Object.entries(cols).map(([col, t]) => [row, col, t.verdict]));
  const pair = (x) => [x.wait?.orig ?? 'missing', x.wait?.rewrite ?? 'missing'];
  const waits = [...e.probes.map(pair), ...(e.sweeps ?? []).flatMap((sw) => sw.stops.map(pair))];
  return { cells, ...engineVerdictCells(name, e.parts !== undefined, cells, waits, reg) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();

async function main() {
const argv = process.argv.slice(2);
const cmd = argv[0];
const arg = (n, d) => { const i = argv.indexOf(`--${n}`); return i < 0 ? d : argv[i + 1]; };
const out = resolve(PKG, arg('out', 'out/run'));
// --parts a,b: undefined = all parts; an empty value is an error (selectParts throws), never "all".
const partsOpt = argv.includes('--parts') ? arg('parts', '').split(',').map((x) => x.trim()).filter(Boolean) : null;

if (cmd === 'run') {
  const { runEngine } = await import('./run.mjs');
  const e = arg('engine', 'both');
  const engines = e === 'both' ? ['chromium', 'playwright-webkit'] : [e];
  const list = (v) => (v === undefined ? null : v === 'none' ? [] : v.split(','));
  for (const engineName of engines) {
    await runEngine({ engineName, outDir: out, concurrency: Number(arg('concurrency', '4')), probeFilter: list(arg('probes')), sweepFilter: list(arg('sweeps')), partFilter: partsOpt });
  }
  process.exit(0); // the engines are closed; leftover handles (keep-alive sockets) must not hold the process
} else if (cmd === 'summary') {
  const { summarize } = await import('./summary.mjs');
  const result = summarize(out, { parts: partsOpt });
  const names = Object.keys(result.engines);
  const reg = loadRegistry();
  const judged = names.map((n) => ({ n, ...engineOfSummary(n, result.engines[n], reg) }));
  for (const j of judged) {
    const count = (v) => j.cells.filter((c) => c[2] === v).length;
    console.log(`gate verdict ${j.n}: ${j.verdict} (cells: ${j.cells.length} total, ${count('pass')} pass, ${count('fail')} fail, ${j.exempt.length} excused, ${j.bad.length} not ok; unsettled samples: ${j.unsettled})`);
    for (const id of [...new Set(j.exempt.map((x) => x[0]))]) {
      const x = reg.exemptions.find((e) => e.id === id);
      console.log(`  excused ${id}: ${j.exempt.filter((y) => y[0] === id).length} cells${x ? ` (${x.verdict}; premise ${x.premise})` : ''}`);
    }
    for (const b of j.bad.slice(0, 20)) console.log(`  not ok: ${b}`);
    if (j.bad.length > 20) console.log(`  ... ${j.bad.length - 20} more not ok`);
  }
  if (judged.length === 0) console.log('gate verdict: no engine file in --out, nothing judged');
  process.exitCode = exitCode(judged.map((j) => j.verdict));
} else if (cmd === 'gaps') {
  // the gaps lane (src/gaps/): the Q33 cells, fractional widths and hover x pointer; see src/gaps/README.md
  const { gapsMain } = await import('./gaps/cli.mjs');
  await gapsMain(argv.slice(1), out);
  process.exit(0);
} else {
  console.error('usage: cli.mjs run|summary --out DIR [...]');
  process.exit(2);
}
}
