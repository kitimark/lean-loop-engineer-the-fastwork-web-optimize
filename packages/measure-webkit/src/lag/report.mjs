// The ranked attribution of the lag probe: raw `fw.webkit.lag/1` sessions in, per region a counter ranking by a unit-free
// ratio, a paint attribution to parts, the top steps, the filter layers and the layer census out, for both arms with the
// arm difference decided on per-pass ranges. Every decision is reduce.mjs (twin of Fw.Measure.WebKitLag); this file joins
import { COUNT_TYPES, bucketBySteps } from '../reduce.mjs';
import { MORPH_FRAMES, scanSteps } from './probe.mjs';
import { phaseRanges } from './phase.mjs';
import {
  Q, regionOf, regionLedger, stepArea, topPart, rollup, rankWindows, colRatio, colSum, frac, fracLt, verdict, topK,
  filterTotals, byKey, RARE_MIN, flagged, ratioVerdict,
} from './reduce.mjs';

/** Timeline record types counted besides COUNT_TYPES (present in the raw records, not in the lane's columns). */
export const EXTRA_TYPES = Object.freeze(['RequestAnimationFrame', 'TimerInstall', 'TimerRemove']);
/** Record types whose duration (end - start, microseconds on the Simulator host, not phone time) is a column. */
export const DURATION_TYPES = Object.freeze(['Layout', 'Paint', 'RecalculateStyles', 'Composite', 'FunctionCall']);
export const COLUMNS = Object.freeze([...COUNT_TYPES, ...EXTRA_TYPES, ...DURATION_TYPES.map((t) => `${t}Us`), 'paintArea']);
const PAINT = COLUMNS.indexOf('Paint'), AREA = COLUMNS.indexOf('paintArea');
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

/**
 * One row per step of a timed run, columns COLUMNS: the record counts, the durations in microseconds, the paint area in
 * css px^2. All of it is derived from the run's raw Timeline records.
 */
export function stepRows(run) {
  const { steps } = bucketBySteps(run.records, run.marks, run.endTime);
  return steps.map((recs, k) => {
    const count = new Map([...COUNT_TYPES, ...EXTRA_TYPES].map((t) => [t, 0])), dur = new Map(DURATION_TYPES.map((t) => [t, 0]));
    for (const r of recs) {
      if (count.has(r[0])) count.set(r[0], count.get(r[0]) + 1);
      if (dur.has(r[0]) && typeof r[2] === 'number' && typeof r[1] === 'number') dur.set(r[0], dur.get(r[0]) + Math.round((r[2] - r[1]) * 1e6));
    }
    return [...COUNT_TYPES, ...EXTRA_TYPES].map((t) => count.get(t)).concat(DURATION_TYPES.map((t) => dur.get(t)), [run.reduced.perStepPaintArea[k]]);
  });
}

/**
 * Steps of a scroll run joined to the geometry: y, boxes, clips. The page height differs by a few dozen px between loads
 * (MEASURED: maxY 5231 and 5267 within one session), so the step count of the geometry load and of a timed load can
 * differ; a step takes the boxes of the geometry step whose y is nearest (INFERRED join, exact when the heights agree).
 */
export function scrollSteps(session, pass) {
  const g = session.geometry, clips = clipsPerStep(pass.scroll, pass.scroll.ys);
  const nearest = (y) => g.ys.reduce((best, gy, i) => (Math.abs(gy - y) < Math.abs(g.ys[best] - y) ? i : best), 0);
  return pass.scroll.ys.map((y, k) => ({ y, boxes: g.scroll[nearest(y)].boxes, clips: clips[k] }));
}

export const MORPH_PHASES = Object.freeze({
  idle: [0, MORPH_FRAMES.idle],
  open: [MORPH_FRAMES.idle, MORPH_FRAMES.idle + MORPH_FRAMES.open],
  close: [MORPH_FRAMES.idle + MORPH_FRAMES.open, MORPH_FRAMES.idle + MORPH_FRAMES.open + MORPH_FRAMES.close],
});

