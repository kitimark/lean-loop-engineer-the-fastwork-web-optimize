#!/usr/bin/env node
// node src/throttle/toolbar-cli.mjs run --driver d --site dir --vm n [--message text] [--arms default,unthrottle] [--cycles 4] [--out file]
// node src/throttle/toolbar-cli.mjs build-driver --dir d   build the touch driver once, before the Simulator boots
// node src/throttle/toolbar-cli.mjs report --in a.json,run2-job3=b.json [--md file]   (label=file keeps jobs of several runs apart)   the tables and the verdict per flag
// node src/throttle/toolbar-cli.mjs plan [--message text]   print the arms of every job
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { loadavg } from 'node:os';
import { watch } from '../watchdog.mjs';
import { findDevice } from '../sim.mjs';
import { buildDriver, cleanup, findDriver, stop } from './driver.mjs';
import { makePassRunner } from './pass-run.mjs';
import { toolbarPass } from './toolbar-probe.mjs';
import { ARMS, reasonOf } from './toolbar.mjs';
import { armsOf, planOf } from './toolbar-plan.mjs';
import { reportMd } from './toolbar-report.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest,
  options: {
    site: { type: 'string' }, arms: { type: 'string' }, message: { type: 'string', default: '' }, cycles: { type: 'string', default: '4' },
    drag: { type: 'string', default: '480' }, velocity: { type: 'string', default: '150' }, settle: { type: 'string', default: '6000' }, vm: { type: 'string', default: '1' },
    'no-warmup': { type: 'boolean', default: false }, out: { type: 'string' }, dir: { type: 'string' }, driver: { type: 'string' }, in: { type: 'string' }, md: { type: 'string' },
    keep: { type: 'boolean', default: true },
  },
  allowNegative: true,
});
const log = (s) => console.error(s);
const siteOf = (arm) => {
  if (!v.site) throw new Error(`arm ${arm} needs --site (the prerendered build)`);
  return { dir: v.site, search: ARMS[arm] };
};

async function main() {
  switch (cmd) {
    case 'run': {
      const arms = v.arms ? v.arms.split(',') : armsOf(Number(v.vm), v.message);
      const unknown = arms.filter((a) => !(a in ARMS));
      if (unknown.length) throw new Error(`unknown arm ${unknown.join(', ')}; one of ${Object.keys(ARMS).join(', ')}`);
      log(`job ${v.vm}: arms ${arms.join(', ')}`);
      const udid = findDevice().udid;
      const driver = v.driver ? findDriver(resolve(v.driver)) : await buildDriver({ udid, log });
      log(`load ${loadavg()[0].toFixed(0)} before the first pass`);
      const drag = { cycles: Number(v.cycles), dragPt: Number(v.drag), velocity: Number(v.velocity), holdMs: 600, mode: 'finish', target: 'springboard' };
      const passes = [], failed = [], machine = [];
      const file = resolve(v.out ?? 'out/toolbar.json');
      const outDir = dirname(file);
      mkdirSync(outDir, { recursive: true });
      const save = () => writeFileSync(file, JSON.stringify({ vm: v.vm, drag, arms, passes, failed, machine }) + '\n');
      const { warmUp, runArm } = makePassRunner({ driver, udid, drag, log, vm: v.vm, keep: v.keep, settleMs: Number(v.settle), outDir, siteOf,
        firstSiteArm: arms[0], passOf: toolbarPass, reasonOf, state: { passes, failed, machine }, save });
      try {
        if (!v['no-warmup']) await warmUp('warm-up');
        for (const arm of arms) await runArm(arm, 0);
      } finally { stop(); if (!v.driver) cleanup(driver); }
      save();
      log(`wrote ${file} (${passes.length} passes${failed.length ? `, ${failed.length} failed` : ''})`);
      if (!passes.length) throw new Error('no pass completed');
      break;
    }
    case 'build-driver': {
      if (!v.dir) throw new Error('usage: build-driver --dir d');
      await buildDriver({ dir: resolve(v.dir), log });
      log(`load ${loadavg()[0].toFixed(0)} after the build`);
      break;
    }
    case 'report': {
      if (!v.in) throw new Error('usage: report --in a.json,b.json [--md file]');
      const jobs = v.in.split(',').map((e) => {
        const [label, file] = e.includes('=') ? e.split('=') : [null, e];
        return { label, ...JSON.parse(readFileSync(resolve(file), 'utf8')) };
      });
      const md = reportMd(jobs.map((j, i) => ({ vm: j.label ?? `job ${j.vm ?? i + 1}`, passes: j.passes })));
      if (v.md) writeFileSync(resolve(v.md), md); else console.log(md);
      break;
    }
    case 'plan':
      for (const [i, a] of planOf(v.message).entries()) console.log(`job ${i + 1}: ${a.join(',')}`);
      break;
    default:
      console.error('usage: run|build-driver|report|plan');
      process.exitCode = 2;
  }
}
const guard = watch();
main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = e.exitCode ?? 1; }).finally(() => guard.done(process.exitCode ?? 0));
