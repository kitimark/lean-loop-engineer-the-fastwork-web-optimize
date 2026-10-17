#!/usr/bin/env node
// Commands on the real measurement iPhone (see device.mjs). Run from this package:
//   node src/device-cli.mjs ping
//   node src/device-cli.mjs counts  --target original|rewrite [--site <dist/aot>] [--search '?...'] [--passes 3] [--out file]
//   node src/device-cli.mjs swipe  --target original|rewrite [--site ..] [--seconds 100] [--timeline] [--wait-light s] [--out file]  (a person swipes)
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

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest, allowNegative: true,
  options: {
    target: { type: 'string', default: 'original' }, site: { type: 'string' }, search: { type: 'string', default: '' },
    passes: { type: 'string', default: '3' }, reps: { type: 'string', default: '5' }, speed: { type: 'string', default: '800' },
    step: { type: 'string', default: '50' }, frames: { type: 'string', default: '2' }, settle: { type: 'string', default: '6000' },
    warmup: { type: 'string', default: '1' }, a: { type: 'string' }, in: { type: 'string' }, kind: { type: 'string' }, r: { type: 'string' }, sim: { type: 'string' }, seconds: { type: 'string', default: '100' }, timeline: { type: 'boolean', default: false }, 'wait-light': { type: 'string', default: '0' }, instruction: { type: 'string', default: 'Swipe with your finger from the TOP of the page to the BOTTOM at normal reading speed, then back to the top. Repeat.' }, out: { type: 'string' }, clock: { type: 'string', default: 'pinned' },
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
      const rd = (f) => JSON.parse(readFileSync(resolve(f), 'utf8'));
      const files = (v.in || '').split(',').filter(Boolean).map(rd);
      save(v.kind === 'frames' ? poolFrames(files, summarizeFrames) : stripCounts(files[0]));
      break;
    }
    default:
      console.error('usage: ping | counts | frames | compare | package [--target original|rewrite] [--site dist/aot] [--search ?..] [--passes n] [--reps n] [--speed px/s] [--out file]');
      process.exitCode = 2;
  }
}
main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = 1; });