const mean = (a) => (a.length ? a.reduce((s, x) => s + x, 0) / a.length : 0);
const num = (q) => q[0] / q[1];
const sum = (a) => a.reduce((s, x) => s + x, 0);

/** Sessions that kept at least one pass with `part` (a partly failed session still carries its completed passes). */
const withPart = (arm, part) => arm.map((s) => ({ ...s, passes: s.passes.filter((p) => p[part]) })).filter((s) => s.passes.length);

/** Min and max of a list of fractions, or null. */
const rangeOf = (qs) => (qs.length ? [qs.reduce((a, b) => (fracLt(b, a) ? b : a)), qs.reduce((a, b) => (fracLt(a, b) ? b : a))] : null);

/** The difference of two arms from their per-pass values: only separated ranges count (Lean: verdict). */
const diffOf = (orig, faith) => verdict(orig, faith);

// ---------------------------------------------------------------------------------------------------- analysis

/** The passes of an arm with their rows and steps. */
function scrollItems(arm) {
  return withPart(arm, 'scroll').flatMap((s, si) => s.passes.map((p, pi) => {
    const { vh, maxY } = p.scroll.info;
    return { s, p, tag: `s${si + 1}p${pi + 1}`, vh, maxY, rows: stepRows(p.scroll), steps: scrollSteps(s, p), fps: p.scroll.framesPerStep ?? s.framesPerStep ?? 2 };
  }));
}

const regionRows = (it, region) => it.rows.filter((_, i) => regionOf(it.vh, it.maxY, it.steps[i].y) === region);

/** Counter table of per-pass windows against per-pass baselines: pooled and per-pass ratios, rank, mean rows. */
function counterTable(wins, bases, fR, fC) {
  const w = wins.flat(), b = bases.flat();
  const { ranked, unranked } = rankWindows(fR, fC, w, b, COLUMNS);
  const rows = COLUMNS.map((name, j) => {
    const basePass = bases.map((x) => colSum(x, j));
    return {
      name, perFrame: sum(w.map((r) => r[j])) / (fR * (w.length || 1)), baseFrame: sum(b.map((r) => r[j])) / (fC * (b.length || 1)),
      ratio: colRatio(fR, fC, w, b, j), perPass: wins.map((x, i) => colRatio(fR, fC, x, bases[i], j)).filter((x) => x !== null),
      absPass: wins.filter((x) => x.length).map((x) => frac(colSum(x, j), fR * x.length)),
      rank: ranked.findIndex(([n]) => n === name) + 1 || null,
      basePass, rare: flagged(name, basePass),
    };
  });
  return { rows, unranked, rowsInWindow: w.length, rowsInBaseline: b.length, passes: wins.length };
}

/** Per-part paint area (css px^2) per pass, parts rolled up to their coarse name, with the mean and share over the passes. */
function partTable(perPassLedgers) {
  const coarse = perPassLedgers.map((l) => new Map(rollup(l)));
  const names = [...new Set(coarse.flatMap((m) => [...m.keys()]))];
  const total = sum(coarse.map((m) => sum([...m.values()])));
  return names.map((name) => {
    const perPass = coarse.map((m) => (m.get(name) ?? 0) / PX2);
    return { name, perPass, mean: mean(perPass), share: total ? sum(perPass) * PX2 / total : 0 };
  }).sort((a, b) => b.mean - a.mean);
}

const leafTable = (perPassLedgers) => {
  const all = byKey(perPassLedgers.flat());
  const total = sum(all.map(([, v]) => v));
  return all.map(([k, v]) => ({ name: k, mean: v / PX2 / (perPassLedgers.length || 1), share: total ? v / total : 0 })).sort((a, b) => b.mean - a.mean);
};

/** The steps with the largest paint area (css px^2) in a pool of steps, with their counters and owning part. */
function topOf(pool, k = 5) {
  return topK(k, pool.map((e, i) => [i, e.row[AREA]])).map(([i]) => pool[i]);
}

