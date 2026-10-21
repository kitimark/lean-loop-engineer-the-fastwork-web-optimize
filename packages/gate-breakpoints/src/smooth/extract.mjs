// Motion continuity from a trajectory-probe raw file (task smoothness-probe, part A). Reads only; the node and property order come from
// trajectory/registry.mjs. The decisions (stall, jump, reversal, tail) are reduce.mjs, the TS twin of lean/Fw/Gate/Smooth.lean.
//
// Two ideal curves, because a property's true easing is not known from the page:
//   line: the straight line in the driver (m for the end-of-page morph, scroll y for the hero path) between the settled ends.
//         Easing and delays count as defects in every arm alike, so only differences between arms mean anything.
//   ref:  the original's own response at the same driver value. For the original itself the curve is built from its other
//         repeats (leave one out), so its row is the run-to-run consistency of the original.
import { HERO_NODES, MORPH_NODES } from '../trajectory/registry.mjs';
import { lerp, metrics, worst, flat, flagged, quantile } from './reduce.mjs';

const CONTINUOUS = new Set(['unit', 'geometry', 'colour']);
const HERO_ORDER = ['s0', 's25', 's50', 's90', 's200', 'mid', 'hold', 'b50', 'b25', 'b0'];
const MORPH_END = 10000;

/** Every continuous scalar of a row: key `node#element.prop[component]` to its integer value. */
export function scalars(row, nodes) {
  const out = new Map();
  for (const n of nodes) {
    const els = row.nodes?.[n.id];
    if (!els) continue;
    els.forEach((el, i) => {
      n.props.forEach((p, k) => {
        if (!CONTINUOUS.has(p.kind)) return;
        const v = el?.[k];
        if (!Array.isArray(v) || !v.every((x) => Number.isFinite(x))) return;
        v.forEach((x, c) => out.set(`${n.id}#${i}.${p.id}[${c}]`, x));
      });
    });
  }
  return out;
}

const tenths = (ms) => Math.round(ms * 10);
export const nodeOf = (key) => key.slice(0, key.indexOf('#'));
const byRep = (rows) => {
  const m = new Map();
  for (const r of rows ?? []) {
    const q = r.rep ?? 0;
    if (!m.has(q)) m.set(q, []);
    m.get(q).push(r);
  }
  return m;
};

/** The samples of every scalar along one push: key to {t, d, v} columns (time in tenths of ms, driver, value). */
function samplesOf(rows, driverOf, nodes) {
  const per = rows.map((r) => ({ t: tenths(r.t), d: driverOf(r), vals: scalars(r, nodes) }));
  const keys = new Set(per.flatMap((f) => [...f.vals.keys()]));
  const out = new Map();
  for (const k of keys) {
    const col = { t: [], d: [], v: [] };
    for (const f of per) {
      if (!f.vals.has(k) || f.d === null || f.d === undefined) continue;
      col.t.push(f.t);
      col.d.push(f.d);
      col.v.push(f.vals.get(k));
    }
    if (col.t.length >= 2) out.set(k, col);
  }
  return out;
}

/** The pushes of one arm's run: the end-of-page open and close pushes per rep, and the hero path's segments. */
export function pushesOf(run) {
  const out = [];
  const ph = run.morph?.phases;
  if (ph?.open && ph?.close) {
    const open = byRep(ph.open);
    const close = byRep(ph.close);
    const openHold = byRep(ph['open-hold']);
    const closeHold = byRep(ph['close-hold']);
    for (const [q, rows] of open) {
      const oh = openHold.get(q);
      const ch = closeHold.get(q);
      const cl = close.get(q);
      if (!oh?.length || !ch?.length || !cl?.length) continue;
      const b = scalars(oh[oh.length - 1], MORPH_NODES);
      const a = scalars(ch[ch.length - 1], MORPH_NODES);
      const m = (r) => r.m;
      const live = (xs) => xs.filter((r) => r.m !== null);
      out.push({ window: 'end-open', push: `rep${q}`, rep: q, nodes: MORPH_NODES, d0: 0, d1: MORPH_END, a, b, samples: samplesOf(live(rows), m, MORPH_NODES) });
      out.push({ window: 'end-close', push: `rep${q}`, rep: q, nodes: MORPH_NODES, d0: 0, d1: MORPH_END, a, b, samples: samplesOf(live(cl), m, MORPH_NODES) });
    }
  }
  const rows = run.hero?.rows ?? [];
  const by = new Map(rows.map((r) => [r.tag, r]));
  for (let i = 1; i < HERO_ORDER.length; i++) {
    const step = HERO_ORDER[i];
    if (step === 'hold') continue;
    const prev = by.get(`${HERO_ORDER[i - 1]}/rest`);
    const next = by.get(`${step}/rest`);
    const ms = ['m1', 'm2', 'm3', 'm4'].map((m) => by.get(`${step}/${m}`)).filter(Boolean);
    if (!prev || !next || ms.length === 0 || prev.y === next.y) continue;
    out.push({ window: 'hero', push: step, rep: 0, nodes: HERO_NODES, d0: prev.y, d1: next.y, a: scalars(prev, HERO_NODES), b: scalars(next, HERO_NODES),
      samples: samplesOf([prev, ...ms], (r) => r.y, HERO_NODES) });
  }
  return out;
}

