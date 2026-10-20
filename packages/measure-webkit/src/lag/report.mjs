// The ranked attribution of the lag probe: raw `fw.webkit.lag/1` sessions in, per region a counter ranking, a paint
// attribution to parts and the filter layers out. Every decision is reduce.mjs (twin of Fw.Measure.WebKitLag); this file
// joins records to boxes and formats.
import { COUNT_TYPES, bucketBySteps, classify, TOL } from '../reduce.mjs';
import { MORPH_FRAMES } from './probe.mjs';
import { Q, regionOf, regionLedger, stepArea, stepCount, rollup, rankWindows, filterTotals, byKey } from './reduce.mjs';

export const COLUMNS = Object.freeze([...COUNT_TYPES, 'paintArea']);
const PX2 = Q * Q;

/** Bounding rectangle of a Paint clip quad, quarter CSS px. */
export function clipRect(q) {
  const xs = [q[0], q[2], q[4], q[6]], ys = [q[1], q[3], q[5], q[7]];
  return [Math.round(Math.min(...xs) * Q), Math.round(Math.min(...ys) * Q), Math.round(Math.max(...xs) * Q), Math.round(Math.max(...ys) * Q)];
}

/**
 * Per-step paint clips of a timed run, from its raw records, moved from document to viewport coordinates.
 * The Paint quad is `contentsToRootView(...)` (PageTimelineAgent.cpp:299@862f17dcae0a), but on iOS the native view
 * scrolls, so `ScrollView::contentsToView` returns the point unchanged (ScrollView.cpp:989-993@862f17dcae0a,
 * `delegatesScrollingToNativeView()`): the quad stays in document coordinates. CONFIRMED by source; MEASURED in the
 * local debug run: at y=0 the first clip equals the `people` box, at y=200 that box moved up 200 px, its clip did not.
 * `scrollY` is the scroll position of each step (a number for all steps, or one per step).
 */
export function clipsPerStep(run, scrollY = 0) {
  const { steps } = bucketBySteps(run.records, run.marks, run.endTime);
  return steps.map((rows, k) => {
    const dy = Math.round((Array.isArray(scrollY) ? scrollY[k] ?? 0 : scrollY) * Q);
    return rows.filter((r) => r[0] === 'Paint' && Array.isArray(r[3]) && r[3].length >= 8).map((r) => { const c = clipRect(r[3]); return [c[0], c[1] - dy, c[2], c[3] - dy]; });
  });
}

const rowsOf = (reduced) => reduced.perStep.map((row, i) => [...row, reduced.perStepPaintArea[i]]);

/** Steps of a scroll run joined to the geometry: y, boxes, clips. */
export function scrollSteps(session, pass) {
  const g = session.geometry, clips = clipsPerStep(pass.scroll, pass.scroll.ys);
  if (g.ys.length !== pass.scroll.ys.length) throw new Error(`geometry has ${g.ys.length} steps, the scroll ${pass.scroll.ys.length}`);
  return g.ys.map((y, k) => ({ y, boxes: g.scroll[k].boxes, clips: clips[k] }));
}

/** Phases of a morph run: idle (the baseline), open (after the push down), close (after the push up), as step index ranges. */
export const MORPH_PHASES = Object.freeze({
  idle: [0, MORPH_FRAMES.idle],
  open: [MORPH_FRAMES.idle, MORPH_FRAMES.idle + MORPH_FRAMES.open],
  close: [MORPH_FRAMES.idle + MORPH_FRAMES.open, MORPH_FRAMES.idle + MORPH_FRAMES.open + MORPH_FRAMES.close],
});

const mean = (a) => (a.length ? a.reduce((s, x) => s + x, 0) / a.length : 0);
const fmt = (x, d = 2) => (Number.isFinite(x) ? x.toFixed(d) : '-');
const classOf = (sums) => (sums.length >= 2 ? classify(sums.map((s) => [s]), TOL.zone).cls : 'one run');

/** A window of the stepped scroll: rows of the steps whose y is in `region`, per pass. */
function scrollWindow(arm, region) {
  return arm.flatMap((s) => s.passes.map((p) => {
    const ys = p.scroll.ys, vh = p.scroll.info.vh, maxY = p.scroll.info.maxY, rows = rowsOf(p.scroll.reduced);
    return rows.filter((_, i) => regionOf(vh, maxY, ys[i]) === region);
  }));
}