/** Filter totals per session at the scanned steps of a region; legacy artifacts (no `scanned`) use the rule they were taken with. */
function filterStats(arm, region) {
  return arm.map((s) => {
    const g = s.geometry, gi = g.info, vp = [0, 0, Math.round(gi.vw * Q), Math.round(gi.vh * Q)];
    let steps = 0, scanned = 0, count = 0, area = 0, areaRadius = 0;
    g.ys.forEach((y, k) => {
      if (regionOf(gi.vh, gi.maxY, y) !== region) return;
      steps++;
      const smp = g.scroll[k];
      const was = smp.scanned ?? (scanSteps(g.ys, gi.vh, gi.maxY).includes(k) || y <= gi.vh || gi.maxY - gi.vh <= y);
      if (!was) return;
      const t = filterTotals(vp, smp.filters);
      scanned++; count += t.count; area += t.area; areaRadius += t.areaRadius;
    });
    return { steps, scanned, count: scanned ? frac(count, scanned) : null, area: scanned ? frac(area, scanned * PX2) : null, areaRadius: scanned ? frac(areaRadius, scanned * PX2) : null };
  });
}

/** Scroll regions A, B and calm of one arm. */
function analyzeScrollItems(items, arm) {
  const out = {};
  const calm = items.map((it) => regionRows(it, 'calm'));
  for (const region of ['A', 'B']) {
    const wins = items.map((it) => regionRows(it, region));
    const ledgers = items.map((it) => byKey(regionLedger(it.vh, it.maxY, it.steps, region, stepArea)));
    const pool = items.flatMap((it) => it.steps.map((st, i) => ({ tag: it.tag, y: st.y, row: it.rows[i], part: topPart(st), st })).filter((e) => regionOf(it.vh, it.maxY, e.y) === region));
    out[region] = {
      stepsPerPass: mean(wins.map((w) => w.length)), table: counterTable(wins, calm, 1, 1), parts: partTable(ledgers), leaves: leafTable(ledgers),
      top: topOf(pool).map(({ tag, y, row, part }) => ({ tag, y, row, part })), filter: filterStats(arm, region),
    };
  }
  out.calm = { stepsPerPass: mean(calm.map((w) => w.length)), filter: filterStats(arm, 'calm') };
  return out;
}

