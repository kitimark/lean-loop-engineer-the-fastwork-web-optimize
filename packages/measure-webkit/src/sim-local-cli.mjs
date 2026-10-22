#!/usr/bin/env node
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { parseArgs } from 'node:util';

const { values: v } = parseArgs({ options: {
  site: { type: 'string' }, engine: { type: 'string', default: 'both' }, passes: { type: 'string', default: '3' }, 'max-rounds': { type: 'string', default: '9' },
  'deadline-min': { type: 'string', default: '25' }, 'wait-s': { type: 'string', default: '90' }, 'base-wait-s': { type: 'string', default: '600' }, out: { type: 'string', default: 'results/mac-safari' },
  device: { type: 'string', default: 'fw-mac-safari-27' }, 'no-lease': { type: 'boolean', default: false }, 'debug-ignore-quiet': { type: 'boolean', default: false },
} });
if (!v.site) { console.error('usage: sim-local-cli.mjs --site <prerendered build dir> [--engine sim|safari|both]'); process.exit(2); }
process.env.FW_SIM_NAME = v.device;

const cwd = process.cwd();
const out = resolve(cwd, v.out);
mkdirSync(join(out, 'passes'), { recursive: true });
const log = (s) => console.error(`${new Date().toISOString().slice(11, 19)} ${s}`);

const { localArms, readMachine, summarize, takeBaseline } = await import('./safari-local-run.mjs');
const { holdSimSlot, holdMeasureSlot } = await import('./safari-local-lease.mjs');
const { arms, dropped } = localArms(resolve(v.site));
log(`arms: ${arms.map((a) => a.id).join(' ')}${dropped.length ? ` (dropped as duplicates: ${dropped.join(' ')})` : ''}`);

if (v['debug-ignore-quiet'] && /(^|\/)results\//.test(v.out)) { console.error('--debug-ignore-quiet never writes under results/'); process.exit(2); }
const calm = { time: 0, loadCenti: 0, mem: { freeMB: 9999, specMB: 0, purgMB: 0, fileMB: 0, fileMinMB: 0, swapUsedMB: 0, swapTotalMB: 0, press: 1, comprMBPerMin: 0, swapOutMBPerMin: 0 }, ramMB: 16384, compressorMB: 0, holders: 0, queued: 0 };
const optsFor = (lease) => {
  const read = v['debug-ignore-quiet'] ? async () => ({ ...calm, time: Math.floor(Date.now() / 1000) }) : () => readMachine({ cwd, mine: lease.token ? [lease.token] : [] });
  const takeBase = v['debug-ignore-quiet'] ? async () => ({ floorCenti: 0, readings: [] }) : ({ boot }) => takeBaseline({ read, boot, waitMs: Number(v['base-wait-s']) * 1000, log });
  return { arms, read, takeBase, pass: lease.pass ?? null, passes: Number(v.passes), maxRounds: Number(v['max-rounds']), waitMs: Number(v['wait-s']) * 1000, everyMs: 5000, log };
};
const withLease = async (kind, fn) => {
  const lease = v['no-lease'] ? { token: null, release: async () => {} } : kind === 'sim' ? await holdSimSlot({ cwd, log }) : await holdMeasureSlot({ cwd, log });
  try { return await fn(lease); } finally { await lease.release(); }
};
const all = [];
const onRow = (r0) => { const r = v['debug-ignore-quiet'] ? { ...r0, debug: true } : r0; all.push(r); writeFileSync(join(out, 'passes', `${r.engine}-${r.window}-${r.arm}-r${r.round}.json`), JSON.stringify(r, null, 1) + '\n'); };
const meta = { lane: 'local', debug: v['debug-ignore-quiet'], note: 'local debug lane on one shared Mac, not a CI or phone result', startedAt: new Date().toISOString(), arms: arms.map((a) => a.id), dropped, passes: Number(v.passes), engines: {} };
try {
  if (v.engine === 'sim' || v.engine === 'both') {
    const { ensureDevice, runSimLocal } = await import('./sim-local.mjs');
    const r = await withLease('sim', (lease) => {
      const dev = ensureDevice(v.device);
      log(`device ${dev.name}: ${dev.created ? 'created now (once; later runs reuse it)' : 'reused'}`);
      meta.device = { name: dev.name, createdThisRun: dev.created };
      return runSimLocal({ ...optsFor(lease), onRow, deadlineMs: Date.now() + Number(v['deadline-min']) * 60000 });
    });
    meta.engines.sim = { device: 'iOS Simulator (iPhone 15 Pro Max type)', runtime: r.runtime, ua: r.ua, vw: r.vw, baseline: r.baseline };
  }
  if (v.engine === 'safari' || v.engine === 'both') {
    const { runSafariLocal } = await import('./safari-local.mjs');
    const r = await withLease('measure', (lease) => runSafariLocal({ ...optsFor(lease), onRow, deadlineMs: Date.now() + Number(v['deadline-min']) * 60000 }));
    meta.engines.safari = { ua: r.ua, vw: r.vw, rect: r.rect, baseline: r.baseline };
  }
} finally {
  meta.finishedAt = new Date().toISOString();
  meta.mac = { chip: spawnSync('sysctl', ['-n', 'machdep.cpu.brand_string'], { encoding: 'utf8' }).stdout.trim(), os: spawnSync('sw_vers', ['-productVersion'], { encoding: 'utf8' }).stdout.trim() };
  writeFileSync(join(out, 'meta.json'), JSON.stringify(meta, null, 1) + '\n');
  writeFileSync(join(out, 'summary.json'), JSON.stringify(summarize(all), null, 1) + '\n');
  log(`wrote ${all.length} pass files and the summary to ${out}`);
}
