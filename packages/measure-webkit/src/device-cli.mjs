#!/usr/bin/env node
// Commands on the real measurement iPhone (see device.mjs). Run from this package:
//   node src/device-cli.mjs ping
//   node src/device-cli.mjs counts  --target original|rewrite [--site <dist/aot>] [--search '?...'] [--passes 3] [--out file]
//   node src/device-cli.mjs swipe  --target original|rewrite [--site ..] [--seconds 100] [--timeline] [--wait-light s] [--out file]  (a person swipes)
//   node src/device-cli.mjs plan                                        (the A/B/A steps and their banner texts)
//   node src/device-cli.mjs record --step k --target original|rewrite [--site ..] [--search ..] --out rec-k.json  (a person swipes; arm from the plan)
//   node src/device-cli.mjs reduce --in rec-1.json,rec-2.json,...      (Lean reductions + comparison; no phone)
//   node src/device-cli.mjs profile --in rec-k.json --id user-<name> --out ../measure-chromium/profiles/user-<name>.json
//   node src/device-cli.mjs package --kind session --in rec-1.json,... --date YYYY-MM-DD --out results/phone/<date>
//   node src/device-cli.mjs frames  --target original|rewrite [--site <dist/aot>] [--reps 5] [--speed 800] [--out file]
// Nothing is committed from here except via results/phone/*. The LAN address and device id are never printed or stored.
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { withPhone } from './device.mjs';
import { pageInfo, loadFresh } from './page.mjs';
import { phoneCounts, phoneFrames } from './device-runs.mjs';
import { simPasses, phonePasses, compareArms, compareMarkdown, stripCounts, poolFrames } from './device-compare.mjs';
import { summarizeFrames } from './device-runs.mjs';
import { phoneSwipe } from './device-swipe.mjs';
import { phoneRecord, stepOf } from './device-record.mjs';
import { PLAN, CONST, reducePass, compareZones, normalize } from './device-session.mjs';
import { readRecord, writeProfile, writePackage } from './device-profile.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest, allowNegative: true,
  options: {
    target: { type: 'string', default: 'original' }, site: { type: 'string' }, search: { type: 'string', default: '' },
    passes: { type: 'string', default: '3' }, reps: { type: 'string', default: '5' }, speed: { type: 'string', default: '800' },
    step: { type: 'string', default: '50' }, frames: { type: 'string', default: '2' }, settle: { type: 'string', default: '6000' },
    warmup: { type: 'string', default: '1' }, a: { type: 'string' }, in: { type: 'string' }, kind: { type: 'string' }, r: { type: 'string' }, sim: { type: 'string' }, seconds: { type: 'string', default: '100' }, timeline: { type: 'boolean', default: false }, 'wait-light': { type: 'string', default: '0' }, instruction: { type: 'string', default: 'Swipe with your finger from the TOP of the page to the BOTTOM at normal reading speed, then back to the top. Repeat.' }, out: { type: 'string' }, id: { type: 'string' }, date: { type: 'string' }, dpr: { type: 'string', default: '3' }, clock: { type: 'string', default: 'pinned' },
  },
});
const log = (s) => console.error(s);
const sessionOpts = { site: v.target === 'rewrite' ? { dir: v.site, search: v.search } : null, log };
if (v.target === 'rewrite' && !v.site) throw new Error('--target rewrite needs --site <dist/aot>');
const save = (data) => {
  if (!v.out) return;
  mkdirSync(dirname(resolve(v.out)), { recursive: true });
  writeFileSync(resolve(v.out), JSON.stringify(data, null, 1) + '\n');
  log(`wrote ${v.out}`);
};

