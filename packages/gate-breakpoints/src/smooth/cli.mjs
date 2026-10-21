#!/usr/bin/env node
// smoothness-probe tables. Usage:
//   node src/smooth/cli.mjs continuity --runs <dir> --out <dir>   motion continuity from downloaded trajectory-probe runs (part A)
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
} else if (cmd === 'cadence') {
  const { cadenceMain } = await import('./cadence-table.mjs');
  await cadenceMain(flag('--runs'), flag('--out'));
} else {
  console.error('usage: cli.mjs continuity|cadence --runs <dir> --out <dir>');
  process.exit(2);
}