/** Counter table of one window against its baseline: sums per pass, mean per step, class across the passes, rank. */
function counterTable(winPerPass, basePerPass) {
  const rows = COLUMNS.map((name, j) => {
    const sums = winPerPass.map((w) => w.reduce((s, r) => s + r[j], 0));
    const nW = mean(winPerPass.map((w) => w.length));
    const bMean = mean(basePerPass.flatMap((w) => w.map((r) => r[j])));
    const wMean = mean(winPerPass.flatMap((w) => w.map((r) => r[j])));
    return { name, perStep: wMean, baseline: bMean, ratio: bMean > 0 ? wMean / bMean : null, cls: classOf(sums), sums, steps: nW };
  });
  const ranked = rankWindows(winPerPass.flat(), basePerPass.flat(), COLUMNS);
  const perPassTop = winPerPass.map((w, i) => rankWindows(w, basePerPass[i], COLUMNS).filter(([, e]) => e > 0).slice(0, 3).map(([n]) => n).join('>'));
  return { rows, ranked, perPassTop };
}

const toPx2 = (ledger) => ledger.map(([k, v]) => [k, v / PX2]);

/** Per-region analysis of one arm (its sessions). */
export function analyzeScroll(arm) {
  const base = scrollWindow(arm, 'calm');
  const out = {};
  for (const region of ['A', 'B']) {
    const win = scrollWindow(arm, region);
    const table = counterTable(win, base);
    const area = [], count = [], filt = [];
    for (const s of arm) {
      const p0 = s.passes[0].scroll, vh = p0.info.vh, maxY = p0.info.maxY;
      for (const pass of s.passes) {
        const steps = scrollSteps(s, pass);
        area.push(...regionLedger(vh, maxY, steps, region, stepArea));
        count.push(...regionLedger(vh, maxY, steps, region, stepCount));
      }
      const vp = [0, 0, Math.round(p0.info.vw * Q), Math.round(vh * Q)];
      s.geometry.ys.forEach((y, k) => { if (regionOf(vh, maxY, y) === region) filt.push(filterTotals(vp, s.geometry.scroll[k].filters)); });
    }
    const passes = arm.reduce((n, s) => n + s.passes.length, 0);
    const scale = (l) => l.map(([k, v]) => [k, v / passes]);
    out[region] = {
      steps: table.rows[0].steps, table, passes,
      paintAreaByPart: toPx2(scale(byKey(area))), paintAreaByCoarse: toPx2(scale(rollup(byKey(area)))), paintCountByPart: scale(byKey(count)), paintCountByCoarse: scale(rollup(byKey(count))),
      filter: { count: mean(filt.map((f) => f.count)), area: mean(filt.map((f) => f.area)) / PX2, areaRadius: mean(filt.map((f) => f.areaRadius)) / PX2 },
    };
  }
  out.calmFilter = (() => {
    const f = [];
    for (const s of arm) {
      const p0 = s.passes[0].scroll, vh = p0.info.vh, maxY = p0.info.maxY, vp = [0, 0, Math.round(p0.info.vw * Q), Math.round(vh * Q)];
      s.geometry.ys.forEach((y, k) => { if (regionOf(vh, maxY, y) === 'calm' && s.geometry.scroll[k].filters.length >= 0 && k % 8 === 0) f.push(filterTotals(vp, s.geometry.scroll[k].filters)); });
    }
    return { count: mean(f.map((x) => x.count)), area: mean(f.map((x) => x.area)) / PX2, areaRadius: mean(f.map((x) => x.areaRadius)) / PX2 };
  })();
  return out;
}

/** Morph analysis of one arm: the open and close phases against the idle frames. */
export function analyzeMorph(arm) {
  const slice = (rows, [a, b]) => rows.slice(a, b);
  const runs = arm.flatMap((s) => s.passes.map((p) => ({ s, m: p.morph })));
  const idle = runs.map(({ m }) => slice(rowsOf(m.reduced), MORPH_PHASES.idle));
  const out = {};
  for (const phase of ['open', 'close']) {
    const win = runs.map(({ m }) => slice(rowsOf(m.reduced), MORPH_PHASES[phase]));
    const table = counterTable(win, idle);
    const area = [], count = [], filt = [];
    for (const { s, m } of runs) {
      const g = s.geometry.morph, [a, b] = MORPH_PHASES[phase];
      const clips = clipsPerStep(m, m.before?.y ?? 0);
      const vp = [0, 0, Math.round(m.info.vw * Q), Math.round(m.info.vh * Q)];
      for (let k = a; k < b; k++) {
        const smp = g.samples[k];
        if (!smp) continue;
        const step = { y: 0, boxes: smp.boxes, clips: clips[k] };
        area.push(...stepArea(step)); count.push(...stepCount(step));
        filt.push(filterTotals(vp, smp.filters));
      }
    }
    const n = runs.length;
    const scale = (l) => l.map(([k, v]) => [k, v / n]);
    out[phase] = {
      steps: MORPH_PHASES[phase][1] - MORPH_PHASES[phase][0], table, passes: n,
      paintAreaByPart: toPx2(scale(byKey(area))), paintAreaByCoarse: toPx2(scale(rollup(byKey(area)))), paintCountByPart: scale(byKey(count)), paintCountByCoarse: scale(rollup(byKey(count))),
      filter: { count: mean(filt.map((f) => f.count)), area: mean(filt.map((f) => f.area)) / PX2, areaRadius: mean(filt.map((f) => f.areaRadius)) / PX2 },
    };
  }
  out.taken = runs.map(({ m }) => m.taken);
  out.scrollToCalls = runs.map(({ m }) => m.scrollTo);
  out.morph = runs.map(({ s, m }) => ({ before: m.before.morph, after: m.after.morph, geomBefore: s.geometry.morph.before.morph, geomAfter: s.geometry.morph.after.morph }));
  out.platform = runs.map(({ m }) => m.before.platform);
  return out;
}

