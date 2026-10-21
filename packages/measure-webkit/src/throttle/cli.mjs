#!/usr/bin/env node
// node src/throttle/cli.mjs run [--site dir] [--arms original,rewrite,lift] [--rounds 2] [--cycles 4] [--vm n] [--out file]
//   Real touches on Mobile Safari in the booted Simulator (XCUITest driver) while the page records frames; one pass per arm and round, the
//   order rotated each round. original = the read-only snapshot; rewrite = the default prerendered build (--site); lift = the rewrite with
//   ?fw=engine.scroll:throttle-lift.
// node src/throttle/cli.mjs report --in a.json,b.json [--md file]   the still-run table and the verdict per job and pooled
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { withSession } from '../session.mjs';
import { watch } from '../watchdog.mjs';
import { findDevice } from '../sim.mjs';
import { buildDriver, cleanup, stop } from './driver.mjs';
import { armPass } from './probe.mjs';
import { reportMd } from './report.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest,
  options: {
    site: { type: 'string' }, arms: { type: 'string', default: 'rewrite,lift,original' }, rounds: { type: 'string', default: '2' },
    cycles: { type: 'string', default: '4' }, drag: { type: 'string', default: '360' }, velocity: { type: 'string', default: '120' },
    hold: { type: 'string', default: '600' }, settle: { type: 'string', default: '6000' }, vm: { type: 'string', default: '1' },
    out: { type: 'string' }, in: { type: 'string' }, md: { type: 'string' }, keep: { type: 'boolean', default: true },
  },
  allowNegative: true,
});
const log = (s) => console.error(s);
const LIFT_SEARCH = '?fw=engine.scroll:throttle-lift';
const siteOf = (arm) => {
  if (arm === 'original') return null;
  if (!v.site) throw new Error(`arm ${arm} needs --site (the prerendered build)`);
  return { dir: v.site, search: arm === 'lift' ? LIFT_SEARCH : '' };
};
/** Round r runs the arms rotated by r places. */
const rotate = (arms, r) => arms.map((_, i) => arms[(i + r) % arms.length]);

async function main() {
  switch (cmd) {
    case 'run': {
      const arms = v.arms.split(',');
      const udid = findDevice().udid;
      const driver = await buildDriver({ udid, log });
      const drag = { cycles: Number(v.cycles), dragPt: Number(v.drag), velocity: Number(v.velocity), holdMs: Number(v.hold) };
      const passes = [], failed = [];
      try {
        for (let round = 0; round < Number(v.rounds); round++) {
          for (const arm of rotate(arms, round)) {
            const tag = `${arm}-r${round + 1}`;
            try {
              const rec = await withSession((ctx) => armPass(ctx, { driver, udid, drag, settleMs: Number(v.settle), tag }),
                { keep: v.keep, site: siteOf(arm) });
              passes.push({ arm, round: round + 1, vm: v.vm, ...rec });
            } catch (e) { failed.push(`${tag}: ${e.message}`); log(`${tag} failed: ${e.message}`); }
          }
        }
      } finally { stop(); cleanup(driver); }
      const file = resolve(v.out ?? 'out/throttle.json');
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, JSON.stringify({ vm: v.vm, drag, passes, failed }) + '\n');
      log(`wrote ${file} (${passes.length} passes${failed.length ? `, ${failed.length} failed` : ''})`);
      if (!passes.length) throw new Error('no pass completed');
      break;
    }
    case 'report': {
      if (!v.in) throw new Error('usage: report --in a.json,b.json [--md file]');
      const vms = v.in.split(',').map((f, i) => {
        const j = JSON.parse(readFileSync(resolve(f), 'utf8'));
        return { vm: `job ${j.vm ?? i + 1}`, passes: j.passes };
      });
      const md = reportMd(vms);
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
