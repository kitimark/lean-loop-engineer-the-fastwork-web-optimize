// THE ONE PURE REDUCTION MODULE of this package. No I/O, no protocol, no clock.
//
// Policy (CLAUDE.md, "Lean first"): the harness (Simulator, Inspector protocol, I/O) is TypeScript/JS, but everything
// after raw counts is meant to come from Lean (Fw/Spec/Screen, Cost, Verdict, Frames). The harness therefore writes
// RAW records as plain JSON (schemas below) and this module is the interim reduction of them. Every export here
// needs a Lean spec + golden vectors; nothing here is a verdict, a landing class or a gate.
//
// Raw schema `fw.webkit.records/1` (what scrollrun/seek/census write next to their reductions):
//   records : [[type, startTimeSeconds, endTimeSeconds|null, clipQuad|null], ...]  flattened Timeline records
//             (clipQuad = [x1,y1,x2,y2,x3,y3,x4,y4] of a Paint record, CSS px; null otherwise)
//   marks   : [startTimeSeconds, ...]  TimeStamp records of the step marks wk:s0, wk:s1, ...
//   endTime : startTimeSeconds of the wk:end mark
//
// Reductions here: record tallies per step (`reduceSteps`), zone sums (`zones`), the run-to-run comparison of a count
// across runs into deterministic / stable / quarantined (`classify`) and the multiset symmetric difference (`symDiff`).

/** Record types tallied in every vector (a fixed list: a vector's shape never depends on what happened to occur). */
export const COUNT_TYPES = Object.freeze([
  'RecalculateStyles', 'Layout', 'Paint', 'Composite', 'RenderingFrame',
  'FireAnimationFrame', 'TimerFire', 'ObserverCallback', 'EventDispatch', 'FunctionCall',
  'ScheduleStyleRecalculation', 'InvalidateLayout',
]);
const IGNORED = new Set(['TimeStamp', 'RequestAnimationFrame', 'CancelAnimationFrame', 'TimerInstall', 'TimerRemove']);

/** Area of a clip quad (shoelace), CSS px^2; 0 when missing. */
export function quadArea(q) {
  if (!Array.isArray(q) || q.length < 8) return 0;
  let s = 0;
  for (let i = 0; i < 4; i++) { const j = (i + 1) % 4; s += q[2 * i] * q[2 * j + 1] - q[2 * j] * q[2 * i + 1]; }
  return Math.abs(s) / 2;
}

/** Depth-first flatten of nested protocol records into the raw `records` rows. */
export function flattenRecords(records) {
  const out = [], stack = [...records].reverse();
  while (stack.length) {
    const r = stack.pop();
    if (!r) continue;
    const msg = r.type === 'TimeStamp' ? (r.data?.message ?? null) : null;
    out.push([r.type, r.startTime, r.endTime ?? null, r.type === 'Paint' ? (r.data?.clip ?? null) : msg]);
    if (Array.isArray(r.children)) for (let i = r.children.length - 1; i >= 0; i--) stack.push(r.children[i]);
  }
  return out;
}
// For a TimeStamp row the 4th column is the mark's message (string); for a Paint row the clip quad; else null.

/** Tally raw rows: counts per COUNT_TYPES, Paint clip area sum, and the other types seen. */
export function tally(rows) {
  const counts = Object.fromEntries(COUNT_TYPES.map((t) => [t, 0]));
  let paintArea = 0;
  const other = {};
  for (const [type, , , extra] of rows) {
    if (type in counts) counts[type]++;
    else if (!IGNORED.has(type)) other[type] = (other[type] || 0) + 1;
    if (type === 'Paint') paintArea += quadArea(extra);
  }
  return { counts, paintArea: Math.round(paintArea), other };
}

/** Start times of TimeStamp rows named `${prefix}${k}`, k = 0..n-1 (null where missing). */
export function markTimes(rows, prefix, n) {
  const t = new Array(n).fill(null);
  for (const [type, start, , msg] of rows) {
    if (type !== 'TimeStamp' || typeof msg !== 'string' || !msg.startsWith(prefix)) continue;
    const k = Number(msg.slice(prefix.length));
    if (Number.isInteger(k) && k >= 0 && k < n && t[k] === null) t[k] = start;
  }
  return t;
}

/** Start time of the first TimeStamp row with this exact message, or null. */
export const markTime = (rows, message) => rows.find((r) => r[0] === 'TimeStamp' && r[3] === message)?.[1] ?? null;

/**
 * Join rows to steps: row r belongs to step k when marks[k] <= r.start < marks[k+1] (the last step runs to
 * `endTime`). Returns per-step rows and the rows before the first mark.
 */
export function bucketBySteps(rows, marks, endTime) {
  const n = marks.length;
  const steps = Array.from({ length: n }, () => []);
  let before = 0;
  for (const r of rows) {
    const s = r[1];
    if (typeof s !== 'number' || s < marks[0]) { before++; continue; }
    if (s >= endTime) continue;
    let lo = 0, hi = n - 1;
    while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (marks[mid] <= s) lo = mid; else hi = mid - 1; }
    steps[lo].push(r);
  }
  return { steps, before };
}