const topLines = (ledger, n = 6) => {
  const total = ledger.reduce((s, [, v]) => s + v, 0);
  return [...ledger].sort((a, b) => b[1] - a[1]).slice(0, n).map(([k, v]) => `${k} ${fmt(v, 0)} (${fmt((100 * v) / (total || 1), 0)}%)`).join(', ');
};

function counterMd(t, label) {
  const lines = [`| counter (${label}) | per step | calm per step | ratio | excess rank | class over runs |`, '|---|---|---|---|---|---|'];
  const rank = new Map(t.ranked.map(([n, e], i) => [n, [i + 1, e]]));
  for (const r of t.rows) {
    const [i, e] = rank.get(r.name);
    lines.push(`| ${r.name} | ${fmt(r.perStep)} | ${fmt(r.baseline)} | ${r.ratio === null ? '-' : fmt(r.ratio, 1)} | ${e > 0 ? i : '-'} | ${r.cls} |`);
  }
  lines.push('', `top counters per run (excess > 0): ${t.perPassTop.map((x, i) => `r${i + 1} ${x || '-'}`).join('; ')}`);
  return lines.join('\n');
}

/** Markdown of one arm. */
export function armMd(name, arm) {
  const sc = analyzeScroll(arm), mo = analyzeMorph(arm);
  const info = arm[0].passes[0].scroll.info;
  const L = [`## ${name}`, '', `${arm.length} sessions, ${arm.reduce((n, s) => n + s.passes.length, 0)} passes; viewport ${info.vw}x${info.vh}, maxY ${info.maxY}.`, ''];
  for (const region of ['A', 'B']) {
    const r = sc[region];
    L.push(`### Region ${region} (scroll)`, '', `${r.steps} steps per pass.`, '', counterMd(r.table, `region ${region}`), '',
      `paint area per pass by part (css px^2): ${topLines(r.paintAreaByCoarse)}`, `paint area by leaf part: ${topLines(r.paintAreaByPart, 8)}`,
      `paint count per pass by part: ${topLines(r.paintCountByCoarse)}`,
      `filter/backdrop elements per step: ${fmt(r.filter.count)} visible, ${fmt(r.filter.area, 0)} px^2, area x radius ${fmt(r.filter.areaRadius, 0)} (calm: ${fmt(sc.calmFilter.count)}, ${fmt(sc.calmFilter.area, 0)}, ${fmt(sc.calmFilter.areaRadius, 0)})`, '');
  }
  for (const phase of ['open', 'close']) {
    const r = mo[phase];
    L.push(`### Region B morph, ${phase} (${r.steps} frames)`, '', counterMd(r.table, `morph ${phase}`), '',
      `paint area per pass by part (css px^2): ${topLines(r.paintAreaByCoarse)}`, `paint area by leaf part: ${topLines(r.paintAreaByPart, 8)}`,
      `paint count per pass by part: ${topLines(r.paintCountByCoarse)}`,
      `filter/backdrop elements per frame: ${fmt(r.filter.count)} visible, ${fmt(r.filter.area, 0)} px^2, area x radius ${fmt(r.filter.areaRadius, 0)}`, '');
  }
  L.push(`morph validity: wheel taken ${JSON.stringify(mo.taken)}, scrollTo calls ${JSON.stringify(mo.scrollToCalls)}, --morph ${JSON.stringify(mo.morph)}, platform before ${JSON.stringify(mo.platform)}`, '');
  const c = arm.map((s) => s.geometry.census);
  L.push('### Layers (census, untimed)', '', '| session | state y | layers | backing MB | filter/backdrop layers |', '|---|---|---|---|---|');
  c.forEach((cs, i) => cs.forEach((x) => L.push(`| ${i + 1} | ${x.scrollY} | ${x.layerCount} | ${fmt(x.memoryBytes / 1e6, 1)} | ${x.filterLayers.length} |`)));
  return L.join('\n');
}
