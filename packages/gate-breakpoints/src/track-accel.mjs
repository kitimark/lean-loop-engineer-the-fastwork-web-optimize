// Chromium half of the geom-track-style probe (task geom-track-style): per morph.geom Web Animation track, did Chromium start it on the
// compositor, and if not why; and how many style recalcs the page pays per arm. Readout: a Chrome trace (devtools.timeline +
// blink.animations + blink.user_timing) taken over the whole probe run.
//
//   compositor decision  The trace "Animation" instant (animation.cc:2653@f842f52, data.compositeFailed = FailureReason bits) is written
//                        when a checked animation CANNOT run on the compositor; a success writes none (animation.cc:2631-2637). The
//                        BEGIN event of the same NamedTrack carries data.name = animation.id, which the page probe set to its tag. A tag
//                        that began and has no failure instant while Running is read as "on the compositor" (a trace has no success event).
//   style recalcs        trace events named UpdateLayoutTree (the DevTools "Recalculate Style" slice) between the page's own
//                        `fwx:<arm>:<stage>:start|end` user-timing marks.
// Chromium only. The page script is shared with the WebKitTestRunner arm (track-accel-page.mjs).
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { chromium } from 'playwright-core';
import { PKG, siteDist, startServer } from './serve.mjs';
import { rewritePathFor } from '../../visual-diff/src/run.mjs';
import { ARMS, PROPS, SCHEMA, probeSource } from './track-accel-page.mjs';

export const GOLDEN = resolve(PKG, '../contracts/golden/parts/morph-track-accel.jsonl');
export const MODES = { scrubbed: 'morph.geom:on', timed: 'morph.geom:on,morph.tween:geom-timed' };
/** FailureReason bits, compositor_animations.h:69-137@f842f52. */
export const REASONS = [
  ['accelerated-animations-disabled', 0], ['effect-suppressed-by-devtools', 1], ['invalid-animation-or-effect', 2], ['unsupported-timing', 3],
  ['non-replace-composite', 4], ['target-invalid-compositing-state', 5], ['target-has-incompatible-animations', 6], ['target-has-css-offset', 7],
  ['transform-property-cannot-be-accelerated', 10], ['filter-moves-pixels', 12], ['unsupported-css-property', 13], ['mixed-keyframe-value-types', 15],
  ['timeline-source-invalid-compositing-state', 16], ['no-visible-change', 17], ['affects-important-property', 18], ['svg-independent-transform', 19],
  ['non-replace-iteration-composite', 20], ['unsupported-inheritance', 21],
];
export const decodeReasons = (bits) => REASONS.filter(([, b]) => (bits >>> b) & 1).map(([n]) => n);

export function loadGolden(path = GOLDEN) {
  return readFileSync(path, 'utf8').trim().split('\n').map((l) => JSON.parse(l)).filter((l) => l.fn === 'tracks');
}

const CATEGORIES = ['devtools.timeline', 'blink.animations', 'blink.user_timing', 'cc', 'disabled-by-default-devtools.timeline', 'disabled-by-default-devtools.timeline.invalidationTracking'];
const WORK = new Set(['UpdateLayoutTree', 'RecalculateStyles', 'Layout', 'UpdateLayer', 'UpdateLayerTree', 'PrePaint', 'Paint', 'Commit', 'FunctionCall', 'HitTest']);

/** The join key of a trace event on its custom track: id2 / id / thread. */
export const keyOf = (ev) => (ev.id2 ? JSON.stringify(ev.id2) : ev.id !== undefined ? `id:${ev.id}` : `tid:${ev.pid}:${ev.tid}`);

