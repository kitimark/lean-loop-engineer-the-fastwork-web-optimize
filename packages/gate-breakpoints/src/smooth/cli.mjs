#!/usr/bin/env node
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
  const { runCadence } = await import('./cadence.mjs');
  const widths = (flag('--widths') ?? '390,1280').split(',').map(Number);
  const out = flag('--out') ?? 'out/smoothness';
  const { parseThrottle } = await import('./throttle.mjs');
  const cpuThrottle = parseThrottle(flag('--cpu-throttle'));
  if (cpuThrottle === null) { console.error('--cpu-throttle must be 1 or 6'); process.exit(2); }
  const res = await runCadence({ widths, cpuThrottle, search: flag('--search') ?? '', reps: Number(flag('--reps') ?? 6), traceReps: Number(flag('--trace-reps') ?? 2) });
  mkdirSync(out, { recursive: true });
  for (const w of widths) writeFileSync(join(out, `cadence-${w}.json`), `${JSON.stringify({ ...res, runs: res.runs.filter((r) => r.width === w), traces: res.traces.filter((r) => r.width === w) })}\n`);
  console.log(`cadence run: ${res.runs.length} windows, ${res.traces.length} traced, refused=${res.refused}`);
  if (res.refused) process.exit(1);
} else if (cmd === 'webkit') {
  const { runWebkitCadence } = await import('./webkit-cadence.mjs');
  const out = flag('--out') ?? 'out/smoothness-webkit';
  const { parseArms } = await import('./bound.mjs');
  const res = await runWebkitCadence({ width: Number(flag('--width') ?? 390), lookSearch: flag('--search'), only: parseArms(flag('--arms')), holdMs: flag('--hold-ms'), reps: Number(flag('--reps') ?? 6), cadenceReps: Number(flag('--cadence-reps') ?? 5) });
  mkdirSync(out, { recursive: true });
  const { writeRaws } = await import('../../../measure-webkit/src/profile/raw.mjs');
  writeFileSync(join(out, 'mac.json'), `${JSON.stringify(writeRaws(out, 'mac', res))}\n`);
  console.log(`webkit mac: ${res.rows.length} windows, refused=${res.refused}, ${res.wallSeconds} s`);
  if (res.refused) process.exit(1);
} else if (cmd === 'cadence') {
  const { cadenceMain } = await import('./cadence-table.mjs');
  await cadenceMain(flag('--runs'), flag('--out'));
} else {
  console.error('usage: cli.mjs continuity|run|cadence --runs <dir> --out <dir>');
  process.exit(2);
}
