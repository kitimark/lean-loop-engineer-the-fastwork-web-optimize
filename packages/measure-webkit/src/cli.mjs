#!/usr/bin/env node
// pnpm --filter @fw/measure-webkit census -- --state 0
// pnpm --filter @fw/measure-webkit scroll
// pnpm --filter @fw/measure-webkit seek
// pnpm --filter @fw/measure-webkit determinism -- --runs 2
// pnpm --filter @fw/measure-webkit sim -- down
// Every command boots `fw-iphone-27` headless, serves the snapshot read-only on 127.0.0.1, runs, and shuts the
// Simulator down again (unless --keep). Results are written to out/ (gitignored) as JSON.
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { withSession, simDown } from './session.mjs';
import { loadFresh, pageInfo } from './page.mjs';
import { censusAt } from './census.mjs';
import { scrollRun } from './scrollrun.mjs';
import { seekExperiment } from './seek.mjs';
import { probe } from './rfprobe.mjs';
import { screenAndTicks } from './handoff.mjs';
import { warmUpLoad, perStepPasses, classifyModes, perStepTable } from './perstep.mjs';
import { quietPasses } from './quiet.mjs';
import { byArm, armsTable, devCorrelation } from './quietreport.mjs';
import { onePassRetrying, classifyPasses, reasonNames, markdownTable, resolveStates } from './determinism.mjs';
import { COUNT_TYPES, zones, summarize } from './reduce.mjs';

const OUT = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'out');
const argv = process.argv.slice(2).filter((a) => a !== '--');
const [cmd, ...rest] = argv;
const OPTS = {
  state: { type: 'string', default: '0' },
  clock: { type: 'string', default: 'pinned' },
  hold: { type: 'string', default: '1500' },
  settle: { type: 'string', default: '6000' },
  window: { type: 'string', default: '2000' },
  step: { type: 'string', default: '50' },
  frames: { type: 'string', default: '2' },
  idle: { type: 'string', default: '0' },
  ns: { type: 'string', default: '0,10,50,100' },
  runs: { type: 'string', default: '2' },
  out: { type: 'string' },
  keep: { type: 'boolean', default: true }, // the Simulator stays booted between commands; --no-keep or `sim down` shuts it down
  vendors: { type: 'string', default: 'off' },
  seek: { type: 'boolean', default: true }, // --no-seek skips the seek fixture
  modes: { type: 'string', default: 'base,lock,hold,lock+hold' },
  site: { type: 'string' },
  search: { type: 'string', default: '' },
  mode: { type: 'string', default: 'base' },
  warmup: { type: 'string', default: '1' },
  arms: { type: 'string', default: '0,1,3' }, // quiet: busy-loop processes per arm
  reps: { type: 'string', default: '3' }, // quiet: rounds (each round runs every arm once)
  cols: { type: 'string' }, // handoff: comma list of count types forming the vector (default all 12)
};
const { values: v, positionals } = parseArgs({ args: rest, options: OPTS, allowPositionals: true, allowNegative: true });
const num = (s) => Number(s);
const log = (s) => console.error(s);

