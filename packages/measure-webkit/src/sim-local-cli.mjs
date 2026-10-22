#!/usr/bin/env node
// Local lane CLI (mac-safari-measure, named exception (c) of "measure on CI"): Safari on macOS and Mobile Safari in the iOS Simulator
// on this Mac, every pass under a sim slot and Lean's quiet rule. Writes results/mac-safari/{passes/*.json, summary.json, meta.json}.
//   node sim-local-cli.mjs --site <apps/site/dist/aot> [--engine sim|safari|both] [--passes 3] [--deadline-min 25] [--out dir]
// A local run is never a CI result: the files say `lane: local`.
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { parseArgs } from 'node:util';

const { values: v } = parseArgs({ options: {
  site: { type: 'string' }, engine: { type: 'string', default: 'both' }, passes: { type: 'string', default: '3' }, 'max-rounds': { type: 'string', default: '9' },
  'deadline-min': { type: 'string', default: '25' }, 'wait-s': { type: 'string', default: '90' }, out: { type: 'string', default: 'results/mac-safari' },
  device: { type: 'string', default: 'fw-mac-safari-27' }, 'no-lease': { type: 'boolean', default: false },
} });
if (!v.site) { console.error('usage: sim-local-cli.mjs --site <prerendered build dir> [--engine sim|safari|both]'); process.exit(2); }
process.env.FW_SIM_NAME = v.device; // before sim.mjs is imported: DEVICE_NAME is read once

const cwd = process.cwd();
const out = resolve(cwd, v.out);
mkdirSync(join(out, 'passes'), { recursive: true });
const log = (s) => console.error(`${new Date().toISOString().slice(11, 19)} ${s}`);

const { localArms, readMachine, summarize } = await import('./safari-local-run.mjs');
const { holdSimSlot } = await import('./safari-local-lease.mjs');
const { arms, dropped } = localArms(resolve(v.site));
log(`arms: ${arms.map((a) => a.id).join(' ')}${dropped.length ? ` (dropped as duplicates: ${dropped.join(' ')})` : ''}`);

const lease = v['no-lease'] ? { token: null, release: async () => {} } : await holdSimSlot({ cwd, log });
const read = () => readMachine({ cwd, mine: lease.token ? [lease.token] : [] });
const opts = { arms, read, passes: Number(v.passes), maxRounds: Number(v['max-rounds']), waitMs: Number(v['wait-s']) * 1000, everyMs: 5000, log };
const all = [];
const onRow = (r) => { all.push(r); writeFileSync(join(out, 'passes', `${r.engine}-${r.window}-${r.arm}-r${r.round}.json`), JSON.stringify(r, null, 1) + '\n'); };
const meta = { lane: 'local', note: 'local debug lane on one shared Mac, not a CI or phone result', startedAt: new Date().toISOString(), arms: arms.map((a) => a.id), dropped, passes: Number(v.passes), engines: {} };
let created = false;
try {
  if (v.engine === 'sim' || v.engine === 'both') {
    const { ensureDevice, runSimLocal } = await import('./sim-local.mjs');
    created = ensureDevice(v.device).created;
    const r = await runSimLocal({ ...opts, onRow, deadlineMs: Date.now() + Number(v['deadline-min']) * 60000 });
    meta.engines.sim = { device: 'iOS Simulator (iPhone 15 Pro Max type)', runtime: r.runtime, ua: r.ua, vw: r.vw };
  }
  if (v.engine === 'safari' || v.engine === 'both') {
    const { runSafariLocal } = await import('./safari-local.mjs');
    const r = await runSafariLocal({ ...opts, onRow, deadlineMs: Date.now() + Number(v['deadline-min']) * 60000 });
    meta.engines.safari = { ua: r.ua, vw: r.vw, rect: r.rect };
  }
} finally {
  if (created) { const { removeDevice } = await import('./sim-local.mjs'); try { removeDevice(v.device); } catch (e) { log(`device delete: ${e.message}`); } }
  await lease.release();
  meta.finishedAt = new Date().toISOString();
  meta.mac = { chip: spawnSync('sysctl', ['-n', 'machdep.cpu.brand_string'], { encoding: 'utf8' }).stdout.trim(), os: spawnSync('sw_vers', ['-productVersion'], { encoding: 'utf8' }).stdout.trim() };
  writeFileSync(join(out, 'meta.json'), JSON.stringify(meta, null, 1) + '\n');
  writeFileSync(join(out, 'summary.json'), JSON.stringify(summarize(all), null, 1) + '\n');
  log(`wrote ${all.length} pass files and the summary to ${out}`);
}
