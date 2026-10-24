#!/usr/bin/env node
// node src/throttle/cli.mjs run [--site dir] [--arms original,rewrite,lift,unthrottle] [--rounds 2] [--cycles 4] [--vm n] [--out file]
//   Real touches on Mobile Safari in the booted Simulator (XCUITest driver) while the page records frames; one pass per arm and round, the
//   order rotated each round. original = the read-only snapshot; rewrite = the default prerendered build (--site); lift = the rewrite with
//   ?fw=engine.scroll:throttle-lift; unthrottle = the rewrite with ?fw=engine.scroll:unthrottle; unthrottle-follow = ?fw=engine.scroll:unthrottle-follow
//   --mode finish: the page is scrolled to 300 px above its end, then real drags past the end open the morph panel and back (finish zone
//   counts, scrollY reversals while open, open lateness; --drag 480 --velocity 150 by default).
//   --rotate n rotates the first round's arm order by n (the workflow passes the job number - 1, so jobs start on different arms).
// node src/throttle/cli.mjs build-driver --dir d  build the touch driver once, before the Simulator boots (run --driver d uses it)
// node src/throttle/cli.mjs report --in a.json,b.json [--md file]   the still-run table and the verdict per job and pooled
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { withSession } from '../session.mjs';
import { watch } from '../watchdog.mjs';
import { findDevice, shutdownDevice } from '../sim.mjs';
import { loadavg } from 'node:os';
import { buildDriver, cleanup, dragPass, findDriver, stop } from './driver.mjs';
import { armPass } from './probe.mjs';
import { loadFresh } from '../page.mjs';
import { excludeReason, reportMd, ARMS, SHIPPED_ARM, FOLLOW_ARM } from './report.mjs';
import { movingMd } from './follow-report.mjs';
import { finishPass } from './finish-probe.mjs';
import { excludeReason as finishExclude, reportMd as finishMd } from './finish-report.mjs';
import { COMPOSITIONS } from './morph-end.mjs';
import { reportMd as morphEndMd } from './morph-end-report.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest,
  options: {
    site: { type: 'string' }, arms: { type: 'string', default: 'rewrite,lift,original' }, rounds: { type: 'string', default: '2' },
    cycles: { type: 'string', default: '4' }, timeout: { type: 'string', default: '300' }, reset: { type: 'boolean', default: false }, rotate: { type: 'string', default: '0' }, drag: { type: 'string' }, velocity: { type: 'string' }, mode: { type: 'string', default: 'drags' },
    target: { type: 'string', default: 'springboard' }, hold: { type: 'string', default: '600' }, 'no-warmup': { type: 'boolean', default: false }, settle: { type: 'string', default: '6000' }, vm: { type: 'string', default: '1' },
    out: { type: 'string' }, dir: { type: 'string' }, driver: { type: 'string' }, in: { type: 'string' }, md: { type: 'string' }, keep: { type: 'boolean', default: true },
  },
  allowNegative: true,
});
const log = (s) => console.error(s);
const SEARCH = { lift: '?fw=engine.scroll:throttle-lift', unthrottle: '?fw=engine.scroll:unthrottle', 'unthrottle-follow': '?fw=engine.scroll:unthrottle-follow', ...COMPOSITIONS };
const KNOWN_ARMS = new Set(['original', ...Object.keys(SEARCH)]);
const MORPH_END_ARMS = new Set(Object.keys(COMPOSITIONS).filter((a) => a !== 'rewrite'));
const siteOf = (arm) => {
  if (arm === 'original') return null;
  if (!v.site) throw new Error(`arm ${arm} needs --site (the prerendered build)`);
  return { dir: v.site, search: SEARCH[arm] ?? '' };
};
const rotate = (arms, r) => arms.map((_, i) => arms[(i + r) % arms.length]);