/** Per-step and total tallies of a captured run. `marks` and `endTime` as in the raw schema. */
export function reduceSteps(rows, marks, endTime) {
  const { steps, before } = bucketBySteps(rows, marks, endTime);
  const per = steps.map(tally);
  const total = tally(rows.filter((r) => typeof r[1] === 'number' && r[1] >= marks[0] && r[1] < endTime));
  return {
    countTypes: COUNT_TYPES,
    perStep: per.map((t) => COUNT_TYPES.map((k) => t.counts[k])), // one row per step, columns COUNT_TYPES
    perStepPaintArea: per.map((t) => t.paintArea),
    total: { ...total.counts, paintArea: total.paintArea },
    other: total.other,
    rowsBeforeFirstStep: before,
  };
}

/** Aggregate per-step rows into zones of `zonePx` scroll px. `ys[i]` = scroll offset of step i. */
export function zones(ys, perStep, perStepPaintArea, zonePx = 500) {
  const out = [];
  ys.forEach((y, i) => {
    const z = Math.floor(y / zonePx);
    while (out.length <= z) out.push({ zone: out.length, y0: out.length * zonePx, steps: 0, counts: new Array(COUNT_TYPES.length).fill(0), paintArea: 0 });
    const o = out[z];
    o.steps++;
    perStep[i].forEach((v, j) => { o.counts[j] += v; });
    o.paintArea += perStepPaintArea[i];
  });
  return out;
}

// ---- run-to-run comparison (PLAN V-i) -------------------------------------------------------------------------
//   deterministic : every cell is identical in every run.
//   stable        : not identical, but every cell's spread (max - min over the runs) <= max(absTol, relTol * max|v|).
//   quarantined   : some cell spreads beyond that. Reported, never gated on.
// A "cell" is one number: a total, a zone sum, a step, a per-state layer count... Vectors compare cell by cell;
// vectors of different length are quarantined.

/** Tolerances per aggregation level (documented in the README). */
export const TOL = Object.freeze({
  census: { absTol: 1, relTol: 0.05 },
  memory: { absTol: 0, relTol: 0.02 },
  paint: { absTol: 2, relTol: 0.1 },
  total: { absTol: 2, relTol: 0.05 },
  zone: { absTol: 2, relTol: 0.1 },
  step: { absTol: 1, relTol: 0 },
  exact: { absTol: 0, relTol: 0 },
});

/** @param {number[][]} runs one array of cells per run */
export function classify(runs, tol) {
  if (runs.length < 2) throw new Error('need at least two runs');
  const len = runs[0].length;
  if (runs.some((r) => r.length !== len)) return { cls: 'quarantined', reason: 'vector length differs between runs', cells: len, differingCells: null, cellsBeyondTolerance: null, maxSpread: null, maxRelSpread: null };
  let differing = 0, maxSpread = 0, maxRel = 0, beyond = 0;
  for (let i = 0; i < len; i++) {
    let lo = Infinity, hi = -Infinity, big = 0;
    for (const r of runs) { lo = Math.min(lo, r[i]); hi = Math.max(hi, r[i]); big = Math.max(big, Math.abs(r[i])); }
    const spread = hi - lo;
    if (spread === 0) continue;
    differing++;
    maxSpread = Math.max(maxSpread, spread);
    if (big > 0) maxRel = Math.max(maxRel, spread / big);
    if (spread > Math.max(tol.absTol, tol.relTol * big)) beyond++;
  }
  const cls = differing === 0 ? 'deterministic' : beyond === 0 ? 'stable' : 'quarantined';
  return { cls, cells: len, differingCells: differing, cellsBeyondTolerance: beyond, maxSpread, maxRelSpread: Math.round(maxRel * 1e4) / 1e4 };
}

/**
 * Session-independent identity of a census layer (layer ids and node ids are per inspector session and left out):
 * name | pseudo | bounds | compositedBounds | backing bytes | reasons.
 */
export const layerKey = (l) => `${l.name}|${l.pseudo || ''}|${l.bounds}|${l.compositedBounds}|${l.memory}|${l.reasons.join('+')}`;

/** Multiset symmetric-difference size between two lists of strings. */
export function symDiff(a, b) {
  const m = new Map();
  for (const x of a) m.set(x, (m.get(x) || 0) + 1);
  for (const x of b) m.set(x, (m.get(x) || 0) - 1);
  let d = 0;
  for (const v of m.values()) d += Math.abs(v);
  return d;
}

/** The weakest level decides the class of a (family, metric). */
export function summarize(rows) {
  const order = { deterministic: 0, stable: 1, quarantined: 2 };
  const by = new Map();
  for (const r of rows) {
    const key = `${r.family}|${r.metric}`;
    const e = by.get(key) || { family: r.family, metric: r.metric, levels: {} };
    e.levels[r.level] = r.cls;
    by.set(key, e);
  }
  return [...by.values()].map((e) => ({ ...e, worst: Object.values(e.levels).reduce((w, c) => (order[c] > order[w] ? c : w), 'deterministic') }));
}
