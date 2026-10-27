#!/usr/bin/env node
//   node src/device-replay-cli.mjs source   --in rec-1.json --id user-x --out source.json     (profile + zone data of a recording; local only)
//   node src/device-replay-cli.mjs make     --source source.json --kind recorded|fast-fling|zone-hero|zone-finish|cold [--n 5] [--gap 300] [--reps 3] --out profile.json
//   node src/device-replay-cli.mjs compile  --profile profile.json [--out actions.json]       (W3C payload, tick statistics; no phone)
//   node src/device-replay-cli.mjs check    --profile profile.json --in replay-record.json    (replayMatches, conjuncts per swipe)
//   node src/device-replay-cli.mjs plan     --kinds recorded,fast-fling --reps 3 --arms 2     (the passes and the arm order of each)
//   node src/device-replay-cli.mjs run      --source source.json [--kinds recorded] [--reps 3] --out run.json [--sim <simulator udid>]  (the phone, or an iOS Simulator with --sim)
// Exit codes: 0 ok, 1 error, 2 usage, 3 a named replay error (replay-stall, wd-timeout): the message names the piece and the call that hung.
// The source file holds a person's finger path: keep it out of git (.local/ or the scratchpad).
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { rawResolve as resolve } from './device-raw-dir.mjs';
import { readRecord } from './device-profile.mjs';
import { replayStrokes, t0Of } from './device-session.mjs';
import { ofTouches, compile, w3c, actsMs, TICK_MAX, makeProfile, schedule, LIM, simulateEvents } from './device-replay.mjs';
import { checkRecord, wdClient, startSafaridriver, runSession, prepareSimulator } from './device-replay-wd.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v } = parseArgs({
  args: rest, allowNegative: true,
  options: {
    in: { type: 'string' }, id: { type: 'string' }, out: { type: 'string' }, source: { type: 'string' }, profile: { type: 'string' }, kind: { type: 'string', default: 'recorded' },
    kinds: { type: 'string', default: 'recorded' }, reps: { type: 'string', default: '3' }, arms: { type: 'string', default: '1' }, n: { type: 'string', default: '5' },
    gap: { type: 'string', default: '300' }, port: { type: 'string', default: '4444' }, base: { type: 'string' }, caps: { type: 'string', default: '{"browserName":"Safari","platformName":"iOS"}' },
    settle: { type: 'string', default: '6000' }, sim: { type: 'string' },
  },
});
const log = (s) => console.error(s);
const read = (f) => JSON.parse(readFileSync(resolve(f), 'utf8'));
const save = (data) => {
  if (!v.out) return;
  mkdirSync(dirname(resolve(v.out)), { recursive: true });
  writeFileSync(resolve(v.out), JSON.stringify(data) + '\n');
  log(`wrote ${v.out}`);
};
const toTenthMs = (ms) => Math.round(Number(ms) * 100);

async function main() {
  switch (cmd) {
    case 'source': {
      if (!v.in || !v.id) throw new Error('source needs --in <record> --id <name> [--out file]');
      const r = readRecord(resolve(v.in));
      const profile = ofTouches(v.id, r.touches, r.w, r.h);
      if (profile === null) throw new Error('a second finger was down in this pass: no single-finger replay can be made');
      const source = { profile, zone: { maxY10: r.maxY10, frames: r.t.map((t, i) => [t, r.y[i]]), t0: t0Of(replayStrokes(r.touches)) } };
      save(source);
      console.log(JSON.stringify({ id: profile.id, swipes: profile.swipes.length, frames: r.t.length }));
      break;
    }
    case 'make': {
      const p = makeProfile(read(v.source), v.kind, { n: Number(v.n), gap: toTenthMs(v.gap), reps: Number(v.reps) });
      if (p === null) throw new Error(`the recording has no swipe for kind ${v.kind}`);
      save(p);
      console.log(JSON.stringify({ id: p.id, load: p.load, swipes: p.swipes.length }));
      break;
    }
    case 'compile': {
      const p = read(v.profile);
      const acts = compile(p);
      const durs = acts.map((a) => (a[0] === 'm' ? a[3] : a[0] === 'p' ? a[1] : 0));
      save({ acts, w3c: w3c(acts) });
      console.log(JSON.stringify({ id: p.id, actions: acts.length, ms: actsMs(acts), maxTickMs: Math.max(0, ...durs), tickMax: TICK_MAX, events: simulateEvents(acts).length }));
      break;
    }
    case 'check': {
      const out = checkRecord({ rec: read(v.in), profile: read(v.profile) });
      save({ matches: out.matches, perSwipe: out.perSwipe, swipesSeen: out.rep.length, total: out.report.total });
      console.log(JSON.stringify({ matches: out.matches, swipes: out.perSwipe.length, failing: out.perSwipe.filter((c) => !c.swipe).length, seen: out.rep.length }));
      break;
    }
    case 'plan': {
      const kinds = v.kinds.split(',').filter(Boolean);
      for (const r of schedule(kinds, Number(v.reps), Number(v.arms))) console.log(`${r.kind} rep ${r.rep} arms ${r.order.join(',')}`);
      break;
    }
    case 'run': {
      const source = read(v.source);
      const urls = process.env.FW_REPLAY_URLS
        ? process.env.FW_REPLAY_URLS.split(',').map((e) => { const i = e.indexOf('='); return { name: e.slice(0, i), url: e.slice(i + 1) }; })
        : process.env.FW_REPLAY_URL ? [{ name: 'original', url: process.env.FW_REPLAY_URL }] : [];
      if (urls.length === 0) throw new Error('set FW_REPLAY_URL (one page) or FW_REPLAY_URLS (name=url,name=url)');
      const opts = { n: Number(v.n), gap: toTenthMs(v.gap), reps: Number(v.reps) };
      const driver = v.base ? { base: v.base, stop() {} } : await startSafaridriver(Number(v.port), { log });
      try {
        const wd = wdClient(driver.base);
        const caps = v.sim ? { ...JSON.parse(v.caps), 'safari:useSimulator': true, 'safari:deviceUDID': v.sim } : JSON.parse(v.caps);
        const prepare = v.sim ? () => prepareSimulator(v.sim, { log }) : null;
        const r = await runSession({ wd, caps, prepare, arms: urls, base: source.profile, kinds: v.kinds.split(',').filter(Boolean), reps: Number(v.reps), gen: { n: opts.n, gap: opts.gap, reps: opts.reps, zone: source.zone }, settleMs: Number(v.settle), log });
        save({ schema: 'fw.replay.run/1', lim: LIM, passes: r.passes });
        const ok = r.passes.filter((p) => p.report !== null);
        console.log(JSON.stringify({ passes: r.passes.length, matches: r.passes.filter((p) => p.matches).length, stalled: r.passes.filter((p) => p.stalled).map((p) => ({ arm: p.arm, ...p.stalled })), over34: ok.map((p) => p.report.total.over34), n: ok.map((p) => p.report.total.n) }));
        if (r.passes.some((p) => p.stalled)) process.exitCode = 3;
      } finally { driver.stop(); }
      break;
    }
    default:
      console.error('usage: source | make | compile | check | plan | run  (see the header of this file)');
      process.exitCode = 2;
  }
}
main().catch((e) => { console.error(`error${e.code ? ` [${e.code}]` : ''}: ${e.message}`); process.exitCode = e.code === 'replay-stall' || e.code === 'wd-timeout' ? 3 : 1; });