/** Reduce a Chrome trace to marks, work slices and animation events (pure). */
export function reduceTrace(events) {
  const marks = events.filter((e) => typeof e.name === 'string' && e.name.startsWith('fwx:')).map((e) => ({ name: e.name, ts: e.ts, pid: e.pid, tid: e.tid }));
  const work = events.filter((e) => WORK.has(e.name) && (e.ph === 'X' || e.ph === 'B')).map((e) => ({ name: e.name, ts: e.ts, dur: e.dur ?? 0, pid: e.pid, tid: e.tid, el: e.args?.elementCount ?? e.args?.beginData?.elementCount ?? 0 }));
  const anim = events.filter((e) => e.name === 'Animation' && e.ph !== 'M').map((e) => ({ ph: e.ph, ts: e.ts, key: keyOf(e), data: e.args?.data ?? null, end: e.args?.endData ?? null }));
  const cc = events.filter((e) => e.name === 'KeyframeModel' && (e.ph === 'b' || e.ph === 'B')).map((e) => ({ ts: e.ts, name: e.args?.Name ?? e.args?.data?.Name ?? '' }));
  // Why a style recalc was scheduled: the DevTools invalidation-tracking events ({nodeName, reason}); empty when the category is off.
  const inval = events.filter((e) => typeof e.name === 'string' && e.name.endsWith('InvalidationTracking') && e.ph !== 'M')
    .map((e) => ({ name: e.name, ts: e.ts, pid: e.pid, tid: e.tid, reason: e.args?.data?.reason ?? '?', node: e.args?.data?.nodeName ?? '?' }));
  return { marks, work, anim, cc, inval };
}

/** cc::TargetProperty::Type, cc/trees/target_property.h:15-30@f842f52. */
export const CC_PROP = ['transform', 'scale', 'rotate', 'translate', 'opacity', 'filter', 'scroll-offset', 'background-color', 'bounds', 'css-custom', 'native', 'backdrop-filter'];

/** cc KeyframeModel BEGIN events (keyframe_model.cc:152-155: written when the compositor starts a model; Name = "<curve>-<TargetProperty>-<group>"). */
export function ccStarts(cc, t0, t1) {
  const by = {};
  for (const e of cc) {
    if (e.ts < t0 || e.ts > t1) continue;
    const m = /^[A-Za-z]+-(\d+)-\d+$/.exec(e.name);
    const p = m ? (CC_PROP[Number(m[1])] ?? `type${m[1]}`) : e.name || '?';
    by[p] = (by[p] ?? 0) + 1;
  }
  return by;
}

/** Windows by mark pair `fwx:<arm>:<stage>:start|end` -> { arm, stage, t0, t1, work: {name: {n, ms}} }. */
export function windowsOf(marks, work, inval = []) {
  const open = new Map();
  const out = [];
  for (const m of [...marks].sort((a, b) => a.ts - b.ts)) {
    const [, arm, stage, edge] = m.name.split(':');
    const k = `${arm}:${stage}`;
    if (edge === 'start') open.set(k, m);
    else if (edge === 'end' && open.has(k)) {
      const s = open.get(k);
      open.delete(k);
      const tally = {};
      const slices = [];
      for (const w of work) {
        if (w.pid !== s.pid || w.tid !== s.tid || w.ts < s.ts || w.ts > m.ts) continue;
        const t = (tally[w.name] ??= { n: 0, ms: 0, el: 0 });
        t.n++;
        t.el += w.el;
        t.ms += w.dur / 1000;
        if (w.name === 'UpdateLayoutTree') slices.push([Math.round((w.ts - s.ts) / 100) / 10, w.el, Math.round(w.dur / 10) / 100]);
      }
      for (const t of Object.values(tally)) t.ms = Math.round(t.ms * 100) / 100;
      const why = {};
      for (const v of inval) {
        if (v.pid !== s.pid || v.tid !== s.tid || v.ts < s.ts || v.ts > m.ts) continue;
        const k = `${v.name.replace('InvalidationTracking', '')}:${v.reason}`;
        const o = (why[k] ??= { n: 0, nodes: {} });
        o.n++;
        o.nodes[v.node] = (o.nodes[v.node] ?? 0) + 1;
      }
      for (const o of Object.values(why)) o.nodes = Object.fromEntries(Object.entries(o.nodes).sort((a, b) => b[1] - a[1]).slice(0, 8));
      out.push({ arm, stage, t0: s.ts, t1: m.ts, work: tally, slices, why });
    }
  }
  return out;
}

