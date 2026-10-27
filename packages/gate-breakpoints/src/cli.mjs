// node src/cli.mjs run     --engine chromium|playwright-webkit|both --out out/<label> [--concurrency 4] [--probes id,block,...] [--sweeps id,...|none]
//                          [--parts engine.scroll,nav.hitTest,hero.countdown,hero.exit]   (pilot part ids of src/anchors.json; default all)
// node src/cli.mjs flip    --engine chromium|playwright-webkit|both --fw morph.geom:on --out out/flip
// node src/cli.mjs gaps    run|summary|device-serve|device-judge --out out/<label>   (the Q33 gaps lane; src/gaps/README.md)
// node src/cli.mjs summary --out out/<label> [--parts id,...]   (reads <engine>.json files there, writes summary.json, summary.md and
//   readings-<engine>.json; --parts narrows the verdict to those parts, which the run must have covered; a narrowed run names covered
//   and skipped parts and never exits 0)
//   `summary` prints one verdict line and one readings line per engine and exits 0 only when the run is not narrowed and every engine
//   passed (Lean Fw.Gate.Exit.runExit): an engine passes only if its readings are exactly the Lean universe (rows x columns x reading
//   ids), EVERY reading passed or is excused by a Lean-registered exemption that lists it, and no sample is unsettled.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { PKG } from './serve.mjs';

// TS stand-in for Lean Fw.Gate.Exit (lean/Fw/Gate/Exit.lean): checked against packages/contracts/golden/gate/exit.jsonl
// by test/exit.test.mjs. Replace by an fwcore op when one is wired. It holds no list of its own: the exemptions and the universe are
// read from the golden bytes Lean generates (Fw.Gate.Exit.exemptions, Fw.Gate.Exit.gateUniverse).
export const EXIT_GOLDEN = resolve(PKG, '../contracts/golden/gate/exit.jsonl');
let registry = null;
/** The allowlist, the universe and the narrowed-run excuse, from the Lean-generated golden file (Lean exemptionLine, universeLine,
 * narrowedLine). The universe is every (row, column, reading id) of the table; its size must be the size Lean states. */
export function loadRegistry(path = EXIT_GOLDEN) {
  if (path === EXIT_GOLDEN && registry) return registry;
  const lines = readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  const u = lines.find((l) => l.kind === 'universe');
  const r = { exemptions: lines.filter((l) => l.kind === 'exemption'), narrowedId: lines.find((l) => l.kind === 'narrowed')?.id };
  if (r.exemptions.length === 0 || r.narrowedId === undefined || u === undefined) throw new Error(`no exemption registry in ${path}`);
  r.universe = u.rows.flatMap((row) => u.cols.flatMap(([col, ids]) => ids.map((id) => [row, col, id])));
  if (r.universe.length !== u.size) throw new Error(`universe in ${path}: ${r.universe.length} keys, Lean states ${u.size}`);
  if (path === EXIT_GOLDEN) registry = r;
  return r;
}
const VERDICT_NAMES = (n) => ['pass', 'fail', 'not-comparable'].includes(n) || /^unreachable:(primary-pair|whole-width|width-dpr)$/.test(n);
/** Lean Fw.Gate.Exit.tableCellOfWire: a cell from its wire form (row, column, [[reading id, verdict name]]); no reading is a block that
 * was not run; an unknown verdict name is an error, never a pass. */
export function tableCellOfWire(row, col, readings) {
  return { row, col, readings: readings.map(([id, name]) => { if (!VERDICT_NAMES(name)) throw new Error(`unknown verdict ${name}`); return { id, v: name }; }) };
}
/** Lean Fw.Gate.Exit.excuseReading: the id of the first exemption that names the reading, or null (Exemption.matches: the same
 * engine, column and verdict, a row the exemption lists and a reading id it lists; there is no wildcard). */
export function excuseReading(engine, row, col, r, reg = loadRegistry()) {
  const x = reg.exemptions.find((e) => e.engine === engine && e.col === col && e.verdict === r.v && e.rows.includes(row) && e.ids.includes(r.id));
  return x ? x.id : null;
}
/** Lean Fw.Gate.Exit.Reading.ok: a reading passed or is excused. */
export const readingOk = (engine, row, col, r, reg) => r.v === 'pass' || excuseReading(engine, row, col, r, reg) !== null;
/** Lean Fw.Gate.Exit.TableCell.ok (rollup_pass_iff_all_readings): a cell with no reading is ok only in a narrowed run, any other cell
 * only when EVERY reading is ok. */
