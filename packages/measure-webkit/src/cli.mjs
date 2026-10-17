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
import { onePass, classifyPasses, markdownTable, resolveStates } from './determinism.mjs';
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
  keep: { type: 'boolean', default: false },
  vendors: { type: 'string', default: 'off' },
  'no-seek': { type: 'boolean', default: false },
};
const { values: v, positionals } = parseArgs({ args: rest, options: OPTS, allowPositionals: true });
const num = (s) => Number(s);
const log = (s) => console.error(s);

function save(name, data) {
  const file = v.out ? resolve(v.out) : resolve(OUT, `${name}-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(data, null, 1) + '\n');
  log(`wrote ${file}`);
  return file;
}
const sessionOpts = { keep: v.keep, vendors: v.vendors };
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
        for (let i = 0; i < runs; i++) {
          log(`pass ${i + 1}/${runs}`);
          ps.push(await onePass(ctx, { states, clock: v.clock, settleMs: num(v.settle), holdMs: num(v.hold), paintWindowMs: num(v.window), step: num(v.step), framesPerStep: num(v.frames), seek: !v['no-seek'], seekNs: v.ns.split(',').map(num), log }));
        }
        return ps;
      }, sessionOpts);
      const rows = classifyPasses(passes);
      save('determinism', { runs, clock: v.clock, states, rows, summary: summarize(rows), passes });
      console.log(markdownTable(rows));
      break;
    }
    case 'merge': {
      // merge: classes of independent determinism sessions (JSON files from `determinism --out`), the worse one wins
      const rank = { deterministic: 0, stable: 1, quarantined: 2 };
      const sessions = positionals.map((f) => classifyPasses(JSON.parse(readFileSync(resolve(f), 'utf8')).passes)); // recomputed from the raw passes
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