/** Per tag: began?, last play state, and the decoded failures of its track. */
export function decisionsOf(anim, tags) {
  // A track key is a heap pointer (NamedTrack::FromPointer), so a later Animation can reuse it: a BEGIN opens a new record, the instants
  // that follow belong to the record open on that key, an END closes it.
  const open = new Map();
  const all = [];
  const tagName = new Map(tags.map((t) => [t.id, t]));
  const fresh = (key, ts) => {
    const r = { key, ts, name: null, began: false, fails: [], states: [] };
    all.push(r);
    open.set(key, r);
    return r;
  };
  for (const e of [...anim].sort((x, y) => x.ts - y.ts)) {
    const begin = e.ph === 'b' || e.ph === 'B';
    const rec = begin ? fresh(e.key, e.ts) : (open.get(e.key) ?? fresh(e.key, e.ts));
    if (begin) rec.began = true;
    if (e.data?.name && /^fwx\d+$/.test(e.data.name)) rec.name = e.data.name;
    if (e.data && 'compositeFailed' in e.data) {
      rec.fails.push({ ts: e.ts, bits: e.data.compositeFailed, reasons: decodeReasons(e.data.compositeFailed), unsupported: e.data.unsupportedProperties ?? null, additional: e.data.additionalReasons ?? null });
    }
    if (e.data?.state) rec.states.push(e.data.state);
    if (e.end?.state) rec.states.push(`end:${e.end.state}`);
    if (e.ph === 'e' || e.ph === 'E') open.delete(e.key);
  }
  const named = all.filter((r) => r.name && tagName.has(r.name));
  const rows = named.map((r) => ({ ...tagName.get(r.name), began: r.began, key: r.key, fails: r.fails, states: r.states }));
  return { rows, unnamed: all.filter((r) => !r.name && r.fails.length).length, tracks: all.length };
}

const count = (xs, f) => xs.reduce((m, x) => { const k = f(x); m[k] = (m[k] ?? 0) + 1; return m; }, {});

/** Per arm: page stages joined with the trace windows, the named compositor decisions and the cc compositor starts. Pure. */
export function armSummary(page, windows, decisions, cc = []) {
  const byArm = {};
  for (const r of page.rows) byArm[r.arm] = { arm: r.arm, tracks: r.tracks ?? 0, engaged: r.engaged ?? true, stages: r.stages, table: r.table ?? null, docAnims: r.docAnims ?? null };
  for (const d of decisions.rows) {
    const a = byArm[d.arm];
    if (!a) continue;
    (a.decided ??= []).push({ id: d.id, mg: d.mg, prop: d.prop, idx: d.idx, held: d.held, began: d.began, fails: d.fails.map((f) => f.reasons.join('+') || String(f.bits)), states: d.states });
  }
  for (const w of windows) {
    const a = byArm[w.arm];
    if (!a) continue;
    const st = a.stages.find((s) => s.stage === w.stage);
    if (st) {
      st.trace = { recalcs: (w.work.UpdateLayoutTree?.n ?? 0) + (w.work.RecalculateStyles?.n ?? 0), recalcMs: Math.round(((w.work.UpdateLayoutTree?.ms ?? 0) + (w.work.RecalculateStyles?.ms ?? 0)) * 100) / 100, elements: (w.work.UpdateLayoutTree?.el ?? 0) + (w.work.RecalculateStyles?.el ?? 0), work: w.work, slices: w.slices, why: w.why };
      if (w.stage === 'sweep' || w.stage === 'flip') st.ccStarts = ccStarts(cc, w.t0 - 50000, w.t1 + 150000);
    }
  }
  for (const a of Object.values(byArm)) {
    const win = a.stages.find((s) => s.stage === 'sweep' || s.stage === 'flip');
    a.perFrame = win?.trace && win.frames ? Math.round((win.trace.recalcs / win.frames) * 1000) / 1000 : null;
    a.ccStarts = win?.ccStarts ?? null;
  }
  return Object.values(byArm);
}

const keyProp = (k) => k.split(':').slice(-1)[0];
const keyEl = (k) => k.split(':')[0];

