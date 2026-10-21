#!/usr/bin/env node
// smoothness-probe tables. Usage:
//   node src/smooth/cli.mjs continuity --runs <dir> --out <dir>   motion continuity from downloaded trajectory-probe runs (part A)
//   node src/smooth/cli.mjs run --widths 390,1280 --search ?preset=v2-proved --reps 6 --out <dir>   the cadence lane on one runner (part B)
//   node src/smooth/cli.mjs webkit --width 390 --search ?fw=... --reps 6 --cadence-reps 5 --out <dir>   leg 1 of smoothness-webkit-cadence (WebKit on macOS)
//   node src/smooth/cli.mjs cadence --runs <dir> --out <dir>      frame cadence from downloaded smoothness runs (part B)
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { summariseAll, byArm, markdown } from './table.mjs';

const args = process.argv.slice(2);
const flag = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
const [cmd] = args;

if (cmd === 'continuity') {
  const dir = flag('--runs');
  const out = flag('--out');
  if (!dir || !out) { console.error('continuity needs --runs <dir> --out <dir>'); process.exit(2); }
  const engines = (flag('--engines') ?? '').split(',').filter(Boolean);
  const widths = (flag('--widths') ?? '').split(',').filter(Boolean).map(Number);
  const all = summariseAll(dir);
  const skipped = all.skipped;
  const records = all.records.filter((r) => (engines.length === 0 || engines.includes(r.engine)) && (widths.length === 0 || widths.includes(r.width)));
  const rows = byArm(records);
  mkdirSync(out, { recursive: true });
  if (args.includes('--records')) writeFileSync(join(out, 'continuity.records.json'), `${JSON.stringify({ skipped, records })}\n`);
  writeFileSync(join(out, 'continuity.skipped.json'), `${JSON.stringify(skipped, null, 1)}\n`);
  writeFileSync(join(out, 'continuity.table.json'), `${JSON.stringify(rows, null, 1)}\n`);
  writeFileSync(join(out, 'continuity.table.md'), `${markdown(rows)}\n`);
  console.log(`continuity: ${records.length} records from ${new Set(records.map((r) => r.run)).size} runs, ${skipped.length} skipped, ${rows.length} table rows`);
} else if (cmd === 'run') {
  // The cadence lane on one runner: Chromium, the widths given, the candidate search, repeats per arm and window.
  const { runCadence } = await import('./cadence.mjs');
  const widths = (flag('--widths') ?? '390,1280').split(',').map(Number);
  const out = flag('--out') ?? 'out/smoothness';
  const res = await runCadence({ widths, search: flag('--search') ?? '', reps: Number(flag('--reps') ?? 6), traceReps: Number(flag('--trace-reps') ?? 2) });
  mkdirSync(out, { recursive: true });
  for (const w of widths) writeFileSync(join(out, `cadence-${w}.json`), `${JSON.stringify({ ...res, runs: res.runs.filter((r) => r.width === w), traces: res.traces.filter((r) => r.width === w) })}\n`);
  console.log(`cadence run: ${res.runs.length} windows, ${res.traces.length} traced, refused=${res.refused}`);
  if (res.refused) process.exit(1);
} else if (cmd === 'webkit') {
  // Leg 1 of smoothness-webkit-cadence: Playwright WebKit on a macOS runner, all arms, the Timeline profile and the cadence.
  const { runWebkitCadence } = await import('./webkit-cadence.mjs');
  const out = flag('--out') ?? 'out/smoothness-webkit';
  const res = await runWebkitCadence({ width: Number(flag('--width') ?? 390), lookSearch: flag('--search'), reps: Number(flag('--reps') ?? 6), cadenceReps: Number(flag('--cadence-reps') ?? 5) });
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, 'mac.json'), `${JSON.stringify(res)}\n`);
  console.log(`webkit mac: ${res.rows.length} windows, refused=${res.refused}, ${res.wallSeconds} s`);
  if (res.refused) process.exit(1);
} else if (cmd === 'cadence') {
  const { cadenceMain } = await import('./cadence-table.mjs');
  await cadenceMain(flag('--runs'), flag('--out'));
} else {
  console.error('usage: cli.mjs continuity|run|cadence --runs <dir> --out <dir>');
  process.exit(2);
}
