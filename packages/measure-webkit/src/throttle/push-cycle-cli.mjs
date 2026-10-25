#!/usr/bin/env node
// node src/throttle/push-cycle-cli.mjs run --site dir --driver d [--arms original,rewrite,user] [--rounds 1] [--cycles 6] [--hold 600] [--vm n] [--out file]
//   Real touches on Mobile Safari in the booted Simulator: the page is scrolled to 300 px above its end, then N back-and-forth cycles (drag past
//   the end, drag back, shorter drag so the toolbar returns), dwell --hold ms after each press. One pass per arm and round, the order rotated by
//   --rotate. original = the read-only snapshot; rewrite = the default prerendered build; user = the user's composition; off-<flag> = it minus one flag.
// node src/throttle/push-cycle-cli.mjs report --in a.json,b.json [--md file]   the per-cycle table, the trend and the H1/H2 verdicts
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { loadavg } from 'node:os';
import { watch } from '../watchdog.mjs';
import { findDevice } from '../sim.mjs';
import { buildDriver, cleanup, findDriver, stop } from './driver.mjs';
import { makePassRunner } from './pass-run.mjs';
import { excludeReason } from './finish-report.mjs';
import { pushCyclePass } from './push-cycle-pass.mjs';
import { searchOf } from './push-cycle.mjs';
import { reportMd } from './push-cycle-report.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest,
  options: {
    site: { type: 'string' }, arms: { type: 'string', default: 'original,rewrite,user' }, rounds: { type: 'string', default: '1' },
    cycles: { type: 'string', default: '6' }, hold: { type: 'string', default: '600' }, rotate: { type: 'string', default: '0' },
    drag: { type: 'string', default: '480' }, velocity: { type: 'string', default: '150' }, target: { type: 'string', default: 'springboard' },
    timeout: { type: 'string', default: '480' }, reset: { type: 'boolean', default: false }, 'no-warmup': { type: 'boolean', default: false },
    settle: { type: 'string', default: '6000' }, vm: { type: 'string', default: '1' }, out: { type: 'string' }, driver: { type: 'string' },
    in: { type: 'string' }, md: { type: 'string' }, keep: { type: 'boolean', default: true },
  },
  allowNegative: true,
});
const log = (s) => console.error(s);
const siteOf = (arm) => {
  const search = searchOf(arm);
  if (search === null) return null;
  if (!v.site) throw new Error(`arm ${arm} needs --site (the prerendered build)`);
  return { dir: v.site, search };
};
const rotate = (arms, r) => arms.map((_, i) => arms[(i + r) % arms.length]);

async function main() {
  switch (cmd) {
    case 'run': {
      const arms = v.arms.split(',');
      for (const a of arms) searchOf(a); // throws on an unknown arm
      const udid = findDevice().udid;
      const driver = v.driver ? findDriver(resolve(v.driver)) : await buildDriver({ udid, log });
      log(`load ${loadavg()[0].toFixed(0)} before the first pass`);
      const drag = { cycles: Number(v.cycles), dragPt: Number(v.drag), velocity: Number(v.velocity), holdMs: Number(v.hold), mode: 'finish', target: v.target };
      const passes = [], failed = [], machine = [];
      const file = resolve(v.out ?? 'out/push-cycle.json');
      const outDir = dirname(file);
      mkdirSync(outDir, { recursive: true });
      const save = () => writeFileSync(file, JSON.stringify({ vm: v.vm, drag, passes, failed, machine }) + '\n');
      const { warmUp, runArm } = makePassRunner({ driver, udid, drag, log, vm: v.vm, keep: v.keep, settleMs: Number(v.settle), outDir, siteOf,
        firstSiteArm: arms.find((x) => x !== 'original') ?? 'original', passOf: pushCyclePass, reasonOf: excludeReason, state: { passes, failed, machine }, save });
      try {
        if (!v['no-warmup']) await warmUp('warm-up');
        for (let round = 0; round < Number(v.rounds); round++) {
          for (const arm of rotate(arms, round + Number(v.rotate))) await runArm(arm, round);
        }
      } finally { stop(); if (!v.driver) cleanup(driver); }
      save();
      log(`wrote ${file} (${passes.length} passes${failed.length ? `, ${failed.length} failed` : ''})`);
      if (!passes.length) throw new Error('no pass completed');
      break;
    }
    case 'report': {
      if (!v.in) throw new Error('usage: report --in a.json,b.json [--md file]');
      const jobs = v.in.split(',').map((f) => JSON.parse(readFileSync(resolve(f), 'utf8'))).map((j, i) => ({ ...j, vm: `job ${j.vm ?? i + 1}` }));
      const md = reportMd(jobs);
      if (v.md) writeFileSync(resolve(v.md), md); else console.log(md);
      break;
    }
    default:
      console.error('usage: run|report');
      process.exitCode = 2;
  }
}
const guard = watch();
main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = e.exitCode ?? 1; }).finally(() => guard.done(process.exitCode ?? 0));
