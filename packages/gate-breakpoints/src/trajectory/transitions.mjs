// Per-frame transition probe of the earn button and the language button (task earn-webkit-parity). The original and the faithful
// rewrite are walked through the hero-pill exit, the hero-pill entry and one morph push (wheel open, wheel close) in real time, native
// rAF, no animation seeking. Every rendering frame records the rects of the earn button, the language wrap and the actions group,
// and (mode `full`) the computed padding, max-width, opacity and column-gap, the CSS transitions alive per property
// (document.getAnimations) and the transition events. Mode `light` reads the two rects only: the difference between the two modes
// bounds what the reading itself does to the page. The reduction below is a TS stand-in of the measurement summary; the cause is
// decided in Lean (Fw.Engine.TransitionStart). Glue and reduction only.
//
//   node src/trajectory/transitions.mjs capture --engine chromium|playwright-webkit --widths 390,1280 --reps 3 --out DIR
//   node src/trajectory/transitions.mjs summary --in DIR[,DIR2] --out DIR3 [--run ID]
import { mkdirSync, readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { LAUNCHERS } from '../engines.mjs';
import { PIN_SRC, waitReady } from '../page.mjs';
import { startServer, snapshotRoot, siteDist } from '../serve.mjs';
import { MORPH_NODES, envFor, resolveNodes } from './registry.mjs';
import { installKit } from './kit.mjs';

const INIT_KIT = `${PIN_SRC}\n(${installKit.toString()})();`;
const log = (...a) => process.stderr.write(a.join(' ') + '\n');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** The scripted scroll of the hero sequences: viewport heights travelled, how long the ramp lasts, how long the page is held after it. */
export const RAMP = { toVh: 2, ms: 600, preMs: 300, holdMs: 1500 };
/** The morph pushes: wheel delta and how long each is recorded after its wheel event. */
export const PUSHES = [{ seq: 'morph-open', dy: 120, ms: 1500, holdMs: 900 }, { seq: 'morph-close', dy: -120, ms: 1500, holdMs: 900 }];
/** The sequences of a page in the order they run on it. */
export const SEQUENCES = ['hero-exit', 'hero-entry', 'morph-open', 'morph-close'];

/** The CSS selectors of the nodes read, per arm, from the anchor registry (one source for both arms). */
export function selectorsFor(site) {
  const nodes = resolveNodes([
    ...MORPH_NODES.filter((n) => ['nav', 'actions', 'earn'].includes(n.id)),
    { id: 'lang', part: 'nav.langMenu', role: 'wrap', props: [] },
    { id: 'langBtn', part: 'nav.langMenu', role: 'switch', props: [] },
  ]);
  return Object.fromEntries(nodes.map((n) => [n.id, site === 'orig' ? n.orig : n.rewrite]));
}

/**
 * The in-page recorder; it is serialised into the page, so it uses nothing outside itself. `start(sel, mode)` records one row per
 * rendering frame until `stop()`; `ramp` is a scripted scroll driven by the clock (instant scrolls, one per frame);
 * `mark(label)` tags the next row.
 */
export function recorder() {
  const st = (window.__tr = { rows: [], events: [], loop: false, gen: 0, t0: 0, els: {}, ids: new WeakMap(), nextId: 1, mode: 'full', label: null });
  const rnd = (v, k = 100) => Math.round(v * k) / k;
  const keyOf = (el) => Object.keys(st.els).find((k) => st.els[k] === el) ?? null;
  for (const type of ['transitionrun', 'transitionstart', 'transitioncancel', 'transitionend']) {
    document.addEventListener(type, (e) => {
      if (st.loop) st.events.push({ type, prop: e.propertyName, node: keyOf(e.target), t: rnd(performance.now() - st.t0, 10), elapsed: e.elapsedTime });
    }, true);
  }
  const rect = (el) => { if (!el) return null; const b = el.getBoundingClientRect(); return [rnd(b.left), rnd(b.top), rnd(b.width), rnd(b.height)]; };
  const flag = (nav, c) => (nav && nav.classList.contains(c) ? '1' : '0');
  return {
    start(sel, mode) {
      st.rows = []; st.events = []; st.loop = true; st.mode = mode; st.label = null;
      st.els = {};
      for (const k of Object.keys(sel)) st.els[k] = document.querySelector(sel[k]);
      st.t0 = performance.now();
      const mine = ++st.gen;
      const full = mode === 'full';
      const tick = (ts) => {
        if (!st.loop || st.gen !== mine) return;
        const read = performance.now();
        const e = st.els;
        const row = { t: rnd(ts - st.t0, 10), read: rnd(read - st.t0, 10), y: rnd(window.scrollY, 10), lbl: st.label, earn: rect(e.earn), lang: rect(e.lang) };
        st.label = null;
        if (full) {
          row.act = rect(e.actions);
          row.nav = ['is-hero-pill', 'is-expanded', 'is-morphing'].map((c) => flag(e.nav, c)).join('');
          if (e.earn) {
            const cs = getComputedStyle(e.earn);
            row.cs = { pl: cs.paddingLeft, pr: cs.paddingRight, mw: cs.maxWidth, op: cs.opacity, ne: cs.getPropertyValue('--nav-expand').trim(),
              eo: cs.getPropertyValue('--earn-out').trim(), el: cs.getPropertyValue('--earn-layout').trim(), tr: cs.transitionProperty };
          }
          if (e.actions) row.gap = getComputedStyle(e.actions).columnGap;
          row.an = [];
          for (const a of document.getAnimations()) {
            if (typeof CSSTransition === 'undefined' || !(a instanceof CSSTransition)) continue;
            const node = keyOf(a.effect && a.effect.target);
            if (node === null) continue;
            if (!st.ids.has(a)) st.ids.set(a, st.nextId++);
            row.an.push([node, a.transitionProperty, st.ids.get(a), Math.round(Number(a.currentTime) || 0), a.playState]);
          }
        }
        st.rows.push(row);
        requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
      return true;
    },
    mark(label) { st.label = label; return true; },
    stop() { st.loop = false; st.gen++; return { rows: st.rows, events: st.events }; },
    ramp(a) {
      return new Promise((resolve) => {
        const vh = window.innerHeight;
        const t0 = performance.now();
        const step = () => {
          const k = Math.min(1, (performance.now() - t0) / a.ms);
          window.scrollTo({ top: Math.round((a.fromVh + (a.toVh - a.fromVh) * k) * vh), left: 0, behavior: 'instant' });
          if (k < 1) requestAnimationFrame(step); else resolve(Math.round(window.scrollY));
        };
        requestAnimationFrame(step);
      });
    },
    waitFrames(n) { return new Promise((r) => { let k = 0; const f = () => (++k >= n ? r(true) : requestAnimationFrame(f)); requestAnimationFrame(f); }); },
  };
}
export const REC = `window.__rec = (${recorder.toString()})();`;

/** One page: the hero sequences (scripted scroll), then the morph pushes (wheel). Returns { ready, self, sequences: {seq: {rows, events}} }. */
async function walkPage(engine, env, arm, mode, morph) {
  const sel = selectorsFor(arm.site);
  const s = await engine.open(env, { origin: arm.origin, path: '/', init: `${INIT_KIT}\n${REC}`, frozen: false });
  try {
    const ready = await s.evaluate(waitReady, { site: arm.site, capMs: 20000 });
    const self = await s.evaluate(() => (window.__fw ? { config: window.__fw.configHash ?? null, mode: window.__fw.mode ?? null } : { config: null, mode: null }));
    await s.evaluate(() => { window.scrollTo({ top: 0, left: 0, behavior: 'instant' }); });
    await sleep(900);
    const sequences = {};
    const record = async (seq, body) => {
      await s.evaluate((a) => window.__rec.start(a.sel, a.mode), { sel, mode });
      await body();
      sequences[seq] = await s.evaluate(() => window.__rec.stop());
    };
    await record('hero-exit', async () => {
      await sleep(RAMP.preMs);
      await s.evaluate(() => window.__rec.mark('ramp'));
      await s.evaluate((a) => window.__rec.ramp(a), { fromVh: 0, toVh: RAMP.toVh, ms: RAMP.ms });
      await sleep(RAMP.holdMs);
    });
    await record('hero-entry', async () => {
      await sleep(RAMP.preMs);
      await s.evaluate(() => window.__rec.mark('ramp'));
      await s.evaluate((a) => window.__rec.ramp(a), { fromVh: RAMP.toVh, toVh: 0, ms: RAMP.ms });
      await sleep(RAMP.holdMs);
    });
    if (!morph) return { ready, self, sequences };
    const navSel = sel.nav;
    await s.evaluate((q) => window.__traj.watchNav(q), navSel);
    await s.evaluate((a) => window.__traj.approach(a), { arm: arm.site, nodes: [], pageProps: [], navSel, restMs: 600, settleCapMs: 4000 });
    for (const p of PUSHES) {
      await record(p.seq, async () => {
        await s.mouse(env.width / 2, env.height / 2);
        await s.evaluate(() => window.__rec.mark('wheel'));
        await s.wheel(env.width / 2, env.height / 2, p.dy);
        await sleep(p.ms + p.holdMs);
      });
    }
    return { ready, self, sequences };
  } finally { await s.close().catch(() => {}); }
}

/** Capture one engine over `widths`: the original and the faithful rewrite, `reps` full pages and one light page per arm and width. */
export async function capture({ engineName, widths, reps, out, morph = true, env = process.env }) {
  mkdirSync(out, { recursive: true });
  const configs = JSON.parse(readFileSync(join(siteDist(env), 'configs.json'), 'utf8'));
  const orig = await startServer(snapshotRoot(env));
  const rewrite = await startServer(siteDist(env));
  const engine = await LAUNCHERS[engineName]();
  const arms = [
    { site: 'orig', role: 'orig', origin: orig.origin, want: null },
    { site: 'rewrite', role: 'faithful', origin: rewrite.origin, want: configs.bySearch[''] },
  ];
  const runs = [];
  try {
    for (const width of widths) for (const arm of arms) {
      const modes = [...Array.from({ length: reps }, () => 'full'), 'light'];
      for (let k = 0; k < modes.length; k++) {
        const mode = modes[k];
        const t0 = Date.now();
        const e = envFor(width);
        const one = await walkPage(engine, e, arm, mode, morph);
        const identity = arm.site === 'orig' ? (one.self.config === null ? 'ok' : 'mismatch')
          : (one.self.config === arm.want && one.self.mode === 'hydrate' ? 'ok' : 'mismatch');
        runs.push({ width, role: arm.role, mode, rep: k, identity, self: one.self, ready: one.ready, sequences: one.sequences });
        log(`transitions ${engineName} ${width} ${arm.role} ${mode} #${k}: ${Date.now() - t0} ms, identity ${identity}, rows ${SEQUENCES.map((q) => one.sequences[q]?.rows.length ?? 0).join('/')}`);
      }
    }
    const head = { engine: engineName, version: await engine.version(), reps, ramp: RAMP, pushes: PUSHES, selectors: { orig: selectorsFor('orig'), rewrite: selectorsFor('rewrite') }, runs };
    writeFileSync(join(out, `transitions-${engineName}.json`), JSON.stringify(head));
    if (runs.some((r) => r.identity !== 'ok')) { log('transitions: an arm is not the page it was asked for'); process.exitCode = 2; }
  } finally {
    await engine.close().catch(() => {});
    await orig.close(); await rewrite.close();
  }
}

// ---- reduction (TS stand-in; the cause is decided in Lean) ----

const num = (s) => { const v = parseFloat(s); return Number.isFinite(v) ? v : null; };
const median = (a) => { if (a.length === 0) return null; const b = [...a].sort((x, y) => x - y); const m = b.length >> 1; return b.length % 2 ? b[m] : (b[m - 1] + b[m]) / 2; };

/** The first frame after the first row where the nav's hero-pill flag differs from the first row's; null when it never does. Mode `light` has no flags. */
export function flipIndex(rows) {
  if (rows.length === 0 || rows[0].nav === undefined) return null;
  const k = rows.findIndex((r) => r.nav !== rows[0].nav);
  return k < 0 ? null : k;
}

/** A value series of the rows by reader; null entries stay null. */
export const SERIES = {
  earnW: (r) => (r.earn ? r.earn[2] : null),
  earnX: (r) => (r.earn ? r.earn[0] : null),
  langX: (r) => (r.lang ? r.lang[0] : null),
  padL: (r) => (r.cs ? num(r.cs.pl) : null),
  padR: (r) => (r.cs ? num(r.cs.pr) : null),
  maxW: (r) => (r.cs ? num(r.cs.mw) : null),
  op: (r) => (r.cs ? num(r.cs.op) : null),
  gap: (r) => (r.gap === undefined ? null : num(r.gap)),
};

/**
 * How one series moves after the flip frame `k`: its value before and at the end, the largest one-frame change after the flip and when,
 * the first frame offset (ms from the flip row's t) where it left the start value, where it reached the end value, and how many frames
 * lie strictly between the two (a transition shows many, a snap none).
 */
export function motion(rows, k, f, tol = 0.5) {
  if (k === null || k < 1) return null;
  const v = rows.map(f);
  const v0 = v[k - 1];
  const vE = v.slice(k).reverse().find((x) => x !== null);
  if (v0 === null || v0 === undefined || vE === undefined) return null;
  const t0 = rows[k].t;
  let maxJump = 0, jumpAt = null, leave = null, arrive = null, between = 0;
  for (let i = k; i < rows.length; i++) {
    if (v[i] === null) continue;
    const d = Math.abs(v[i] - v[i - 1]);
    if (v[i - 1] !== null && d > maxJump) { maxJump = d; jumpAt = Math.round(rows[i].t - t0); }
    if (leave === null && Math.abs(v[i] - v0) > 0.05) leave = Math.round(rows[i].t - t0);
    if (arrive === null && Math.abs(v[i] - vE) <= tol) arrive = Math.round(rows[i].t - t0);
    if (Math.abs(v[i] - v0) > tol && Math.abs(v[i] - vE) > tol) between++;
  }
  return { start: v0, end: vE, change: Math.round((vE - v0) * 100) / 100, maxJump: Math.round(maxJump * 100) / 100, jumpAtMs: jumpAt, leaveMs: leave, arriveMs: arrive, between };
}

/** The transitions seen per property of a node: how many distinct animations (a restart makes a new one), the frames each lived, the first frame offset seen. */
export function transitionsSeen(rows, k) {
  const by = new Map();
  rows.forEach((r, i) => {
    for (const [node, prop, id] of r.an ?? []) {
      const key = `${node}:${prop}`;
      const e = by.get(key) ?? { ids: new Set(), frames: 0, firstMs: null };
      e.ids.add(id); e.frames++;
      if (e.firstMs === null) e.firstMs = k === null ? Math.round(r.t) : Math.round(r.t - rows[k].t);
      by.set(key, e);
    }
  });
  return Object.fromEntries([...by].map(([key, e]) => [key, { animations: e.ids.size, frames: e.frames, firstMs: e.firstMs }]));
}

/** The frame cadence of a recording: the median gap between rendering frames and the count of gaps above 24 ms. */
export function cadence(rows) {
  const gaps = rows.slice(1).map((r, i) => r.t - rows[i].t);
  return { frames: rows.length, medianMs: median(gaps) === null ? null : Math.round(median(gaps) * 10) / 10, long: gaps.filter((g) => g > 24).length };
}

/** The event counts per `type:prop:node` of a recording. */
export function eventCounts(events) {
  const c = {};
  for (const e of events) { const key = `${e.type}:${e.node}:${e.prop}`; c[key] = (c[key] ?? 0) + 1; }
  return c;
}

/** Everything one recording (one sequence of one page) reduces to. */
export function analyse({ rows, events }) {
  const k = flipIndex(rows);
  const kk = k === null ? rows.findIndex((r) => r.lbl === 'ramp' || r.lbl === 'wheel') + 1 : k;
  const out = { cadence: cadence(rows), flipFrame: k, flipT: k === null ? null : Math.round(rows[k].t), series: {}, transitions: transitionsSeen(rows, k), events: eventCounts(events) };
  const at = k ?? (kk > 0 ? kk : null);
  for (const [name, f] of Object.entries(SERIES)) out.series[name] = motion(rows, at, f, name === 'op' ? 0.02 : 0.5);
  return out;
}

/** The per-frame table of a recording from `before` frames before the flip to `after` frames after it. */
export function frameTable(rows, k, before = 2, after = 14) {
  if (k === null) return [];
  const f = (v) => (v === null || v === undefined ? '-' : String(Math.round(v * 100) / 100));
  const lines = ['  dt_ms  padL  padR  maxW   opac  earnW  earnX  langX  anims'];
  for (let i = Math.max(0, k - before); i <= Math.min(rows.length - 1, k + after); i++) {
    const r = rows[i];
    const an = (r.an ?? []).filter(([n]) => n === 'earn').map(([, p, id]) => `${p}#${id}`).join(',');
    lines.push(`${String(Math.round(r.t - rows[k].t)).padStart(6)} ${f(SERIES.padL(r)).padStart(5)} ${f(SERIES.padR(r)).padStart(5)} ${f(SERIES.maxW(r)).padStart(6)} ${f(SERIES.op(r)).padStart(5)} ${f(SERIES.earnW(r)).padStart(6)} ${f(SERIES.earnX(r)).padStart(6)} ${f(SERIES.langX(r)).padStart(6)}  ${an}`);
  }
  return lines;
}

/** Across repeats: min, median and max of a number picked from each repeat's analysis; null when none has it. */
export function spread(list, pick) {
  const v = list.map(pick).filter((x) => x !== null && x !== undefined);
  return v.length === 0 ? null : { n: v.length, min: Math.min(...v), median: median(v), max: Math.max(...v) };
}

/** The summary of one capture file: per width, arm and sequence, the full-mode repeats pooled, plus the light mode apart. */
export function summarise(head) {
  const out = { engine: head.engine, version: head.version, reps: head.reps, cells: [] };
  const keys = [...new Set(head.runs.map((r) => `${r.width}|${r.role}`))];
  for (const key of keys) {
    const [width, role] = key.split('|');
    const runs = head.runs.filter((r) => String(r.width) === width && r.role === role);
    for (const seq of SEQUENCES) {
      const full = runs.filter((r) => r.mode === 'full' && r.sequences[seq]).map((r) => analyse(r.sequences[seq]));
      const light = runs.filter((r) => r.mode === 'light' && r.sequences[seq]).map((r) => analyse(r.sequences[seq]));
      const cell = { width: Number(width), role, seq, identity: runs.every((r) => r.identity === 'ok') ? 'ok' : 'mismatch', full: full.length, light: light.length, series: {}, lightSeries: {}, transitions: {} };
      for (const name of Object.keys(SERIES)) {
        const pick = (field) => (a) => (a.series[name] ? a.series[name][field] : null);
        cell.series[name] = { change: spread(full, pick('change')), maxJump: spread(full, pick('maxJump')), arriveMs: spread(full, pick('arriveMs')), between: spread(full, pick('between')) };
        if (['earnW', 'earnX', 'langX'].includes(name)) cell.lightSeries[name] = { maxJump: spread(light, pick('maxJump')), arriveMs: spread(light, pick('arriveMs')), between: spread(light, pick('between')) };
      }
      const props = new Set(full.flatMap((a) => Object.keys(a.transitions)));
      for (const p of props) cell.transitions[p] = { reps: full.filter((a) => a.transitions[p]).length, animations: spread(full.filter((a) => a.transitions[p]), (a) => a.transitions[p].animations), frames: spread(full.filter((a) => a.transitions[p]), (a) => a.transitions[p].frames) };
      cell.cadence = spread(full, (a) => a.cadence.medianMs);
      out.cells.push(cell);
    }
  }
  return out;
}

/** The text of a summary: one block per cell with the per-frame table of the first full repeat. */
export function summaryText(head, summary) {
  const L = [`# ${head.engine} (${head.version}), ${head.reps} full repeats + 1 light page per arm and width`];
  for (const c of summary.cells) {
    L.push('', `## width ${c.width} ${c.role} ${c.seq} (identity ${c.identity}, ${c.full} full, ${c.light} light)`);
    for (const [name, s] of Object.entries(c.series)) {
      if (!s.change || (s.change.min === 0 && s.change.max === 0 && !(s.maxJump && s.maxJump.max > 0))) continue;
      L.push(`  ${name.padEnd(6)} change ${s.change.median} (${s.change.min}..${s.change.max}); max one-frame jump ${s.maxJump?.median} (${s.maxJump?.min}..${s.maxJump?.max}); arrives ${s.arriveMs?.median} ms; frames between ${s.between?.median}`);
    }
    const tp = Object.entries(c.transitions).map(([p, t]) => `${p} x${t.reps}/${c.full} (animations ${t.animations?.median}, frames ${t.frames?.median})`);
    if (tp.length) L.push(`  transitions: ${tp.join('; ')}`);
    else L.push('  transitions: none seen');
    const run = head.runs.find((r) => String(r.width) === String(c.width) && r.role === c.role && r.mode === 'full' && r.sequences[c.seq]);
    if (run) { L.push(...frameTable(run.sequences[c.seq].rows, flipIndex(run.sequences[c.seq].rows)).map((x) => '  ' + x)); }
  }
  return L.join('\n') + '\n';
}

async function summary({ ins, out, run }) {
  mkdirSync(out, { recursive: true });
  const index = { run: run ?? null, files: [] };
  for (const dir of ins) {
    for (const f of readdirSync(dir).filter((x) => /^transitions-.*\.json$/.test(x))) {
      const head = JSON.parse(readFileSync(join(dir, f), 'utf8'));
      const s = summarise(head);
      const base = f.replace(/\.json$/, '');
      writeFileSync(join(out, `${base}.summary.json`), JSON.stringify(s, null, 1) + '\n');
      writeFileSync(join(out, `${base}.summary.txt`), summaryText(head, s));
      index.files.push({ file: f, engine: head.engine, version: head.version });
      log(`summary ${f}: ${s.cells.length} cells`);
    }
  }
  writeFileSync(join(out, 'index.json'), JSON.stringify(index, null, 1) + '\n');
}

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(`--${k}`); return i >= 0 ? args[i + 1] : d; };
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (args[0] === 'capture') {
    await capture({ engineName: opt('engine'), widths: opt('widths', '390,1280').split(',').map(Number), reps: Number(opt('reps', '3')), out: opt('out'), morph: opt('morph', '1') !== '0' });
  } else if (args[0] === 'summary') {
    await summary({ ins: opt('in').split(','), out: opt('out'), run: opt('run') });
  } else {
    log('usage: transitions.mjs capture --engine E --widths 390,1280 --reps 3 [--morph 0] --out DIR | summary --in DIR[,DIR] --out DIR [--run ID]');
    process.exitCode = 2;
  }
}
