#!/usr/bin/env node
// Commands on the real measurement iPhone (see device.mjs). Run from this package:
//   node src/device-cli.mjs ping
//   node src/device-cli.mjs counts  --target original|rewrite [--site <dist/aot>] [--search '?...'] [--passes 3] [--out file]
//   node src/device-cli.mjs swipe  --target original|rewrite [--site ..] [--seconds 100] [--timeline] [--wait-light s] [--out file]  (a person swipes)
//   node src/device-cli.mjs plan --search '?fw=part:variant,...'       (the A/B/A steps and banner texts; an arm that loads the same page as an earlier one is dropped)
//   node src/device-cli.mjs record --step k --target original|rewrite [--site ..] --search '?fw=..' --out rec-k.json  (a person swipes; arm from the plan; --search is the look-change arm's flags)
//   node src/device-cli.mjs reduce --in rec-1.json,rec-2.json,...      (Lean reductions + comparison; no phone)
//   node src/device-cli.mjs profile --in rec-k.json --id user-<name> --out ../measure-chromium/profiles/user-<name>.json
//   node src/device-cli.mjs package --kind session --in rec-1.json,... --date YYYY-MM-DD --out results/phone/<date>
//   node src/device-cli.mjs frames  --target original|rewrite [--site <dist/aot>] [--reps 5] [--speed 800] [--out file]
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
import { CONST, reducePass, compareZones, normalize } from './device-session.mjs';
import { sessionPlan, armSearch } from './device-arms.mjs';
import { readRecord, writeProfile, writePackage } from './device-profile.mjs';
import { planText, runBlock, reduceDir, handResetCommand, phoneSense } from './device-phone-run.mjs';
import { pinnedSession } from './device-phone-pin.mjs';
import { ConditionOwner, PIN, pinGate } from './device-thermal-pin.mjs';
import * as PA from './device-phone-arms.mjs';
import { readThermal } from './device-thermal.mjs';
import { listPhone, readout } from './device.mjs';