function analyzeMorphItems(arm, scrollOf) {
  const all = withPart(arm, 'morph').flatMap((s, si) => s.passes.map((p, pi) => ({ s, p, tag: `s${si + 1}p${pi + 1}`, m: p.morph, ph: phaseRanges(p.morph, MORPH_PHASES), rows: stepRows(p.morph), clips: clipsPerStep(p.morph, p.morph.before?.y ?? 0) })));
  const runs = all.filter((r) => r.ph);
  const out = { passes: runs.length, refused: all.length - runs.length, phases: {} };
  const len = (r, ph) => r.ph[ph][1] - r.ph[ph][0];
  const fps = scrollOf.length ? scrollOf[0].fps : 2;
  const calm = runs.map((r) => scrollOf.find((it) => it.p === r.p)).map((it) => (it ? regionRows(it, 'calm') : []));
  const slice = (r, ph) => r.rows.slice(...r.ph[ph]);
  const frameStep = (r, phase, i) => ({ y: 0, boxes: r.s.geometry.morph.samples[MORPH_PHASES[phase][0] + i]?.boxes ?? [], clips: r.clips[r.ph[phase][0] + i] ?? [] });
  for (const phase of ['open', 'close']) {
    const wins = runs.map((r) => slice(r, phase)), idle = runs.map((r) => slice(r, 'idle'));
    const [a, b] = MORPH_PHASES[phase];
    const ledgers = runs.map((r) => byKey(Array.from({ length: len(r, phase) }, (_, i) => frameStep(r, phase, i)).flatMap(stepArea)));
    const pool = runs.flatMap((r) => Array.from({ length: len(r, phase) }, (_, i) => ({ tag: r.tag, y: i, row: r.rows[r.ph[phase][0] + i], part: topPart(frameStep(r, phase, i)) })));
    const active = runs.map((r) => {
      const g = r.s.geometry.morph, nav = (smp) => JSON.stringify(smp?.boxes.find((x) => x.name === 'nav')?.rect ?? null);
      return g.samples.slice(a, b).filter((smp) => nav(smp) !== nav(g.samples[0])).length;
    });
    const filt = runs.flatMap((r) => r.s.geometry.morph.samples.slice(a, b).map((smp) => filterTotals([0, 0, Math.round(r.m.info.vw * Q), Math.round(r.m.info.vh * Q)], smp.filters)));
    out.phases[phase] = {
      frames: mean(runs.map((r) => len(r, phase))), table: counterTable(wins, calm, 1, fps), tableIdle: counterTable(wins, idle, 1, 1), parts: partTable(ledgers), leaves: leafTable(ledgers),
      top: topOf(pool), activeFrames: mean(active),
      filter: { count: mean(filt.map((f) => f.count)), area: mean(filt.map((f) => f.area)) / PX2, areaRadius: mean(filt.map((f) => f.areaRadius)) / PX2 },
    };
  }
  const idleLedgers = runs.map((r) => byKey(Array.from({ length: len(r, 'idle') }, (_, i) => frameStep(r, 'idle', i)).flatMap(stepArea)));
  out.idle = {
    frames: mean(runs.map((r) => len(r, 'idle'))),
    paintsPerFrame: runs.map((r) => mean(slice(r, 'idle').map((x) => x[PAINT]))),
    areaPerFrame: runs.map((r) => mean(slice(r, 'idle').map((x) => x[AREA]))),
    parts: leafTable(idleLedgers.map((l, i) => l.map(([k, v]) => [k, v / len(runs[i], 'idle')]))),
    rects: runs[0] ? [...new Set((runs[0].clips[1] ?? []).map((c) => `${((c[2] - c[0]) / Q).toFixed(1)}x${((c[3] - c[1]) / Q).toFixed(1)} at ${(c[0] / Q).toFixed(0)},${(c[1] / Q).toFixed(0)}`))] : [],
  };
  out.taken = runs.map((r) => r.m.taken);
  out.scrollToCalls = runs.map((r) => r.m.scrollTo);
  out.morphVar = runs.map((r) => ({ before: r.m.before.morph, after: r.m.after.morph }));
  out.platform = runs.map((r) => r.m.before.platform);
  return out;
}

/** The layer census of one arm: per session the four states. */
function analyzeCensus(arm) {
  const states = arm[0].geometry.census.map((c) => c.scrollY);
  return states.map((_, i) => {
    const per = arm.map((s) => s.geometry.census[i]).filter(Boolean);
    const reasons = [...new Set(per.flatMap((c) => Object.keys(c.reasonCounts ?? {})))].sort();
    return {
      y: per.map((c) => c.scrollY), layers: per.map((c) => c.layerCount), mb: per.map((c) => c.memoryBytes / 1e6), filterLayers: per.map((c) => c.filterLayers.length),
      reasons: Object.fromEntries(reasons.map((r) => [r, per.map((c) => c.reasonCounts?.[r] ?? 0)])),
    };
  });
}

/** Full analysis of one arm (its sessions). */
export function analyzeArm(rawArm) {
  const items = scrollItems(rawArm);
  const info = items[0]?.p.scroll.info ?? null;
  return {
    sessions: rawArm.length, scrollPasses: items.length, info,
    failed: rawArm.flatMap((s, i) => (s.failed?.length ? [`session ${i + 1}: ${s.failed.join('; ')}`] : [])),
    framesPerStep: items[0]?.fps ?? 2,
    scroll: analyzeScrollItems(items, rawArm), morph: analyzeMorphItems(rawArm, items), census: analyzeCensus(rawArm),
  };
}

