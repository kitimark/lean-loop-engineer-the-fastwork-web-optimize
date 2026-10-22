import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { LAUNCHERS } from '../engines.mjs';
import { PIN_SRC, waitReady } from '../page.mjs';
import { startServer, siteDist, rewriteFor } from '../serve.mjs';
import { loadAnchors } from '../spec.mjs';
import { GPU_CELLS, GPU_NODES, PAGE_PROPS, envFor, resolveNodes } from './registry.mjs';
import { installKit } from './kit.mjs';
import { PUSH_PHASES } from './run.mjs';
import { layoutOf } from './cells-gpu.mjs';

const INIT = `${PIN_SRC}\n(${installKit.toString()})();`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => process.stderr.write(a.join(' ') + '\n');
const PHASES = PUSH_PHASES.filter((p) => p.phase === 'open' || p.phase === 'close');

function selOf(anchors, { part, role }) {
  const r = anchors.parts[part]?.roles?.find((x) => x.role === role);
  if (!r) throw new Error(`cells-gpu: no role ${part}:${role} in anchors.json`);
  return r.rewrite;
}

async function openPage(engine, env, origin, search) {
  const s = await engine.open(env, { origin, path: '/' + search, init: INIT, frozen: false });
  const ready = await s.evaluate(waitReady, { site: 'rewrite', capMs: 20000 });
  const arm = await s.evaluate(() => (window.__fw ? { config: window.__fw.configHash ?? null, mode: window.__fw.mode ?? null } : { config: null, mode: null }));
  return { s, ready, arm };
}

async function morphPass(engine, env, origin, search) {
  const { s, arm } = await openPage(engine, env, origin, search);
  try {
    const nodes = resolveNodes(GPU_NODES).map((n) => ({ id: n.id, sel: n.rewrite, props: n.props }));
    const navSel = nodes.find((n) => n.id === 'nav').sel;
    const base = { arm: 'rewrite', nodes, pageProps: PAGE_PROPS, navSel, restMs: 600, settleCapMs: 4000 };
    await s.evaluate((sel) => window.__traj.watchNav(sel), navSel);
    await s.evaluate((a) => window.__traj.approach(a), base);
    const phases = {};
    for (const p of PUSH_PHASES) {
      await s.evaluate((a) => window.__traj.startSampler(a), { ...base, pageProps: [], phase: p.phase, stride: p.stride, lean: false });
      if (p.dy !== 0) await s.wheel(env.width / 2, env.height / 2, p.dy);
      await sleep(p.ms);
      const rows = await s.evaluate(() => window.__traj.stopSampler());
      if (PHASES.some((q) => q.phase === p.phase)) phases[p.phase] = rows;
    }
    return { arm, phases };
  } finally { await s.close().catch(() => {}); }
}

const painScan = async ({ sec, trig, cls, step }) => {
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const el = document.querySelector(trig), pain = document.querySelector(sec);
  if (!el || !pain) return null;
  const vh = window.innerHeight;
  const top = Math.round(el.getBoundingClientRect().top + window.scrollY);
  const max = document.documentElement.scrollHeight - vh;
  const lo = Math.max(0, top - vh), hi = Math.max(lo, Math.min(max, top + Math.round(vh / 2)));
  const at = async (y) => {
    window.scrollTo({ top: y, left: 0, behavior: 'instant' });
    await raf(); await raf();
    return { y, layer: null, cls: pain.classList.contains(cls) };
  };
  window.scrollTo({ top: lo, left: 0, behavior: 'instant' });
  await new Promise((r) => setTimeout(r, 800));
  const ys = [];
  for (let y = lo; y <= hi; y += step) ys.push(y);
  const down = [];
  for (const y of ys) down.push(await at(y));
  const up = [];
  for (const y of ys.slice().reverse()) up.push(await at(y));
  return { down, up };
};

const carouselSample = async ({ scene, cont, ms }) => {
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const sc = document.querySelector(scene), c = document.querySelector(cont);
  if (!sc || !c) return null;
  sc.scrollIntoView({ block: 'center', behavior: 'instant' });
  await raf(); await raf();
  const rows = [];
  const t0 = performance.now();
  while (performance.now() - t0 < ms) {
    await raf();
    const cr = c.getBoundingClientRect();
    const v = [];
    for (const k of Array.from(c.children)) { const r = k.getBoundingClientRect(); v.push(r.x - cr.x, r.y - cr.y, r.width, r.height); }
    rows.push({ t: Math.round((performance.now() - t0) * 10) / 10, v: v.map((x) => Math.round(x * 1000)) });
  }
  return rows;
};

async function pagePass(engine, env, origin, search, fn, arg) {
  const { s } = await openPage(engine, env, origin, search);
  try { await sleep(1500); return await s.evaluate(fn, arg); } finally { await s.close().catch(() => {}); }
}

export async function runCells({ engineName, widths, search = '', reps = 3, env = process.env }) {
  const variant = rewriteFor(siteDist(env), { ...env, FW_SEARCH: search });
  const configs = JSON.parse(readFileSync(join(siteDist(env), 'configs.json'), 'utf8'));
  const baseHash = configs.bySearch[''];
  const want = variant.hash ?? baseHash;
  const anchors = loadAnchors();
  const faithful = await startServer(siteDist(env));
  const rewrite = variant.rewrite ? await startServer(siteDist(env), variant.rewrite) : faithful;
  const engine = await LAUNCHERS[engineName]();
  const runs = [];
  try {
    for (const width of widths) {
      const e = envFor(width);
      for (const a of [{ role: 'base', search: '', want: baseHash, origin: faithful.origin }, { role: 'cand', search, want, origin: rewrite.origin }]) {
        const t0 = Date.now();
        const run = { width, site: 'rewrite', role: a.role, search: a.search, want: a.want };
        let morph = null;
        for (let rep = 0; rep < reps; rep++) {
          log(`cells-gpu ${engineName} ${width} ${a.role}: morph rep ${rep}`);
          const one = await morphPass(engine, e, a.origin, a.search);
          for (const rows of Object.values(one.phases)) for (const r of rows) r.rep = rep;
          if (morph === null) { morph = { arm: one.arm, phases: one.phases, reps }; continue; }
          for (const [ph, rows] of Object.entries(one.phases)) morph.phases[ph] = morph.phases[ph].concat(rows);
        }
        run.morph = morph;
        if (width <= GPU_CELLS.pain.maxWidth) {
          log(`cells-gpu ${engineName} ${width} ${a.role}: pain`);
          run.pain = await pagePass(engine, e, a.origin, a.search, painScan, {
            sec: selOf(anchors, GPU_CELLS.pain.section), trig: selOf(anchors, GPU_CELLS.pain.trigger), cls: GPU_CELLS.pain.cls, step: GPU_CELLS.pain.stepPx,
          });
        }
        log(`cells-gpu ${engineName} ${width} ${a.role}: carousel`);
        run.carousel = await pagePass(engine, e, a.origin, a.search, carouselSample, {
          scene: selOf(anchors, GPU_CELLS.carousel.scene), cont: selOf(anchors, GPU_CELLS.carousel.container), ms: GPU_CELLS.carousel.sampleMs,
        });
        runs.push(run);
        log(`cells-gpu ${engineName} ${width} ${a.role}: done in ${Date.now() - t0} ms`);
      }
    }
    return { engine: engineName, version: await engine.version(), search, hash: want, baseHash, reps, layout: layoutOf(resolveNodes(GPU_NODES)), runs };
  } finally {
    await engine.close().catch(() => {});
    await faithful.close();
    if (rewrite !== faithful) await rewrite.close();
  }
}