/**
 * Compare the arm `all` against the Lean table (golden `tracks` line of this band). Per property: tracks the page made, tracks Lean puts on the
 * compositor, the trace's named compositor failures, and the cc starts that the geom tracks add (arm `all` minus arm `none`, whose tracks are held).
 * ok (timed only): no named failure on a property Lean puts on the compositor, and every filter track named as failing.
 */
export function judge(mode, w, arms, golden) {
  const g = golden.find((l) => l.in.w === w && l.in.eng === 'chromium');
  const all = arms.find((a) => a.arm === 'all');
  const none = arms.find((a) => a.arm === 'none');
  if (!g || !all) return { ok: false, why: 'no golden line or no arm all' };
  const tags = (all.table ?? []).map((r) => ({ mg: r.mg, prop: r.prop }));
  const made = count(tags, (t) => t.prop);
  const leanTracks = count(g.out.keys, keyProp);
  const leanMain = count(mode === 'timed' ? g.out.timedMain : g.out.keys, keyProp);
  const leanWhy = count(mode === 'timed' ? g.out.timedMainWhy : [], (x) => x);
  const decided = (all.decided ?? []).filter((d) => d.began);
  const failed = count(decided.filter((d) => d.fails.length > 0), (d) => d.prop);
  const reasons = {};
  for (const d of decided) for (const f of d.fails) { const r = (reasons[d.prop] ??= {}); r[f] = (r[f] ?? 0) + 1; }
  const ccDelta = {};
  for (const [p, n] of Object.entries(all.ccStarts ?? {})) ccDelta[p] = n - (none?.ccStarts?.[p] ?? 0);
  const gk = count(g.out.keys, (k) => `${keyEl(k)}:${keyProp(k)}`);
  const pk = count(tags, (t) => `${t.mg}:${t.prop}`);
  const extraN = {};
  for (const k of Object.keys(pk)) if ((pk[k] ?? 0) > (gk[k] ?? 0)) extraN[k] = pk[k] - (gk[k] ?? 0);
  // Tracks the page made beyond the Lean sample (image rows of the live layout) are judged apart: their failures are not Lean's.
  const failedKey = count(decided.filter((d) => d.fails.length > 0), (d) => `${d.mg}:${d.prop}`);
  const failedExtra = {};
  for (const [k, n] of Object.entries(failedKey)) if (extraN[k]) failedExtra[keyProp(k)] = (failedExtra[keyProp(k)] ?? 0) + Math.min(n, extraN[k]);
  const props = [...new Set([...Object.keys(made), ...Object.keys(leanTracks)])].sort();
  const byProp = props.map((p) => ({ prop: p, made: made[p] ?? 0, lean: leanTracks[p] ?? 0, leanMain: leanMain[p] ?? 0, failedNamed: (failed[p] ?? 0) - (failedExtra[p] ?? 0), failedExtraTracks: failedExtra[p] ?? 0, reasons: reasons[p] ?? {}, ccStartsAdded: ccDelta[p] ?? 0 }));
  const extra = Object.entries(extraN).map(([k, n]) => `${k} x${n}`);
  const missing = Object.keys(gk).filter((k) => (gk[k] ?? 0) > (pk[k] ?? 0)).map((k) => `${k} x${gk[k] - (pk[k] ?? 0)}`);
  let ok = null;
  if (mode === 'timed') ok = byProp.every((r) => (r.leanMain === 0 ? r.failedNamed === 0 : r.failedNamed >= Math.min(r.leanMain, r.made)));
  return { ok, tracksMade: tags.length, tracksLean: g.out.n, leanWhy, byProp, extra, missing, began: decided.length };
}

const envOf = (w, h) => ({ width: w, height: h, dpr: w <= 640 ? 3 : 1, hover: w <= 1024 ? 'none' : 'hover', pointer: w <= 1024 ? 'coarse' : 'fine' });