// ------------------------------------------------------------------------------------------------------ format

const fmt = (x, d) => {
  if (!Number.isFinite(x)) return '-';
  if (d === 0) return Math.round(x).toLocaleString('en-US');
  if (d !== undefined) return x.toFixed(d);
  const a = Math.abs(x);
  return a >= 1000 ? Math.round(x).toLocaleString('en-US') : a >= 100 ? x.toFixed(0) : a >= 10 ? x.toFixed(1) : x.toFixed(2);
};
const span = (lo, hi) => (lo === hi ? lo : `${lo}-${hi}`);
const rng = (qs, d) => { const r = rangeOf(qs); return r ? span(fmt(num(r[0]), d), fmt(num(r[1]), d)) : '-'; };
const rngN = (xs, d) => (xs.length ? span(fmt(Math.min(...xs), d), fmt(Math.max(...xs), d)) : '-');
const DIFF = { lower: 'faithful lower', higher: 'faithful higher', overlap: 'no difference shown (ranges overlap)', rareBaseline: 'not stated (rare baseline)' };
const RARE_MARK = ' (*)';
const nameOf = (c) => (c.endsWith('Us') ? `${c.slice(0, -2)} (us)` : c === 'paintArea' ? 'paintArea (px^2)' : c);
const asFrac = (xs) => xs.map((x) => frac(Math.round(x * PX2), PX2));

/** The ranked table of one region, both arms side by side, ordered by the first arm's rank. */
function regionTable(label, tabs, names, unit) {
  const [o, f] = tabs;
  const L = [`| counter | ${unit} ${names[0]} / ${names[1] ?? '-'} | baseline ${names[0]} / ${names[1] ?? '-'} | ratio ${names[0]} (per-pass range) | rank ${names[0]} | ratio ${names[1] ?? '-'} (per-pass range) | rank ${names[1] ?? '-'} | difference of the ratio | difference of the ${unit} value |`, '|---|---|---|---|---|---|---|---|---|'];
  const order = [...o.rows].sort((a, b) => (a.rank ?? 99) - (b.rank ?? 99) || COLUMNS.indexOf(a.name) - COLUMNS.indexOf(b.name));
  for (const r of order) {
    const q = f?.rows.find((x) => x.name === r.name);
    const cell = (x) => (x?.ratio ? `${fmt(num(x.ratio))} (${rng(x.perPass)})${x.rare ? RARE_MARK : ''}` : 'no baseline');
    L.push(`| ${nameOf(r.name)} | ${fmt(r.perFrame)} / ${q ? fmt(q.perFrame) : '-'} | ${fmt(r.baseFrame)} / ${q ? fmt(q.baseFrame) : '-'} | ${cell(r)} | ${r.rank ?? '-'} | ${q ? cell(q) : '-'} | ${q?.rank ?? '-'} | ${q && r.perPass.length && q.perPass.length ? DIFF[ratioVerdict(r.rare, q.rare, r.perPass, q.perPass)] : '-'} | ${q && r.absPass.length && q.absPass.length ? DIFF[diffOf(r.absPass, q.absPass)] : '-'} |`);
  }
  L.push('', `The ratio compares a window with the same arm's calm baseline, so an arm difference of the ratio can come from the baseline; the last column decides on the per-pass value itself. (*) the baseline of that arm has fewer than ${RARE_MIN} events of the counter in at least one pass (Lean rareBase, event counts only), so its ratio and rank are unstable and no difference of the ratio is stated for the row. Duration columns (us) are Simulator-host microseconds summed over the records of the type; records nest (a Layout inside a FunctionCall), so durations are not additive across types.`);
  return L.join('\n');
}

const partsMd = (parts, k = 6) => parts.slice(0, k).map((p) => `${p.name} ${fmt(p.mean, 0)} (${fmt(100 * p.share, 0)}%)`).join(', ');