export const cellOk = (engine, narrowed, c, reg) => (c.readings.length === 0 ? narrowed : c.readings.every((r) => readingOk(engine, c.row, c.col, r, reg)));
/** Lean Fw.Gate.Exit.cellExcuses: [excuse id, 'row|col', reading id] for each excused reading of the cell. */
export function cellExcuses(engine, narrowed, c, reg = loadRegistry()) {
  if (c.readings.length === 0) return narrowed ? [[reg.narrowedId, `${c.row}|${c.col}`, '']] : [];
  return c.readings.flatMap((r) => { const id = excuseReading(engine, c.row, c.col, r, reg); return id === null ? [] : [[id, `${c.row}|${c.col}`, r.id]]; });
}
/** The exit code from the verdicts of the judged engines: 0 only when there is one and every one passed (Lean exitCode). */
export function exitCode(verdicts) {
  return verdicts.length > 0 && verdicts.every((v) => v === 'pass') ? 0 : 1;
}
/** Lean Fw.Gate.Exit.runExit: a run narrowed by the `--parts` flag exits 1, whatever its verdicts; any other run exits exitCode. */
export const runExit = (narrowed, verdicts) => (narrowed ? 1 : exitCode(verdicts));
/** Lean Fw.Gate.Exit.wireKeys: the [row, col, reading id] keys of wire cells, cell by cell, reading by reading. */
export const wireKeys = (cells) => cells.flatMap(([row, col, readings]) => readings.map(([id]) => [row, col, id]));
/**
 * Lean List.isPerm on keys: whether `keys` is a permutation of `universe` (each key as often as in the universe, nothing else).
 * Returns the keys the run lacks and the keys it has beyond the universe (a doubled key counts once more each time).
 */
export function universeDiff(keys, universe) {
  const count = new Map();
  for (const k of universe) { const s = JSON.stringify(k); count.set(s, (count.get(s) ?? 0) + 1); }
  const extra = [];
  for (const k of keys) { const s = JSON.stringify(k); const n = count.get(s) ?? 0; if (n === 0) extra.push(k); else count.set(s, n - 1); }
  const missing = [...count].flatMap(([s, n]) => Array(n).fill(JSON.parse(s)));
  return { missing, extra, identical: missing.length === 0 && extra.length === 0 };
}
/** Lean Fw.Gate.Exit.outcomeOfWire: a wait outcome is unsettled when it is 'unsettled' or 'missing' (no wait was recorded). */
export function waitUnsettled(o) {
  if (o === 'unsettled' || o === 'missing') return true;
  if (/^settled@[0-9]+$/.test(o)) return false;
  throw new Error(`unknown outcome ${o}`);
}
/**
 * Lean Fw.Gate.Exit.engineVerdictUW: the verdict of one engine, against the universe (a list of [row, col, reading id] keys), from the
 * wire form of its table cells ([row, col, [[reading id, verdict name]]]) and of its samples' wait outcomes (one [orig, rewrite] pair
 * per probe or sweep stop). The cells are read first, in order, then the waits; the first unknown name throws. A run that is not
 * narrowed is `refused` unless its keys are a permutation of the universe. Unsettled samples are counted from the waits themselves,
 * never from a flag the page set. Returns the verdict, the unsettled count, the excused readings ([id, 'row|col', reading id], Lean
 * cellExcuses), the cells that have a reading which is neither a pass nor excused, and the universe difference.
 */
export function engineVerdictCells(engine, narrowed, cells, waits, universe, reg = loadRegistry()) {
  if (!Array.isArray(universe)) throw new Error('engineVerdictCells: the universe is required');
  const cs = cells.map(([row, col, readings]) => tableCellOfWire(row, col, readings));
  const ws = waits.map(([a, b]) => { const x = waitUnsettled(a); return waitUnsettled(b) || x; });
  const unsettled = ws.filter(Boolean).length;
  const exempt = cs.flatMap((c) => cellExcuses(engine, narrowed, c, reg));
  const bad = cs.filter((c) => !cellOk(engine, narrowed, c, reg)).map((c) => (c.readings.length === 0
    ? `${c.row}|${c.col}: not-run`
    : `${c.row}|${c.col}: ${c.readings.filter((r) => !readingOk(engine, c.row, c.col, r, reg)).map((r) => `${r.id} ${r.v}`).join(', ')}`));
  const diff = universeDiff(wireKeys(cells), universe);
  const isFail = (c) => c.readings.some((r) => r.v === 'fail' && excuseReading(engine, c.row, c.col, r, reg) === null);
  const isPass = (c) => c.readings.some((r) => r.v === 'pass');
  let verdict;
  if (!narrowed && !diff.identical) verdict = 'refused';
  else if (cs.some(isFail)) verdict = 'fail';
  else if (unsettled > 0) verdict = 'unsettled';
  else if (bad.length > 0) verdict = 'incomplete';
  else if (cs.some(isPass)) verdict = 'pass';
  else verdict = 'notRendered';
  return { verdict, unsettled, exempt, bad, diff };
}
/**
 * Verdict of one engine of summary.json: its table cells with their readings (one per probe or sweep stop, `table[row][col].readings`),
 * and its samples (probes and sweep stops) whose settle wait ended unsettled on an arm or was not recorded. A row without `wait` (a
 * summary from before the wait) is read as missing, so as unsettled. `narrowed` is the run's `--parts` flag, never a field of the
 * engine record: a record narrowed by its run but judged without the flag lacks keys of the universe and is refused.
 */