async function main() {
  switch (cmd) {
    case 'run': {
      const arms = v.arms.split(',');
      const unknown = arms.filter((a) => !KNOWN_ARMS.has(a));
      if (unknown.length) throw new Error(`unknown arm ${unknown.join(', ')}; one of ${[...KNOWN_ARMS].join(', ')}`);
      const udid = findDevice().udid;
      const driver = v.driver ? findDriver(resolve(v.driver)) : await buildDriver({ udid, log });
      log(`load ${loadavg()[0].toFixed(0)} before the first pass`);
      if (!['drags', 'finish'].includes(v.mode)) throw new Error(`unknown --mode ${v.mode}; drags or finish`);
      const finish = v.mode === 'finish';
      const drag = { cycles: Number(v.cycles), dragPt: Number(v.drag ?? (finish ? 480 : 360)), velocity: Number(v.velocity ?? (finish ? 150 : 120)),
        holdMs: Number(v.hold), mode: v.mode, target: v.target, timeoutMs: Number(v.timeout) * 1000 };
      const passOf = finish ? finishPass : armPass;
      const reasonOf = finish ? finishExclude : excludeReason;
      const passes = [], failed = [];
      const file = resolve(v.out ?? 'out/throttle.json');
      mkdirSync(dirname(file), { recursive: true });
      // written after every pass: a stalled job still reports the passes it finished
      const save = () => writeFileSync(file, JSON.stringify({ vm: v.vm, drag, passes, failed }) + '\n');
      try {
        // The first session on a fresh Simulator drops its openurl and asks again, and the first XCUITest run relaunches Safari: both
        // reload the page after the recorder started (the first measured pass was lost that way in 4 of 6 CI jobs). One warm-up
        // session loads the page and runs one touch cycle, unrecorded, before the arms.
        if (!v['no-warmup']) {
          try {
            await withSession(async (ctx) => {
              await loadFresh(ctx.c, { clock: 'pinned', settleMs: 2000 });
              const r = await dragPass(driver, { udid, tag: 'warm-up', log, ...drag, cycles: 1 });
              log(`warm-up: touches ${r.code === 0 ? 'done' : `failed (code ${r.code})`}`);
            }, { keep: v.keep, site: siteOf(arms.find((a) => a !== 'original') ?? 'original') });
          } catch (e) { log(`warm-up failed: ${e.message}`); }
        }
        for (let round = 0; round < Number(v.rounds); round++) {
          for (const arm of rotate(arms, round + Number(v.rotate))) {
            for (let attempt = 1; attempt <= 2; attempt++) {
              if (attempt === 2 && v.reset) { try { shutdownDevice(udid, { log }); } catch (e) { log(`reset: ${e.message}`); } }
              const tag = `${arm}-r${round + 1}-a${attempt}`;
              try {
                const rec = await withSession((ctx) => passOf(ctx, { driver, udid, drag, settleMs: Number(v.settle), tag }),
                  { keep: v.keep, site: siteOf(arm) });
                const bad = reasonOf({ arm, round: round + 1, vm: v.vm, ...rec });
                if (bad && attempt < 2) { log(`${tag} not usable (${bad}); trying once more`); continue; }
                passes.push({ arm, round: round + 1, vm: v.vm, attempt, ...rec });
                break;
              } catch (e) {
                log(`${tag} failed: ${e.message}`);
                if (attempt === 2) failed.push(`${tag}: ${e.message}`);
              }
            }
            save();
          }
        }
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
      const jobs = v.in.split(',').map((f) => JSON.parse(readFileSync(resolve(f), 'utf8')));
      const vms = jobs.map((j, i) => ({ vm: `job ${j.vm ?? i + 1}`, passes: j.passes }));
      const isFinish = jobs.some((j) => j.drag?.mode === 'finish');
      const morphEnd = jobs.some((j) => j.passes.some((p) => MORPH_END_ARMS.has(p.arm)));
      const present = [...Object.values(ARMS), SHIPPED_ARM, FOLLOW_ARM].filter((a) => vms.some((x) => x.passes.some((p) => p.arm === a)));
      const md = morphEnd ? morphEndMd(vms) : (isFinish ? finishMd : reportMd)(vms) + (isFinish ? '' : movingMd(vms, present));
      if (v.md) writeFileSync(resolve(v.md), md); else console.log(md);
      break;
    }
    default:
      console.error('usage: run|build-driver|report');
      process.exitCode = 2;
  }
}
const guard = watch();
main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = e.exitCode ?? 1; }).finally(() => guard.done(process.exitCode ?? 0));
