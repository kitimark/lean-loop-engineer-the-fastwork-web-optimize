// node src/cli.mjs run     --engine chromium|playwright-webkit|both --out out/<label> [--concurrency 4] [--probes id,block,...] [--sweeps id,...|none]
//                          [--parts engine.scroll,nav.hitTest,hero.countdown,hero.exit]   (pilot part ids of src/anchors.json; default all)
// node src/cli.mjs gaps    run|summary|device-serve|device-judge --out out/<label>   (the Q33 gaps lane; src/gaps/README.md)
// node src/cli.mjs summary --out out/<label> [--parts id,...]   (reads <engine>.json files there, writes summary.json and summary.md;
//   --parts narrows the verdict to those parts, which the run must have covered; a narrowed run names covered and skipped parts)
//   `summary` prints one verdict line per engine and exits 0 only when every engine passed (Lean Fw.Gate.Exit).
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { PKG } from './serve.mjs';

// TS stand-in for Lean Fw.Gate.Exit (lean/Fw/Gate/Exit.lean): checked against packages/contracts/golden/gate/exit.jsonl
// by test/exit.test.mjs. Replace by an fwcore op when one is wired.
/** The verdict of one engine from the wire names of its table cells and its unsettled probe count (Lean engineVerdict). */
export function engineVerdict(cells, unsettled) {
  const cs = cells.filter((c) => c !== 'not-run');
  for (const c of cs) {
    if (!(['pass', 'fail', 'not-comparable'].includes(c) || /^unreachable:(primary-pair|whole-width|width-dpr)$/.test(c))) throw new Error(`unknown verdict ${c}`);
  }
  if (cs.includes('fail')) return 'fail';
  if (unsettled > 0) return 'unsettled';
  if (cs.includes('pass')) return 'pass';
  return 'notRendered';
}
/** The exit code from the verdicts of the judged engines: 0 only when there is one and every one passed (Lean exitCode). */
export function exitCode(verdicts) {
  return verdicts.length > 0 && verdicts.every((v) => v === 'pass') ? 0 : 1;
}
/** Lean Fw.Gate.Exit.outcomeOfWire: a wait outcome is unsettled when it is 'unsettled' or 'missing' (no wait was recorded). */
export function waitUnsettled(o) {
  if (o === 'unsettled' || o === 'missing') return true;
  if (/^settled@\d+$/.test(o)) return false;
  throw new Error(`unknown outcome ${o}`);
}
/**
 * Lean Fw.Gate.Exit.engineVerdictWW: the verdict of one engine from the wire names of its table cells and of its samples' wait
 * outcomes (one [orig, rewrite] pair per probe or sweep stop). Unsettled samples are counted from the waits themselves
 * (Fw.Gate.Exit.unsettledStates), never from a flag the page set.
 */
export function engineVerdictWaits(cells, waits) {
  return engineVerdict(cells, waits.filter(([a, b]) => waitUnsettled(a) || waitUnsettled(b)).length);
}
/**
 * Verdict of one engine of summary.json: its table cells, and its samples (probes and sweep stops) whose settle wait ended
 * unsettled on an arm or was not recorded. A row without `wait` (a summary from before the wait) is read as missing, so as unsettled.
 */
export function engineOfSummary(e) {
  const cells = Object.values(e.table).flatMap((row) => Object.values(row).map((t) => t.verdict));
  const pair = (x) => [x.wait?.orig ?? 'missing', x.wait?.rewrite ?? 'missing'];
  const waits = [...e.probes.map(pair), ...(e.sweeps ?? []).flatMap((sw) => sw.stops.map(pair))];
  const unsettled = waits.filter(([a, b]) => waitUnsettled(a) || waitUnsettled(b)).length;
  return { verdict: engineVerdictWaits(cells, waits), cells, unsettled };
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
  const judged = names.map((n) => ({ n, ...engineOfSummary(result.engines[n]) }));
  for (const j of judged) {
    const count = (v) => j.cells.filter((c) => c === v).length;
    console.log(`gate verdict ${j.n}: ${j.verdict} (cells: ${count('pass')} pass, ${count('fail')} fail; unsettled probes: ${j.unsettled})`);
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
