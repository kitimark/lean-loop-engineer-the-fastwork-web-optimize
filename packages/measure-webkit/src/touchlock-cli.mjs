#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';

const args = process.argv.slice(2).filter((a) => a !== '--');
const flag = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
const [cmd] = args;

if (cmd === 'run') {
  const site = flag('--site');
  if (!site || !flag('--touch-driver')) { console.error('run needs --site <dir> and --touch-driver <dir>'); process.exit(2); }
  const out = flag('--out') ?? 'out/touch-lock';
  mkdirSync(out, { recursive: true });
  const write = (r) => writeFileSync(join(out, 'touch-lock.json'), `${JSON.stringify(r)}\n`);
  const { runTouchLock } = await import('./touchlock-run.mjs');
  const res = await runTouchLock({
    siteDir: resolve(site), reps: Number(flag('--reps') ?? 6), settleMs: Number(flag('--settle') ?? 2500), touchDriver: resolve(flag('--touch-driver')),
    deadlineMs: flag('--deadline-ms') ? Number(flag('--deadline-ms')) : null, onProgress: write,
  });
  write(res);
  const { markdown } = await import('./touchlock.mjs');
  writeFileSync(join(out, 'touch-lock.md'), `${markdown(res.summary)}\n`);
  console.log(`touch-lock: ${res.rows.length} windows, incomplete=${res.incomplete ?? 'no'}, ${res.wallSeconds} s, ${res.runtime}`);
  process.exit(res.rows.some((r) => r.frames) ? 0 : 1);
} else if (cmd === 'report') {
  const { summarize, markdown } = await import('./touchlock.mjs');
  const files = args.slice(1);
  if (!files.length) { console.error('report needs touch-lock.json files'); process.exit(2); }
  const rows = files.flatMap((f) => JSON.parse(readFileSync(f, 'utf8')).rows);
  console.log(markdown(summarize(rows)));
} else {
  console.error('usage: touchlock-cli.mjs run|report');
  process.exit(2);
}
