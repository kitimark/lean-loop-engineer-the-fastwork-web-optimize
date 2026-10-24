#!/usr/bin/env node
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';

const args = process.argv.slice(2).filter((a) => a !== '--');
const flag = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
const [cmd] = args;

if (cmd === 'sim') {
  const { runSimCadence } = await import('./sim-cadence.mjs');
  const site = flag('--site');
  const search = flag('--search');
  const { parseArms } = await import('../../../gate-breakpoints/src/smooth/bound.mjs');
  const only = parseArms(flag('--arms'));
  if (!site || (!search && !only)) { console.error('sim needs --site <dir> and --search ?fw=... (or --arms base,aa,bound)'); process.exit(2); }
  const out = flag('--out') ?? 'out/smoothness-webkit';
  mkdirSync(out, { recursive: true });
  const { writeRaws } = await import('./raw.mjs');
  const write = (r) => writeFileSync(join(out, 'sim.json'), `${JSON.stringify(writeRaws(out, 'sim', r))}\n`);
  const res = await runSimCadence({ siteDir: resolve(site), lookSearch: search, reps: flag('--reps') ?? 'auto', only, holdMs: flag('--hold-ms'), touchDriver: flag('--touch-driver') ? resolve(flag('--touch-driver')) : undefined, settleMs: Number(flag('--settle') ?? 2500), deadlineMs: flag('--deadline-ms') ? Number(flag('--deadline-ms')) : null, onProgress: write, blockAfterMs: process.env.FW_WALK_TEST_BLOCK_AFTER_MS ? Number(process.env.FW_WALK_TEST_BLOCK_AFTER_MS) : null });
  write(res);
  console.log(`webkit sim: ${res.rows.length} windows, refused=${res.refused}, incomplete=${res.incomplete ?? 'no'}, ${res.wallSeconds} s, ${res.runtime}`);
  process.exit(res.refused || (res.incomplete && !res.rows.some((r) => r.ok)) ? 1 : 0);
} else if (cmd === 'report') {
  const { reportMain } = await import('./report.mjs');
  const { classify } = await import('../../../measure-chromium/src/fwcore.mjs');
  const runs = flag('--runs');
  const out = flag('--out');
  if (!runs || !out) { console.error('report needs --runs <dir> --out <dir>'); process.exit(2); }
  const r = await reportMain({ runs, out, note: flag('--note'), jobsDir: flag('--jobs') ?? join(out, 'jobs'), classify });
  console.log(`report: ${r.jobs} jobs, ${r.skipped.length} skipped, blocks missing from the note: ${r.missing.join(', ') || 'none'}`);
} else {
  console.error('usage: cli.mjs sim|report');
  process.exit(2);
}
