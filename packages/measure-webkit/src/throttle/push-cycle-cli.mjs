#!/usr/bin/env node
// --separate: the full pass has SEP_FULL_CYCLES cycles (Lean sepFullCycles), --cycles is not read
// node src/throttle/push-cycle-cli.mjs run --site dir --driver d [--arms original,rewrite,user] [--rounds 1] [--cycles 6] [--hold 600] [--vm n] [--out file]
// node src/throttle/push-cycle-cli.mjs report --in a.json,b.json [--md file] [--expect 1,2,3]
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync, readFileSync, readdirSync, renameSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { loadavg } from 'node:os';
import { watch } from '../watchdog.mjs';
import { findDevice } from '../sim.mjs';
import { buildDriver, cleanup, findDriver, stop } from './driver.mjs';
import { makePassRunner } from './pass-run.mjs';
import { excludeReason } from './finish-report.mjs';
import { pushCyclePass } from './push-cycle-pass.mjs';
import { searchOf, uploadName, periodMs, SEP_FULL_CYCLES } from './push-cycle.mjs';
import { passFile } from '../session.mjs';
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
    in: { type: 'string' }, md: { type: 'string' }, expect: { type: 'string' }, keep: { type: 'boolean', default: true },
    separate: { type: 'boolean', default: false }, ratio: { type: 'string', default: '2' }, 'rest-cap': { type: 'string', default: '120000' },
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
      const drag = { cycles: v.separate ? SEP_FULL_CYCLES : Number(v.cycles), dragPt: Number(v.drag), velocity: Number(v.velocity), holdMs: Number(v.hold), mode: 'finish', target: v.target };
      const passes = [], failed = [], machine = [];
      const file = resolve(v.out ?? 'out/push-cycle.json');
      const outDir = dirname(file);
      mkdirSync(outDir, { recursive: true });
      let written = 0;
      const save = () => {
        writeFileSync(file, JSON.stringify({ vm: v.vm, drag, passes, failed, machine }) + '\n');
        for (; written < passes.length; written++) writeFileSync(passFile(file, written + 1), JSON.stringify(passes[written]) + '\n');
      };
      const plan = { profile: 'full', targetMs: 0 };
      const runner = (profile) => makePassRunner({ driver, udid, drag, log, vm: v.vm, keep: v.keep, settleMs: Number(v.settle), outDir, siteOf,
        firstSiteArm: arms.find((x) => x !== 'original') ?? 'original', passOf: (ctx, o) => pushCyclePass(ctx, { ...o, profile, targetMs: plan.targetMs, restCapMs: Number(v['rest-cap']) }),
        reasonOf: excludeReason, state: { passes, failed, machine }, save });
      const full = runner('full');
      const dwell = v.separate ? runner('dwell') : null;
      try {
        if (!v['no-warmup']) await full.warmUp('warm-up');
        for (let round = 0; round < Number(v.rounds); round++) {
          for (const arm of rotate(arms, round + Number(v.rotate))) {
            const rd = dwell ? 2 * round : round;
            await full.runArm(arm, rd);
            if (!dwell) continue;
            const last = passes.filter((p) => p.arm === arm && p.profile === 'full').at(-1);
            const period = last?.rec ? periodMs(last.rec) : 0;
            plan.targetMs = period > 0 ? Math.round(period * Number(v.ratio)) : 40000;
            log(`${arm}: full period ${period} ms, dwell target ${plan.targetMs} ms`);
            await dwell.runArm(arm, rd + 1);
          }
        }
      } finally {
        stop(); if (!v.driver) cleanup(driver);
        for (const f of readdirSync(outDir)) if (f !== uploadName(f)) renameSync(join(outDir, f), join(outDir, uploadName(f))); // arm names carry a colon
      }
      save();
      log(`wrote ${file} (${passes.length} passes${failed.length ? `, ${failed.length} failed` : ''})`);
      if (!passes.length) throw new Error('no pass completed');
      break;
    }
    case 'report': {
      if (!v.in) throw new Error('usage: report --in a.json,b.json [--md file] [--expect 1,2,3]');
      const jobs = v.in.split(',').map((f) => JSON.parse(readFileSync(resolve(f), 'utf8'))).map((j, i) => ({ ...j, vm: `job ${j.vm ?? i + 1}` }));
      const md = reportMd(jobs, v.expect ? v.expect.split(',').map((n) => `job ${n}`) : null);
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