export function engineOfSummary(name, e, narrowed, reg = loadRegistry()) {
  if (typeof narrowed !== 'boolean') throw new Error('engineOfSummary: narrowed must be the --parts flag (a boolean)');
  const cells = Object.entries(e.table).flatMap(([row, cols]) => Object.entries(cols).map(([col, t]) => [row, col, t.readings.map((r) => [r.id, r.verdict])]));
  const pair = (x) => [x.wait?.orig ?? 'missing', x.wait?.rewrite ?? 'missing'];
  const waits = [...e.probes.map(pair), ...(e.sweeps ?? []).flatMap((sw) => sw.stops.map(pair))];
  return { cells, ...engineVerdictCells(name, narrowed, cells, waits, reg.universe, reg) };
}
/**
 * The per-reading table of one judged engine: one [row, col, reading id, verdict name, status] row per reading, sorted, where the
 * status is `pass`, `excused:<exemption id>` or `bad`; and its counts. Byte-identical tables mean the same readings and verdicts.
 */
export function readingsTable(engine, cells, reg = loadRegistry()) {
  const rows = cells.flatMap(([row, col, readings]) => readings.map(([id, v]) => {
    const x = v === 'pass' ? null : excuseReading(engine, row, col, { id, v }, reg);
    return [row, col, id, v, v === 'pass' ? 'pass' : x !== null ? `excused:${x}` : 'bad'];
  }));
  rows.sort((a, b) => { const s = JSON.stringify(a.slice(0, 3)); const t = JSON.stringify(b.slice(0, 3)); return s < t ? -1 : s > t ? 1 : 0; });
  const n = (p) => rows.filter((r) => p(r[4])).length;
  return { rows, total: rows.length, pass: n((s) => s === 'pass'), excused: n((s) => s.startsWith('excused:')), bad: n((s) => s === 'bad') };
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
  const narrowed = partsOpt !== null;
  const result = summarize(out, { parts: partsOpt });
  const names = Object.keys(result.engines);
  const reg = loadRegistry();
  const judged = names.map((n) => ({ n, ...engineOfSummary(n, result.engines[n], narrowed, reg) }));
  for (const j of judged) {
    const readings = j.cells.flatMap((c) => c[2]);
    const count = (v) => readings.filter((r) => r[1] === v).length;
    console.log(`gate verdict ${j.n}: ${j.verdict} (cells: ${j.cells.length}, readings: ${readings.length} total, ${count('pass')} pass, ${count('fail')} fail, ${j.exempt.length} excused, ${j.bad.length} cells not ok; unsettled samples: ${j.unsettled})`);
    const t = readingsTable(j.n, j.cells, reg);
    const bytes = `${JSON.stringify(t.rows)}\n`;
    writeFileSync(join(out, `readings-${j.n}.json`), bytes);
    const u = j.diff.identical ? 'identical' : `differs (missing ${j.diff.missing.length}, extra ${j.diff.extra.length})`;
    console.log(`gate readings ${j.n}: total ${t.total}, pass ${t.pass}, excused ${t.excused}, bad ${t.bad}; universe ${reg.universe.length}: ${u}; narrowed: ${narrowed}; table sha256 ${createHash('sha256').update(bytes).digest('hex')}`);
    for (const k of j.diff.missing.slice(0, 10)) console.log(`  missing reading: ${k.join(' | ')}`);
    for (const k of j.diff.extra.slice(0, 10)) console.log(`  extra reading: ${k.join(' | ')}`);
    for (const id of [...new Set(j.exempt.map((x) => x[0]))]) {
      const x = reg.exemptions.find((e) => e.id === id);
      console.log(`  excused ${id}: ${j.exempt.filter((y) => y[0] === id).length} readings${x ? ` (${x.verdict}; premise ${x.premise})` : ''}`);
      const byCell = new Map();
      for (const y of j.exempt.filter((z) => z[0] === id)) byCell.set(y[1], [...(byCell.get(y[1]) ?? []), y[2]]);
      for (const [cellId, ids] of byCell) console.log(`    excused ${cellId}: ${ids.join(' ')}`);
    }
    for (const b of j.bad.slice(0, 20)) console.log(`  not ok: ${b}`);
    if (j.bad.length > 20) console.log(`  ... ${j.bad.length - 20} more not ok`);
  }
  if (judged.length === 0) console.log('gate verdict: no engine file in --out, nothing judged');
  if (narrowed) console.log('gate verdict: narrowed by --parts, so the run never exits 0 (Lean narrowed_never_zero)');
  process.exitCode = runExit(narrowed, judged.map((j) => j.verdict));
} else if (cmd === 'flip') {
  const { runFlipCell } = await import('./flip-cell.mjs');
  const e = arg('engine', 'both');
  const engines = e === 'both' ? ['chromium', 'playwright-webkit'] : [e];
  const bands = argv.includes('--bands') ? arg('bands', '').split(',') : null;
  let ok = true;
  for (const engineName of engines) ok = (await runFlipCell({ engineName, fw: arg('fw', 'morph.geom:on'), outDir: out, bandFilter: bands })) && ok;
  process.exit(ok ? 0 : 1);
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
