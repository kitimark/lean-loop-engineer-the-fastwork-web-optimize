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
import { watch } from './watchdog.mjs';
import { alignPasses, scrollsOf, zoneTable, coverageLine, classifyAligned, classTable } from './align.mjs';
import { warmUpLoad, perStepPasses, classifyModes, perStepTable } from './perstep.mjs';
import { quietPasses } from './quiet.mjs';
import { byArm, armsTable, devCorrelation } from './quietreport.mjs';
import { onePassRetrying, classifyPasses, markdownTable, resolveStates, pinStates } from './determinism.mjs';
import { mergeSessions, unpairedTable } from './mergerows.mjs';
import { COUNT_TYPES, zones, summarize } from './reduce.mjs';
import { censusVerdict } from './census-check.mjs';
import { runsOf, reportRuns } from './census-check-cli.mjs';

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
  types: { type: 'string', default: 'RecalculateStyles,Layout,Paint,Composite' }, // align: count types printed as tables
  'zone-px': { type: 'string', default: '500' }, // align: zone height
  composite: { type: 'string', default: 'none' },
  snap: { type: 'string', default: 'none' },
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
          ps.push(await onePassRetrying(ctx, { states: i === 0 ? states : pinStates(ps[0]), clock: v.clock, settleMs: num(v.settle), holdMs: num(v.hold), paintWindowMs: num(v.window), step: num(v.step), framesPerStep: num(v.frames), mode: v.mode, seek: v.seek, seekNs: v.ns.split(',').map(num), log }));
        }
        return ps;
      }, sessionOpts);
      const rows = classifyPasses(passes);
      const layerCensus = censusVerdict(passes, { composite: v.composite, snap: v.snap });
      // site: what was served (the rewrite arm: the query and the prerendered config's hash); null = the snapshot
      save('determinism', { runs, clock: v.clock, states, site: sessionOpts.site ? { search: v.search, configHash: sessionOpts.site.configHash ?? null } : null, rows, summary: summarize(rows), layerCensus, passes });
      console.log(markdownTable(rows));
      console.log(`layer census: ${layerCensus.state}`);
      for (const p of layerCensus.pairs) for (const l of [`${p.pair}: ${p.state}`, ...p.lines.map((s) => `  ${s}`)]) console.log(l);
      break;
    }
    case 'census-check': {
      const runs = positionals.flatMap((f) => runsOf(f.split('/').pop(), JSON.parse(readFileSync(resolve(f), 'utf8'))));
      const rep = reportRuns(runs, { composite: v.composite, snap: v.snap });
      console.log(`layer census: ${rep.state}`);
      console.log(rep.lines.join('\n'));
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
    case 'align': {
      // align <a.json> <r.json>: pass i of A against pass i of R by scroll position (fwcore measure.webkit.align); a `determinism`
      // or `perstep` file on each side. A zone is comparable as a whole when `full`.
      const [aFile, rFile] = positionals;
      if (!aFile || !rFile) throw new Error('usage: align <a.json> <r.json> [--types t1,t2] [--zone-px 500] [--out file] [--mode base]');
      const read = (f) => JSON.parse(readFileSync(resolve(f), 'utf8'));
      const aScrolls = scrollsOf(read(aFile), v.mode), rScrolls = scrollsOf(read(rFile), v.mode);
      const res = await alignPasses(aScrolls, rScrolls, num(v['zone-px']));
      res.pairs.forEach((p, i) => console.log(`pass ${i + 1}: ${coverageLine(p, aScrolls[i].ys.length, rScrolls[i].ys.length)}`));
      for (const t of v.types.split(',')) console.log(`\n${zoneTable(res.pairs, t)}`);
      if (v.out) save('align', { schema: 'fw.webkit.align/1', a: aFile, r: rFile, zonePx: num(v['zone-px']), passes: res.passes, pairs: res.pairs });
      break;
    }
    case 'align-classes': {
      // align-classes <a1.json> <r1.json> <a2.json> <r2.json> ...: every pass of every pair aligned, then the zone sums of the full zones
      // classified over all passes (deterministic / stable / quarantined) for the A arm, the R arm and the delta.
      if (positionals.length < 2 || positionals.length % 2) throw new Error('usage: align-classes <a1.json> <r1.json> [<a2.json> <r2.json> ...] [--types t1,t2] [--zone-px 500] [--out file]');
      const read = (f) => JSON.parse(readFileSync(resolve(f), 'utf8'));
      const pairs = [];
      for (let i = 0; i < positionals.length; i += 2) pairs.push(...(await alignPasses(scrollsOf(read(positionals[i]), v.mode), scrollsOf(read(positionals[i + 1]), v.mode), num(v['zone-px']))).pairs);
      const res = classifyAligned(pairs);
      console.log(`passes ${pairs.length} (${positionals.length / 2} file pairs)\n\n${classTable(res, v.types.split(','))}`);
      if (v.out) save('align-classes', { schema: 'fw.webkit.align-classes/1', files: positionals, zonePx: num(v['zone-px']), ...res });
      break;
    }
    case 'merge': {
      // merge: classes of independent determinism sessions (JSON files from `determinism --out`), the worse one wins.
      // Rows are matched by key; rows not every session has are listed as unpaired (Lean: StepAlign.pairedRows)
      const raw = positionals.map((f) => JSON.parse(readFileSync(resolve(f), 'utf8')).passes); // recomputed from the raw passes
      const { sessions, out, unpaired } = await mergeSessions(raw);
      console.log('| family | count type | level | class (worst of sessions) | sessions agree |');
      console.log('|---|---|---|---|---|');
      for (const r of out) console.log(`| ${r.family} | ${r.metric} | ${r.level} | **${r.cls}** | ${r.agree ? 'yes' : r.classes.join(' / ')} |`);
      if (unpaired.length) console.log(unpairedTable(unpaired));
      if (v.out) { // machine-readable table for the baselines: scroll rows by level, {class, per-session classes, worst spread}
        const level = (l) => (l === 'total' ? 'total' : l === 'per 500 px zone' ? 'zone' : l === 'per step' ? 'step' : null);
        const byLevel = { total: {}, zone: {}, step: {} };
        for (const r of out) {
          const lv = r.family === 'scroll' ? level(r.level) : null;
          if (lv) byLevel[lv][r.metric] = { class: r.cls, sessions: r.classes, maxSpread: Math.max(...r.at.map((i, s) => sessions[s][i].maxSpread ?? 0)), maxRelSpread: Math.max(...r.at.map((i, s) => sessions[s][i].maxRelSpread ?? 0)) };
        }
        save('classes', { schema: 'fw.webkit.classes/1', sessions: sessions.length, passesPerSession: raw.map((p) => p.length), byLevel, rows: out.map(({ family, metric, level: lv, cls, classes }) => ({ family, metric, level: lv, class: cls, sessions: classes })), unpaired });
      }
      break;
    }
    case 'sim': {
      if (positionals[0] === 'down') simDown(log);
      else throw new Error('usage: sim down');
      break;
    }
    default:
      console.error('usage: census|scroll|seek|determinism|align <a.json> <r.json>|align-classes <a.json> <r.json>...|merge <a.json> <b.json>|sim down  [--state y[,y|max]] [--clock pinned|live] [--hold ms] [--settle ms] [--window ms] [--step px] [--frames n] [--ns a,b] [--runs n] [--out file] [--keep] [--vendors off|live] [--no-seek]');
      process.exitCode = 2;
  }
}
// Fail fast: a stall (no output for 90 s x FW_WK_TIMEOUT_SCALE, FW_WK_STALL_MS overrides) or a process that outlives its command
// ends with a message saying why, instead of sitting until the CI step timeout (watchdog.mjs).
const guard = watch();
main().catch((e) => { console.error(`error: ${e.message}`); process.exitCode = e.exitCode ?? 1; }).finally(() => guard.done(process.exitCode ?? 0));