const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const { values: v, positionals } = parseArgs({
  args: rest, allowNegative: true, allowPositionals: true,
  options: {
    target: { type: 'string', default: 'original' }, site: { type: 'string' }, search: { type: 'string', default: '' },
    passes: { type: 'string', default: '3' }, reps: { type: 'string', default: '5' }, speed: { type: 'string', default: '800' },
    step: { type: 'string', default: '50' }, frames: { type: 'string', default: '2' }, settle: { type: 'string', default: '6000' },
    warmup: { type: 'string', default: '1' }, a: { type: 'string' }, in: { type: 'string' }, kind: { type: 'string' }, r: { type: 'string' }, sim: { type: 'string' }, seconds: { type: 'string', default: '100' }, timeline: { type: 'boolean', default: false }, 'wait-light': { type: 'string', default: '0' }, instruction: { type: 'string', default: 'Swipe with your finger from the TOP of the page to the BOTTOM at normal reading speed, then back to the top. Repeat.' }, out: { type: 'string' }, dir: { type: 'string' }, all: { type: 'boolean', default: false }, blocked: { type: 'string' }, 'hand-reset': { type: 'string' }, reason: { type: 'string' }, only: { type: 'string' }, pin: { type: 'string' }, hold: { type: 'string', default: '0' }, 'max-visits': { type: 'string' }, id: { type: 'string' }, date: { type: 'string' }, dpr: { type: 'string', default: '3' }, clock: { type: 'string', default: 'pinned' },
  },
});
const log = (s) => console.error(s);
const only = () => (v.only ? PA.sessionOf(v.only.split(',').map((x) => x.trim()).filter(Boolean)) : PA.SESSION);
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
    case 'thermal': {
      const id = listPhone().udid;
      const t = readThermal(id);
      const b = readout(id, { thermal: () => t });
      const r = { at: b.at, state: t.state, lock: t.lock, batteryC: b.batteryVirtualTemp, batteryPct: b.batteryPct, charging: b.charging, source: b.thermalSource, ...(t.error ? { error: t.error } : {}) };
      save(r);
      console.log(JSON.stringify(r));
      break;
    }
    case 'arms-plan': {
      if (!v.site) throw new Error('arms-plan needs --site <dist/aot>');
      console.log(planText(resolve(v.site), only()));
      break;
    }
    case 'arms-run': {
      if (v['hand-reset'] !== undefined) {
        if (!v.dir) throw new Error('arms-run --hand-reset <index> <reason> needs --dir <raw dir>');
        const st = handResetCommand(resolve(v.dir), v['hand-reset'], v.reason ?? positionals[0]);
        console.log(JSON.stringify({ handReset: v['hand-reset'], notes: st.leadReset.length }));
        break;
      }
      if (!v.site || !v.dir) throw new Error('arms-run needs --site <dist/aot> and --dir <raw dir>');
      const runBlocks = async (pin) => {
        for (;;) {
          const r = await runBlock({ site: resolve(v.site), dir: resolve(v.dir), log, clock: v.clock, settle: Number(v.settle), blocked: v.blocked ? resolve(v.blocked) : null, session: only(), pin, ...(v['max-visits'] ? { maxVisits: Number(v['max-visits']) } : {}) });
          console.log(JSON.stringify({ ran: r.ran.length, remaining: r.remaining, stopped: r.stopped }));
          if (r.stopped) { process.exitCode = 3; break; }
          if (!v.all || r.remaining <= 0 || r.ran.length === 0) break;
        }
      };
      try {
        if (v.pin) await pinnedSession({ target: v.pin, dir: resolve(v.dir), log, owner: new ConditionOwner({ dir: resolve(v.dir), log }), sense: phoneSense(), body: runBlocks });
        else await runBlocks(null);
      } catch (e) { log(`error: ${e.message}`); process.exitCode = 1; }
      process.exit(process.exitCode ?? 0);
    }
    case 'pin-probe': {
      // pin-probe --pin Serious --dir <dir> [--hold s]: induce, read it back until it is the target, hold, clear, read back. No visit runs.
      if (!v.pin || !v.dir) throw new Error('pin-probe needs --pin Fair|Serious and --dir <dir>');
      const sense = phoneSense();
      const readings = [];
      try {
        await pinnedSession({ target: v.pin, dir: resolve(v.dir), log, owner: new ConditionOwner({ dir: resolve(v.dir), log }), sense, body: async (pin) => {
          const t0 = Date.now();
          for (;;) {
            const s = sense();
            const waitedS = Math.round((Date.now() - t0) / 1000);
            const verdict = pinGate(pin.target, pin.held(), s.lock, s.state, readings.some((r) => r.verdict === 'go'), waitedS);
            readings.push({ at: new Date().toISOString(), state: s.state, tempC: s.tempC ?? null, lock: s.lock, held: pin.held(), verdict });
            log(JSON.stringify(readings[readings.length - 1]));
            if (verdict === 'go') pin.onHeld();
            if (verdict === 'stop') throw new Error(`pin-probe stopped: ${s.state ?? 'unreadable'}`);
            if (verdict === 'go' && (Date.now() - t0) / 1000 >= Number(v.hold)) break;
            await new Promise((r) => setTimeout(r, PIN.pinPollS * 1000));
          }
        } });
      } catch (e) { log(`error: ${e.message}`); process.exitCode = 1; }
      console.log(JSON.stringify({ readings: readings.length, states: readings.map((r) => r.state) }));
      process.exit(process.exitCode ?? 0);
    }
    case 'pin-stop': {
      // pin-stop --dir <dir>: stop an owner an earlier run left behind (pid and start time must match the record).
      if (!v.dir) throw new Error('pin-stop needs --dir <dir>');
      const owner = new ConditionOwner({ dir: resolve(v.dir), log });
      const did = await owner.recover();
      console.log(JSON.stringify({ stopped: did }));
      break;
    }
    case 'arms-reduce': {
      if (!v.dir || !v.out) throw new Error('arms-reduce needs --dir <raw dir> and --out <dir>');
      const s = reduceDir({ dir: resolve(v.dir), out: resolve(v.out) });
      console.log(JSON.stringify({ visits: s.visits.length, notRun: s.notRun, anomalies: s.anomalies, arms: s.arms.map((a) => `${a.id}: counts ${a.labels.counts.all}, frames ${a.labels.frames.all}`) }));
      break;
    }
    case 'plan': {
      const sp = sessionPlan(v.search);
      for (const s of sp.plan) console.log(`${s.step}. [${s.arm}] ${s.text}`);
      for (const d of sp.dropped) console.error(`dropped arm ${d.arm}: it loads the same page as ${d.sameAs} (flags [${d.flags}]); no pass is spent on it`);
      break;
    }
    case 'record': {
      const sp = sessionPlan(v.search);
      const step = stepOf(Number(v.step), sp.plan);
      const pass = sp.plan.filter((s) => s.arm === step.arm && s.step <= step.step).length;
      if ((step.arm === 'original') !== (v.target === 'original')) throw new Error(`step ${step.step} is arm ${step.arm}: --target must be ${step.arm === 'original' ? 'original' : 'rewrite'}`);
      const search = step.arm === 'original' ? '' : armSearch(step.arm, v.search);
      const opts = { site: v.target === 'rewrite' ? { dir: v.site, search } : null, log };
      const r = await withPhone((ctx) => phoneRecord(ctx, { arm: step.arm, pass, seconds: step.seconds, text: step.text, waitLightS: Number(v['wait-light']), loadFresh, clock: v.clock, settleMs: Number(v.settle), log: ctx.log }), opts);
      save(r);
      const sum = reducePass(normalize(r));
      console.log(JSON.stringify({ arm: r.arm, pass: r.pass, frames: r.frames.t.length, maxY: r.maxY, taps: sum.taps, felt: sum.felt.length, zoomFrames: r.zoom?.frames ?? 0, total: sum.total }));
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
      console.error('usage: ping | counts | frames | swipe | plan | record | reduce | profile | compare | package | arms-plan | thermal | arms-run [--only <arm ids>] [--pin Fair|Serious] [--hand-reset <index> <reason>] | pin-probe --pin Serious --dir d [--hold s] | pin-stop --dir d | arms-reduce [--target original|rewrite] [--site dist/aot] [--search ?..] [--passes n] [--reps n] [--speed px/s] [--out file]');
      process.exitCode = 2;
  }
}
main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = 1; });