/** Per-part table of both arms with the per-pass range and the verdict. */
function partsCompare(a, b, names) {
  const L = [`| part | ${names[0]} px^2 per pass (range) | share ${names[0]} | ${names[1] ?? '-'} px^2 per pass (range) | share ${names[1] ?? '-'} | difference |`, '|---|---|---|---|---|---|'];
  const am = new Map(a.parts.map((p) => [p.name, p]));
  const bm = new Map((b?.parts ?? []).map((p) => [p.name, p]));
  const union = [...new Set([...am.keys(), ...bm.keys()])].sort((x, y) => Math.max(am.get(y)?.mean ?? 0, bm.get(y)?.mean ?? 0) - Math.max(am.get(x)?.mean ?? 0, bm.get(x)?.mean ?? 0));
  const cell = (q) => (q ? `${fmt(q.mean, 0)} (${rngN(q.perPass, 0)})` : 'not in this arm');
  const SHOWN = 10;
  for (const name of union.slice(0, SHOWN)) {
    const p = am.get(name);
    const q = bm.get(name);
    const both = p && q && sum(p.perPass) > 0 && sum(q.perPass) > 0;
    L.push(`| ${name} | ${cell(p)} | ${p ? `${fmt(100 * p.share, 0)}%` : '-'} | ${cell(q)} | ${q ? `${fmt(100 * q.share, 0)}%` : '-'} | ${both ? DIFF[diffOf(asFrac(p.perPass), asFrac(q.perPass))] : p && q ? 'not compared (zero in one arm)' : 'not compared (part absent in one arm)'} |`);
  }
  if (union.length > SHOWN) L.push('', `${union.length - SHOWN} more parts not shown`);
  return L.join('\n');
}

const topMd = (label, top) => {
  const L = [`| ${label} | pass | y or frame | Paint | paintArea px^2 | Layout | RecalculateStyles | owning part |`, '|---|---|---|---|---|---|---|---|'];
  top.forEach((t, i) => L.push(`| ${i + 1} | ${t.tag} | ${t.y} | ${t.row[PAINT]} | ${fmt(t.row[AREA], 0)} | ${t.row[COLUMNS.indexOf('Layout')]} | ${t.row[COLUMNS.indexOf('RecalculateStyles')]} | ${t.part} |`));
  return L.join('\n');
};

const filterMd = (names, fs) => {
  const L = [`| region | arm | scanned / steps (per session) | visible filter layers per step (range over sessions) | visible area px^2 | area x radius |`, '|---|---|---|---|---|---|'];
  for (const [region, per] of fs) per.forEach((st, i) => {
    L.push(`| ${region} | ${names[i]} | ${st.map((x) => `${x.scanned}/${x.steps}`).join(', ')} | ${rng(st.map((x) => x.count).filter(Boolean))} | ${rng(st.map((x) => x.area).filter(Boolean), 0)} | ${rng(st.map((x) => x.areaRadius).filter(Boolean), 0)} |`);
  });
  return L.join('\n');
};

const filterDiff = (names, region, fs) => {
  if (fs.length < 2) return '';
  const pick = (k) => fs.map((st) => st.map((x) => x[k]).filter(Boolean));
  const row = (k, label) => `${label}: ${DIFF[diffOf(pick(k)[0], pick(k)[1])]}`;
  return `${region}: ${row('count', 'filter layers per step')}; ${row('area', 'visible filter area')}; ${row('areaRadius', 'area x radius')}`;
};