async function main() {
  switch (cmd) {
    case 'ping': {
      const r = await withPhone(async (ctx) => ({ device: ctx.device, info: await pageInfo(ctx.c), readout: ctx.readout() }), sessionOpts);
      console.log(JSON.stringify(r));
      break;
    }
    case 'counts': {
      const r = await withPhone((ctx) => phoneCounts(ctx, { passes: Number(v.passes), warmup: Number(v.warmup), step: Number(v.step), framesPerStep: Number(v.frames), settleMs: Number(v.settle), clock: v.clock, loadFresh, log: ctx.log }), sessionOpts);
      save({ target: v.target, ...r });
      break;
    }
    case 'frames': {
      const r = await withPhone((ctx) => phoneFrames(ctx, { reps: Number(v.reps), speed: Number(v.speed), settleMs: Number(v.settle), clock: v.clock, loadFresh, log: ctx.log }), sessionOpts);
      save({ target: v.target, ...r });
      break;
    }
    case 'swipe': {
      const r = await withPhone((ctx) => phoneSwipe(ctx, { seconds: Number(v.seconds), timeline: v.timeline, waitLightS: Number(v['wait-light']), instruction: v.instruction, loadFresh, clock: v.clock, settleMs: Number(v.settle), log: ctx.log }), sessionOpts);
      save({ target: v.target, ...r });
      console.log(JSON.stringify({ arm: r.arm, appearance: r.appearance, frames: r.frames, reachedY: r.reachedY, maxY: r.maxY, total: r.summary.total }));
      break;
    }
    case 'plan': {
      for (const s of PLAN) console.log(`${s.step}. [${s.arm}] ${s.text}`);
      break;
    }
    case 'record': {
      const step = stepOf(Number(v.step));
      const pass = PLAN.filter((s) => s.arm === step.arm && s.step <= step.step).length;
      if ((step.arm === 'original') !== (v.target === 'original')) throw new Error(`step ${step.step} is arm ${step.arm}: --target must be ${step.arm === 'original' ? 'original' : 'rewrite'}`);
      if (step.arm === 'look' && !v.search) throw new Error('the look-change arm needs --search ?fw=part:variant,... (chosen by the lead)');
      const search = v.search || (step.arm === 'v2' ? '?preset=v2-proved' : '');
      const opts = { site: v.target === 'rewrite' ? { dir: v.site, search } : null, log };
      const r = await withPhone((ctx) => phoneRecord(ctx, { arm: step.arm, pass, seconds: step.seconds, text: step.text, waitLightS: Number(v['wait-light']), loadFresh, clock: v.clock, settleMs: Number(v.settle), log: ctx.log }), opts);
      save(r);
      const sum = reducePass(normalize(r));
      console.log(JSON.stringify({ arm: r.arm, pass: r.pass, frames: r.frames.t.length, maxY: r.maxY, taps: sum.taps, felt: sum.felt.length, total: sum.total }));
      break;
    }
    case 'reduce': {
      const recs = (v.in || '').split(',').filter(Boolean).map((f) => readRecord(resolve(f)));
      const reports = recs.map((r) => ({ arm: r.arm, pass: r.pass, report: reducePass(r) }));
      const cmp = compareZones(reports);
      save({ thresholdsMs: [CONST.slow / 100, CONST.bad / 100], reports: reports.map((x) => ({ arm: x.arm, pass: x.pass, ...x.report })), compare: cmp });
      console.log(JSON.stringify({ passes: reports.length, compare: cmp.map((z) => ({ zone: z.zone, original: z.original, arms: z.arms.map((a) => `${a.arm}:${a.verdict}`) })) }));
      break;
    }
    case 'profile': {
      if (!v.id || !v.in || !v.out) throw new Error('profile needs --in <record> --id user-<name> --out <file>');
      const p = writeProfile(resolve(v.in), resolve(v.out), { id: v.id, dpr: Number(v.dpr) });
      console.log(JSON.stringify({ id: p.id, strokes: p.input.strokes.length, maxFrames: p.input.maxFrames, feltFrames: p.input.feltFrames }));
      break;
    }
    case 'compare': {
      // compare --a phone-original.json --r phone-rewrite.json [--sim simulator-determinism.json] --out DIR : tables, no phone needed
      const rd = (f) => JSON.parse(readFileSync(resolve(f), 'utf8'));
      const arms = { 'phone original': phonePasses(rd(v.a)) };
      if (v.sim) arms['simulator original'] = simPasses(rd(v.sim));
      if (v.r) arms['phone rewrite'] = phonePasses(rd(v.r));
      const cmp = compareArms(arms);
      save(cmp);
      console.log(compareMarkdown(cmp));
      break;
    }
    case 'package': {
      // package --kind counts|frames --in a.json[,b.json...] --out file : drop raw passes / timestamps for committing
      if (v.kind === 'session') {
        // package --kind session --in rec-1.json,... --date YYYY-MM-DD --out results/phone/<date> : reports and comparison, no timestamps, no device
        if (!v.date || !v.out) throw new Error('package --kind session needs --date and --out <dir>');
        const pkg = writePackage((v.in || '').split(',').filter(Boolean).map((f) => resolve(f)), resolve(v.out), { date: v.date });
        console.log(JSON.stringify({ passes: pkg.passes.length, out: v.out }));
        break;
      }
      const rd = (f) => JSON.parse(readFileSync(resolve(f), 'utf8'));
      const files = (v.in || '').split(',').filter(Boolean).map(rd);
      save(v.kind === 'frames' ? poolFrames(files, summarizeFrames) : stripCounts(files[0]));
      break;
    }
    default:
      console.error('usage: ping | counts | frames | swipe | plan | record | reduce | profile | compare | package [--target original|rewrite] [--site dist/aot] [--search ?..] [--passes n] [--reps n] [--speed px/s] [--out file]');
      process.exitCode = 2;
  }
}
main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = 1; });