function save(name, data) {
  const file = v.out ? resolve(v.out) : resolve(OUT, `${name}-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(data, null, 1) + '\n');
  log(`wrote ${file}`);
  return file;
}
const sessionOpts = { keep: v.keep, vendors: v.vendors, site: v.site ? { dir: v.site, search: v.search } : null };
if (!['pinned', 'live'].includes(v.clock)) throw new Error('--clock is pinned or live');

async function main() {
  switch (cmd) {
    case 'census': {
      const res = await withSession(async (ctx) => {
        await loadFresh(ctx.c, { clock: v.clock, settleMs: num(v.settle) });
        const info = await pageInfo(ctx.c);
        const out = [];
        for (const y of resolveStates(v.state, info.maxY)) out.push(await censusAt(ctx.c, y, { holdMs: num(v.hold), paintWindowMs: num(v.window) }));
        return { info, clock: v.clock, censuses: out };
      }, sessionOpts);
      save('census', res);
      for (const c of res.censuses) {
        console.log(`y=${c.scrollY}: ${c.layerCount} layers, ${c.memoryBytes} backing bytes, paintCount ${c.paintCountTotal} (+${c.paintDeltaTotal} in ${c.paintWindowMs} ms, ${c.newLayersInWindow} new layers)`);
        console.log(`  reasons: ${JSON.stringify(c.reasonCounts)}`);
      }
      break;
    }
    case 'scroll': {
      const res = await withSession(async (ctx) => {
        await loadFresh(ctx.c, { clock: v.clock, settleMs: num(v.settle) });
        return scrollRun(ctx.c, { step: num(v.step), framesPerStep: num(v.frames), idleMs: num(v.idle) });
      }, sessionOpts);
      save('scroll', res);
      console.log(`steps ${res.ys.length} (step ${res.step} px, ${res.framesPerStep} rAF each), wall ${res.scrollWallMs} ms`);
      console.log(`total: ${JSON.stringify(res.reduced.total)}`);
      console.log('zone(500px): ' + COUNT_TYPES.slice(0, 5).join(', '));
      for (const z of zones(res.ys, res.reduced.perStep, res.reduced.perStepPaintArea)) console.log(`  y0=${z.y0}: ${z.counts.slice(0, 5).join(', ')} paintArea ${z.paintArea}`);
      break;
    }
    case 'seek': {
      const res = await withSession(async (ctx) => {
        await loadFresh(ctx.c, { clock: v.clock, settleMs: 500 });
        const r = await seekExperiment(ctx.c, `${ctx.base}/__fixtures/seek.html`, { ns: v.ns.split(',').map(num), log });
        ctx.setClient(r.conn);
        return r.rows;
      }, sessionOpts);
      save('seek', res);
      console.log('n | accelerated layers | style/step free | style/step seeked | layout free/seeked | paint free/seeked | composite free/seeked');
      for (const r of res) {
        const f = (a) => (a.reduced.total.RecalculateStyles / a.steps).toFixed(2);
        console.log(`${r.n} | ${r.layersWithAnimationReason} | ${f(r.free)} | ${f(r.seeked)} | ${r.free.reduced.total.Layout}/${r.seeked.reduced.total.Layout} | ${r.free.reduced.total.Paint}/${r.seeked.reduced.total.Paint} | ${r.free.reduced.total.Composite}/${r.seeked.reduced.total.Composite}`);
      }
      break;
    }
    case 'determinism': {
      const runs = num(v.runs);
      const states = v.state === '0' ? '0,1500,3000,4500,max' : v.state;
      const passes = await withSession(async (ctx) => {
        const ps = [];
        for (let w = 0; w < num(v.warmup); w++) await warmUpLoad(ctx, { clock: v.clock, settleMs: num(v.settle), step: num(v.step), framesPerStep: num(v.frames), log, w, warmup: num(v.warmup) });
        for (let i = 0; i < runs; i++) {
          log(`pass ${i + 1}/${runs}`);
          ps.push(await onePassRetrying(ctx, { states, clock: v.clock, settleMs: num(v.settle), holdMs: num(v.hold), paintWindowMs: num(v.window), step: num(v.step), framesPerStep: num(v.frames), mode: v.mode, seek: v.seek, seekNs: v.ns.split(',').map(num), log }));
        }
        return ps;
      }, sessionOpts);
      const rows = classifyPasses(passes);
      save('determinism', { runs, clock: v.clock, states, rows, summary: summarize(rows), passes });
      console.log(markdownTable(rows));
      break;
    }
    case 'quiet': {
      // webkit-quiet: dose-response of per-step jitter against added host load (see quiet.mjs)
      const arms = v.arms.split(',').map(num);
      const passes = await withSession((ctx) => quietPasses(ctx, { arms, reps: num(v.reps), clock: v.clock, settleMs: num(v.settle), step: num(v.step), framesPerStep: num(v.frames), log, warmup: num(v.warmup), mode: v.mode }), sessionOpts);
      save('quiet', { schema: 'fw.webkit.quiet/1', arms, reps: num(v.reps), clock: v.clock, mode: v.mode, passes });
      break;
    }
    case 'quiet-report': {
      // quiet-report <quiet.json>...: Markdown dose-response tables (jitter between passes of the same arm and file)
      const files = positionals.map((f) => JSON.parse(readFileSync(resolve(f), 'utf8')));
      console.log(armsTable(byArm(files)));
      const c = devCorrelation(files), l = devCorrelation(files, 'lag');
      console.log('\n| count type | corr(count dev, log step dur dev) | corr(count dev, log1p lag dev) |\n|---|---|---|');
      for (const t of COUNT_TYPES) console.log(`| ${t} | ${c[t]} | ${l[t]} |`);
      break;
    }
    case 'perstep': {
      // per-step determinism experiment: every mode, R passes, from fresh loads; raw saved, then the class table
      const modes = v.modes.split(',');
      const entries = await withSession((ctx) => perStepPasses(ctx, { modes, runs: num(v.runs), clock: v.clock, settleMs: num(v.settle), step: num(v.step), framesPerStep: num(v.frames), warmup: num(v.warmup), log }), sessionOpts);
      save('perstep', { modes, runs: num(v.runs), clock: v.clock, site: v.site ? { search: v.search } : null, entries });
      console.log(perStepTable(classifyModes(entries)));
      break;
    }
    case 'perstep-report': {
      // classes over the passes of several perstep files (independent sessions); entries of the same mode are pooled
      const entries = positionals.flatMap((f) => JSON.parse(readFileSync(resolve(f), 'utf8')).entries);
      console.log(perStepTable(classifyModes(entries)));
      break;
    }
    case 'rfprobe': {
      const res = await withSession(async (ctx) => {
        await loadFresh(ctx.c, { clock: v.clock, settleMs: num(v.settle) });
        return probe(ctx.c, { log });
      }, sessionOpts);
      save('rfprobe', res);
      break;
    }
    case 'handoff': {
      // handoff <base.json> <var.json>...: fwcore `screen` (var vs base, per step) and `ticks` (hz 60) on `determinism` outputs
      const [baseFile, ...varFiles] = positionals;
      // a `determinism` file (passes) or a `perstep` file (entries of --mode)
      const scrolls = (f) => { const d = JSON.parse(readFileSync(resolve(f), 'utf8')); return d.passes ? d.passes.map((p) => p.scroll) : d.entries.filter((e) => e.mode === v.mode).map((e) => e.scroll); };
      const base = scrolls(baseFile);
      const out = { base: baseFile, mode: v.mode, cols: v.cols ?? 'all', countTypes: COUNT_TYPES, vars: [] };
      for (const f of varFiles) {
        const r = await screenAndTicks(base, scrolls(f), v.cols ? v.cols.split(',') : null);
        out.vars.push({ file: f, ...r });
        console.log(`${f}: ${JSON.stringify(r.tally)}`);
      }
      save('handoff', out);
      break;
    }
    case 'merge': {
      // merge: classes of independent determinism sessions (JSON files from `determinism --out`), the worse one wins
      const rank = { deterministic: 0, stable: 1, quarantined: 2 };
      const raw = positionals.map((f) => JSON.parse(readFileSync(resolve(f), 'utf8')).passes); // recomputed from the raw passes
      const reasons = [...new Set(raw.flatMap(reasonNames))].sort(); // same reason rows in every session
      const sessions = raw.map((passes) => classifyPasses(passes, { reasons }));
      const keyOf = (r) => `${r.family}|${r.metric}|${r.level}`;
      for (const rows of sessions) {
        if (rows.length !== sessions[0].length || rows.some((r, i) => keyOf(r) !== keyOf(sessions[0][i]))) throw new Error('sessions do not have the same rows (different states or passes?)');
      }
      const out = sessions[0].map((r, i) => {
        const classes = sessions.map((rows) => rows[i].cls);
        return { ...r, classes, cls: classes.reduce((w, x) => (rank[x] > rank[w] ? x : w)), agree: new Set(classes).size === 1 };
      });
      console.log('| family | count type | level | class (worst of sessions) | sessions agree |');
      console.log('|---|---|---|---|---|');
      for (const r of out) console.log(`| ${r.family} | ${r.metric} | ${r.level} | **${r.cls}** | ${r.agree ? 'yes' : r.classes.join(' / ')} |`);
      break;
    }
    case 'sim': {
      if (positionals[0] === 'down') simDown(log);
      else throw new Error('usage: sim down');
      break;
    }
    default:
      console.error('usage: census|scroll|seek|determinism|merge <a.json> <b.json>|sim down  [--state y[,y|max]] [--clock pinned|live] [--hold ms] [--settle ms] [--window ms] [--step px] [--frames n] [--ns a,b] [--runs n] [--out file] [--keep] [--vendors off|live] [--no-seek]');
      process.exitCode = 2;
  }
}
main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = 1; });
