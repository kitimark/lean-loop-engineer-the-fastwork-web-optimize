#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { loadavg } from 'node:os';
import { pathToFileURL } from 'node:url';
import { watch } from '../watchdog.mjs';
import { findDevice } from '../sim.mjs';
import { buildDriver, cleanup, findDriver, stop } from './driver.mjs';
import { makePassRunner } from './pass-run.mjs';
import { partsPass, MODES } from './parts-probe.mjs';
import { excludeReason, ARMS, summarize, summaryMd } from './parts.mjs';

export const SEARCH = Object.freeze({ lift: '?fw=engine.scroll:throttle-lift', unthrottle: '?fw=engine.scroll:unthrottle' });
export const rotate = (arms, r) => arms.map((_, i) => arms[(i + r) % arms.length]);
export const tagOf = (arm, round, attempt) => `${arm}-r${round}${attempt > 1 ? `-a${attempt}` : ''}`;
export const dragOf = (mode, o) => ({ cycles: Number(o.cycles), dragPt: Number(o.drag ?? (mode === 'finish' ? 480 : 360)),
  velocity: Number(o.velocity ?? (mode === 'finish' ? 150 : 120)), holdMs: Number(o.hold), mode: mode === 'finish' ? 'finish' : 'drags', target: o.target });

function options(args) {
  return parseArgs({
    args,
    options: {
      site: { type: 'string' }, arms: { type: 'string', default: ARMS.join(',') }, rounds: { type: 'string', default: '2' }, cycles: { type: 'string', default: '4' },
      drag: { type: 'string' }, velocity: { type: 'string' }, mode: { type: 'string', default: 'drags' }, target: { type: 'string', default: 'springboard' },
      hold: { type: 'string', default: '600' }, 'no-warmup': { type: 'boolean', default: false }, settle: { type: 'string', default: '6000' }, vm: { type: 'string', default: '1' },
      out: { type: 'string' }, dir: { type: 'string' }, driver: { type: 'string' }, in: { type: 'string' }, md: { type: 'string' }, json: { type: 'string' }, run: { type: 'string' },
      keep: { type: 'boolean', default: true },
    },
    allowNegative: true,
  }).values;
}

const log = (s) => console.error(s);

async function run(v) {
  if (!MODES.includes(v.mode)) throw new Error(`unknown --mode ${v.mode}; ${MODES.join(', ')}`);
  const arms = v.arms.split(',');
  for (const a of arms) if (!ARMS.includes(a)) throw new Error(`unknown arm ${a}`);
  const siteOf = (arm) => {
    if (arm === 'original') return null;
    if (!v.site) throw new Error(`arm ${arm} needs --site (the prerendered build)`);
    return { dir: v.site, search: SEARCH[arm] ?? '' };
  };
  const udid = findDevice().udid;
  const driver = v.driver ? findDriver(resolve(v.driver)) : await buildDriver({ udid, log });
  log(`load ${loadavg()[0].toFixed(0)} before the first pass`);
  const drag = dragOf(v.mode, v);
  const passes = [], failed = [], machine = [];
  const file = resolve(v.out ?? 'out/throttle-parts.json');
  mkdirSync(dirname(file), { recursive: true });
  const save = () => writeFileSync(file, JSON.stringify({ vm: v.vm, mode: v.mode, drag, passes, failed, machine }) + '\n');
  // Each pass runs under the Lean machine of Fw.Device.SimTouch (probe, touches, one Simulator restart and one more try): pass-run.mjs
  const { warmUp, runArm } = makePassRunner({ driver, udid, drag, log, vm: v.vm, keep: v.keep, settleMs: Number(v.settle), outDir: dirname(file), siteOf,
    firstSiteArm: arms.find((a) => a !== 'original') ?? 'original', warmMode: 'drags', state: { passes, failed, machine }, save,
    passOf: (ctx, o) => partsPass(ctx, { ...o, mode: v.mode }), reasonOf: (p) => (p.skipped ? null : excludeReason(p)) });
  try {
    if (!v['no-warmup']) await warmUp('warm-up');
    for (let round = 0; round < Number(v.rounds); round++) {
      for (const arm of rotate(arms, round)) await runArm(arm, round);
    }
  } finally { stop(); if (!v.driver) cleanup(driver); }
  save();
  log(`wrote ${file} (${passes.length} passes${failed.length ? `, ${failed.length} failed` : ''})`);
  if (!passes.length) throw new Error('no pass completed');
}

export function report(v) {
  if (!v.in) throw new Error('usage: report --in a.json,b.json [--md file] [--json file] [--run id]');
  const jobs = v.in.split(',').map((f) => JSON.parse(readFileSync(resolve(f), 'utf8')));
  const mode = jobs[0].mode ?? 'drags';
  if (jobs.some((j) => (j.mode ?? 'drags') !== mode)) throw new Error('jobs of different modes in one report');
  const sm = summarize(mode, jobs, v.run ?? null);
  if (v.md) writeFileSync(resolve(v.md), summaryMd(sm)); else console.log(summaryMd(sm));
  if (v.json) writeFileSync(resolve(v.json), `${JSON.stringify(sm, null, 1)}\n`);
  return sm;
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2).filter((a) => a !== '--');
  const v = options(rest);
  switch (cmd) {
    case 'run': await run(v); break;
    case 'build-driver':
      if (!v.dir) throw new Error('usage: build-driver --dir d');
      await buildDriver({ dir: resolve(v.dir), log });
      log(`load ${loadavg()[0].toFixed(0)} after the build`);
      break;
    case 'report': report(v); break;
    default:
      console.error('usage: run|build-driver|report');
      process.exitCode = 2;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const guard = watch();
  main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = e.exitCode ?? 1; }).finally(() => guard.done(process.exitCode ?? 0));
}