/** The whole Markdown report of the analysed arms ([name, analysis] pairs, the first is the reference arm). */
export function reportMd(arms) {
  const names = arms.map(([n]) => n), an = arms.map(([, a]) => a);
  const [o, f] = an;
  const L = ['### Inputs', ''];
  arms.forEach(([n, a]) => L.push(`- ${n}: ${a.sessions} sessions, ${a.scrollPasses} scroll passes, ${a.morph.passes} morph passes; viewport ${a.info.vw}x${a.info.vh}, maxY ${a.info.maxY}${a.failed.length ? `; stopped early: ${a.failed.join(' | ')}` : ''}`));
  L.push('', 'Ratio = counter per frame in the region over counter per frame in the baseline (unit-free; Lean `ratio_scale`). The range is over passes (each pass against its own baseline). "Difference" is stated only when every pass of one arm is on one side of every pass of the other (Lean `verdict`).', '');
  const scrollRegion = (r) => `Region ${r}`;
  for (const r of ['A', 'B']) {
    L.push(`### ${scrollRegion(r)} (scroll), ratio to the calm scroll baseline`, '',
      `${names.map((n, i) => `${n}: ${fmt(an[i].scroll[r].stepsPerPass, 1)} steps per pass in the region, ${fmt(an[i].scroll.calm.stepsPerPass, 1)} calm steps per pass`).join('; ')}. Per-step values.`, '',
      regionTable(r, an.map((a) => a.scroll[r].table), names, 'per step'), '',
      `Counters with no calm baseline (not ranked): ${names.map((n, i) => `${n} ${an[i].scroll[r].table.unranked.map(nameOf).join(', ') || 'none'}`).join('; ')}.`, '',
      `Paint area by part (css px^2 per pass; coarse part names, leaf parts below). The two arms have different part tables (the original a selector table, the rewrite its data-fw elements): a part in one table only is not compared, and the share of a part in both tables can move to a part of the other, so read neighbouring parts together.`, '', partsCompare(o.scroll[r], f?.scroll[r], names), '',
      ...names.map((n, i) => `- ${n}, leaf parts: ${partsMd(an[i].scroll[r].leaves, 8)}`), '');
    names.forEach((n, i) => L.push(`Top 5 steps of ${scrollRegion(r)}, ${n} (by paint area, all passes pooled):`, '', topMd('rank', an[i].scroll[r].top), ''));
  }
  for (const ph of ['open', 'close']) {
    const fps = o.framesPerStep;
    L.push(`### Region B morph, ${ph} push (${o.morph.phases[ph].frames} frames), ratio to the calm scroll baseline`, '',
      `Per-frame values. The calm baseline is the calm scroll steps of the same pass divided by ${fps} frames per step. The nav box differs from the idle tail in ${names.map((n, i) => `${fmt(an[i].morph.phases[ph].activeFrames, 0)} (${n})`).join(', ')} of the frames.`, '',
      regionTable('morph', an.map((a) => a.morph.phases[ph].table), names, 'per frame'), '',
      `Counters with no calm baseline (not ranked): ${names.map((n, i) => `${n} ${an[i].morph.phases[ph].table.unranked.map(nameOf).join(', ') || 'none'}`).join('; ')}.`, '',
      `Against the idle page tail (the 10 frames before the push, nothing moving) instead; ratio, rank 1-3; (*) as above, the idle baseline of that arm has fewer than ${RARE_MIN} events of the counter in at least one pass:`, '',
      ...names.map((n, i) => {
        const t = an[i].morph.phases[ph].tableIdle;
        return `- ${n}: ${t.rows.filter((r) => r.rank && r.rank <= 3).sort((x, y) => x.rank - y.rank).map((r) => `${nameOf(r.name)} x${fmt(num(r.ratio))} (${rng(r.perPass)})${r.rare ? RARE_MARK : ''}`).join(', ')}; no idle baseline: ${t.unranked.map(nameOf).join(', ') || 'none'}`;
      }), '',
      `Paint area by part (css px^2 per pass; the two arms have different part tables, see Region A):`, '', partsCompare(o.morph.phases[ph], f?.morph.phases[ph], names), '',
      ...names.map((n, i) => `- ${n}, leaf parts: ${partsMd(an[i].morph.phases[ph].leaves, 8)}`), '');
    names.forEach((n, i) => L.push(`Top 5 frames of the ${ph} push, ${n} (by paint area; "y or frame" is the frame in the phase):`, '', topMd('rank', an[i].morph.phases[ph].top), ''));
  }
  L.push('### Idle page tail (the 10 frames before the push)', '');
  names.forEach((n, i) => {
    const d = an[i].morph.idle;
    L.push(`- ${n}: Paint per frame ${rngN(d.paintsPerFrame)} per pass, paint area per frame ${rngN(d.areaPerFrame, 0)} px^2 per pass; by part ${partsMd(d.parts, 6)}; first-pass clips ${d.rects.join('; ') || 'none'}`);
  });
  L.push('', '### Filter and backdrop-filter elements (geometry pass, per scanned step)', '');
  const fsRegions = ['A', 'B', 'calm'].map((r) => [r, an.map((a) => a.scroll[r].filter)]);
  L.push(filterMd(names, fsRegions), '');
  for (const [r, per] of fsRegions) { const d = filterDiff(names, r, per); if (d) L.push(`- ${d}`); }
  L.push('', 'The calm baseline scans every eighth step only (the scan reads the computed style of every element); the "scanned / steps" column states how many steps each average is over.', '');
  L.push('### Layer census (LayerTree, untimed, four scroll states, one value per session)', '');
  const head = ['| state | y (px) | layers (range over sessions) | backing MB | filter or backdrop layers |', '|---|---|---|---|---|'];
  L.push(...head);
  an[0].census.forEach((_, si) => {
    names.forEach((n, i) => {
      const c = an[i].census[si];
      L.push(`| ${si + 1} | ${rngN(c.y, 0)} | ${n} ${rngN(c.layers, 0)} | ${rngN(c.mb, 1)} | ${rngN(c.filterLayers, 0)} |`);
    });
    if (f) {
      const q = (xs, d = 1) => xs.map((x) => frac(Math.round(x * d), d));
      L.push(`| ${si + 1} | | layers: ${DIFF[diffOf(q(o.census[si].layers), q(f.census[si].layers))]} | MB: ${DIFF[diffOf(q(o.census[si].mb, 1000), q(f.census[si].mb, 1000))]} | filter layers: ${DIFF[diffOf(q(o.census[si].filterLayers), q(f.census[si].filterLayers))]} |`);
    }
  });
  L.push('', 'Layer count change between consecutive states (mean over sessions): ' + names.map((n, i) => `${n} ${an[i].census.slice(1).map((c, k) => fmt(mean(c.layers) - mean(an[i].census[k].layers), 0)).join(', ')}`).join('; '), '');
  const reasonNames = [...new Set(an.flatMap((a) => Object.keys(a.census.at(-1).reasons)))];
  L.push(`Compositing reasons at the last state (layers per session, range):`, '', `| reason | ${names.join(' | ')} |`, `|---|${names.map(() => '---').join('|')}|`);
  reasonNames.forEach((r) => L.push(`| ${r} | ${an.map((a) => rngN(a.census.at(-1).reasons[r] ?? [0], 0)).join(' | ')} |`));
  L.push('', '### Morph validity', '');
  names.forEach((n, i) => {
    const m = an[i].morph, uniq = (xs) => [...new Set(xs.map((x) => JSON.stringify(x)))].join(' ');
    L.push(`- ${n}: wheel pushes taken (default prevented) in ${m.taken.filter((t) => t.every(Boolean)).length} of ${m.taken.length} passes, scrollTo calls ${uniq(m.scrollToCalls)}, --morph before/after ${uniq(m.morphVar.map((x) => [x.before, x.after]))}, platform box before ${uniq(m.platform.map((x) => x && Math.round(x.height)))}`);
  });
  return L.join('\n');
}

/** Markdown of the arms, from raw sessions: `[[name, sessions], ...]`. */
export const reportFromSessions = (pairs) => reportMd(pairs.map(([n, s]) => [n, analyzeArm(s)]));