/** The response curve of one scalar from several repeats' samples: ties in the driver take the median value, between points a straight line. */
export function curveOf(points) {
  const g = new Map();
  for (const [d, v] of points) (g.get(d) ?? g.set(d, []).get(d)).push(v);
  const pts = [...g.entries()].map(([d, vs]) => [d, quantile(vs, 50)]).sort((x, y) => x[0] - y[0]);
  return (d) => {
    if (pts.length === 0) return null;
    if (d <= pts[0][0]) return pts[0][1];
    if (d >= pts[pts.length - 1][0]) return pts[pts.length - 1][1];
    let lo = 0;
    let hi = pts.length - 1;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (pts[mid][0] <= d) lo = mid;
      else hi = mid;
    }
    return lerp(pts[lo][0], pts[lo][1], pts[hi][0], pts[hi][1], d);
  };
}

/** The frames [t, want, shown] of one scalar of one push, with the ideal chosen by `ideal` ('line' or 'ref'). */
function framesOf(push, key, ideal, ref) {
  const s = push.samples.get(key);
  if (!s) return null;
  if (ideal === 'line') {
    if (!push.a.has(key) || !push.b.has(key)) return null;
    return s.t.map((t, i) => [t, lerp(push.d0, push.a.get(key), push.d1, push.b.get(key), s.d[i]), s.v[i]]);
  }
  if (push.window === 'hero') {
    const o = ref?.samples.get(key);
    if (!o || o.v.length !== s.v.length) return null;
    return s.t.map((t, i) => [t, o.v[i], s.v[i]]);
  }
  const reps = ref ?? [];
  const pts = reps.flatMap((p) => { const o = p.samples.get(key); return o ? o.d.map((d, i) => [d, o.v[i]]) : []; });
  if (pts.length === 0) return null;
  const f = curveOf(pts);
  return s.t.map((t, i) => [t, f(s.d[i]), s.v[i]]);
}

/** Per window and node: each push's worst-of-components metrics, whether it moved (judged) and was flagged, and the worst scalar. */
export function reducePushes(pushes, ideal, refFor) {
  const out = new Map();
  for (const p of pushes) {
    const perNode = new Map();
    const ref = refFor(p);
    for (const key of p.samples.keys()) {
      const frames = framesOf(p, key, ideal, ref);
      if (!frames || frames.length < 2) continue;
      const m = metrics(frames);
      if (flat(m)) continue;
      const nid = nodeOf(key);
      const cur = perNode.get(nid);
      const score = m.stalls + m.jumps + m.reversals + m.tailSteps;
      if (!cur) perNode.set(nid, { m, top: key, topScore: score });
      else perNode.set(nid, { m: worst(cur.m, m), top: score > cur.topScore ? key : cur.top, topScore: Math.max(score, cur.topScore) });
    }
    for (const n of p.nodes) {
      const k = `${p.window}|${n.id}`;
      if (!out.has(k)) out.set(k, { window: p.window, node: n.id, pushes: [] });
      const r = perNode.get(n.id);
      out.get(k).pushes.push(r ? { push: p.push, judged: true, flagged: flagged(r.m), m: r.m, top: r.top } : { push: p.push, judged: false, flagged: false, m: null, top: null });
    }
  }
  return [...out.values()];
}

/**
 * Everything one raw file holds: for each width and each arm, the reduction under both ideals. The `ref` ideal of the original is
 * built without the push's own repeat; of the other arms from all of the original's repeats of the same direction.
 */
export function reduceRaw(raw) {
  const out = [];
  const widths = [...new Set(raw.runs.map((r) => r.width))];
  for (const width of widths) {
    const runs = raw.runs.filter((r) => r.width === width);
    const origRun = runs.find((r) => r.role === 'orig');
    const origPushes = origRun ? pushesOf(origRun) : [];
    for (const run of runs) {
      const pushes = run.role === 'orig' ? origPushes : pushesOf(run);
      const refFor = (p) => {
        if (p.window === 'hero') return origPushes.find((o) => o.window === 'hero' && o.push === p.push) ?? null;
        return origPushes.filter((o) => o.window === p.window && !(run.role === 'orig' && o.rep === p.rep));
      };
      for (const ideal of ['line', 'ref']) {
        if (ideal === 'ref' && run.role === 'orig' && pushes.every((p) => p.window === 'hero')) continue;
        const refForIdeal = run.role === 'orig' && ideal === 'ref' ? (p) => (p.window === 'hero' ? null : refFor(p)) : refFor;
        for (const x of reducePushes(pushes, ideal, refForIdeal)) out.push({ width, role: run.role, search: run.search, ideal, ...x });
      }
    }
  }
  return out;
}