export async function probeBand({ w, h, mode, origin, path, arms, raw, chromePath = process.env.CHROME_PATH }) {
  const env = envOf(w, h);
  const HOVER = { none: 1, hover: 2 };
  const POINTER = { none: 1, coarse: 2, fine: 4 };
  const browser = await chromium.launch({
    ...(chromePath ? { executablePath: chromePath } : {}),
    headless: true,
    args: [`--blink-settings=primaryHoverType=${HOVER[env.hover]},availableHoverTypes=${HOVER[env.hover]},primaryPointerType=${POINTER[env.pointer]},availablePointerTypes=${POINTER[env.pointer]}`, '--font-render-hinting=none', '--force-color-profile=srgb'],
  });
  try {
    const context = await browser.newContext({ viewport: { width: w, height: h }, screen: { width: w, height: h }, deviceScaleFactor: env.dpr, colorScheme: 'light', reducedMotion: 'no-preference' });
    await context.route('**/*', (route) => (route.request().url().startsWith('http://127.0.0.1') ? route.continue() : route.abort()));
    const page = await context.newPage();
    const { PIN_SRC } = await import('./page.mjs');
    await page.addInitScript(PIN_SRC);
    await page.addInitScript(probeSource({ mode, arms }));
    await browser.startTracing(page, { categories: CATEGORIES });
    await page.goto(origin + path, { waitUntil: 'load' });
    const result = await page.evaluate(() => window.__fwx.run());
    const buf = await browser.stopTracing();
    const trace = JSON.parse(buf.toString('utf8'));
    const events = Array.isArray(trace) ? trace : trace.traceEvents;
    const red = reduceTrace(events);
    const windows = windowsOf(red.marks, red.work, red.inval);
    const decisions = decisionsOf(red.anim, result.tags ?? []);
    return { result, windows, decisions, cc: red.cc, version: browser.version(), events: events.length, rawAnim: raw ? red.anim : undefined };
  } finally {
    await browser.close();
  }
}

export async function runTrackAccel({ outDir, bands, modes = ['scrubbed', 'timed'], arms = ARMS, raw = false }) {
  const golden = loadGolden();
  const dist = siteDist();
  const server = await startServer(dist);
  const report = { schema: SCHEMA, engine: 'chromium', props: PROPS, bands: [] };
  try {
    for (const mode of modes) {
      const fw = MODES[mode];
      const { path, search } = rewritePathFor(dist, fw);
      for (const [w, h] of bands) {
        const t0 = Date.now();
        const got = await probeBand({ w, h, mode, origin: server.origin, path: path + search, arms, raw });
        const sums = armSummary(got.result, got.windows, got.decisions, got.cc);
        const verdict = judge(mode, w, sums, golden);
        report.version = got.version;
        report.bands.push({ band: `${w}x${h}`, mode, fw, facts: got.result.facts, errors: got.result.errors, arms: sums, verdict, trace: { events: got.events, animTracks: got.decisions.tracks, unnamedFailing: got.decisions.unnamed }, rawAnim: got.rawAnim });
        const all = sums.find((a) => a.arm === 'all');
        process.stderr.write(`${w}x${h} ${mode}: tracks ${all?.tracks} (lean ${verdict.tracksLean}) named-began ${verdict.began} ok ${verdict.ok} ${(verdict.byProp ?? []).map((r) => `${r.prop}:${r.made}/${r.leanMain}/${r.failedNamed}/${r.ccStartsAdded}`).join(' ')} extra [${(verdict.extra ?? []).join(',')}] missing [${(verdict.missing ?? []).join(',')}] ${Math.round((Date.now() - t0) / 1000)} s${got.result.errors.length ? ` ERRORS ${got.result.errors[0]}` : ''}\n`);
      }
    }
  } finally {
    await server.close();
  }
  mkdirSync(outDir, { recursive: true });
  writeFileSync(join(outDir, 'accel-chromium.json'), `${JSON.stringify(report, null, 1)}\n`);
  const bad = report.bands.filter((b) => b.mode === 'timed' && b.verdict.ok === false).length;
  console.log(`track-accel chromium: ${report.bands.length} band-mode cells, ${bad} timed cells where the trace disagrees with the Lean table`);
  return true;
}

export const DEFAULT_BANDS = [[390, 844], [768, 1024], [1440, 900]];
