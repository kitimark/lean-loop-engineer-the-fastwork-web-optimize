import { readFileSync } from 'node:fs';
import { PUSH, clockOff, framesIn, pct, spans } from './device-push.mjs';
import { toHundredths } from './profile/reduce.mjs';

const GOLDEN = readFileSync(new URL('../../contracts/golden/device/phone-arms.jsonl', import.meta.url), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));
export const WORK = Object.freeze(GOLDEN.find((l) => l.kind === 'flipwork'));
export const BUSY_WORKS = WORK.busyWorks;
export const WAIT = 'commitWait';

const SCRIPT = new Set(['EventDispatch', 'TimerFire', 'EvaluateScript', 'FunctionCall', 'FireAnimationFrame', 'ObserverCallback']);
const BY_TYPE = { RecalculateStyles: 'style', Layout: 'layout', Paint: 'paint', Composite: 'commitWait' };
export const workOf = (t) => (SCRIPT.has(t) ? 'script' : BY_TYPE[t] ?? null);

export const cuts = (a, b, rs) => [a, b, ...rs.flatMap((r) => [r.s, r.e]).filter((t) => a < t && t < b)].sort((x, y) => x - y);

export function innerIdx(x, y, rs) {
  let best = null;
  rs.forEach((r, i) => {
    if (r.s <= x && y <= r.e && x < y && (best === null || rs[best].s <= r.s)) best = i;
  });
  return best;
}

const pieces = (a, b, rs) => { const c = cuts(a, b, rs); return c.slice(1).map((y, i) => [c[i], y, innerIdx(c[i], y, rs)]); };
export const workTime = (a, b, rs, w) => pieces(a, b, rs).filter((p) => p[2] !== null && workOf(rs[p[2]].type) === w).reduce((n, p) => n + p[1] - p[0], 0);
export const held = (a, b, rs, i) => pieces(a, b, rs).filter((p) => p[2] === i).reduce((n, p) => n + p[1] - p[0], 0);
export const busy = (a, b, rs) => BUSY_WORKS.reduce((n, w) => n + workTime(a, b, rs, w), 0);

export function dominant(a, b, rs) {
  if (busy(a, b, rs) * WORK.idleDen < (b - a) * WORK.idleNum) return (b - a) * WORK.idleNum <= workTime(a, b, rs, WAIT) * WORK.idleDen ? WAIT : 'idle';
  const t = Object.fromEntries(BUSY_WORKS.map((w) => [w, workTime(a, b, rs, w)]));
  let best = 'script';
  for (const w of BUSY_WORKS) if (t[best] < t[w]) best = w;
  return best;
}

export function lead(a, b, rs, w) {
  let best = null;
  let bt = 0;
  rs.forEach((r, i) => {
    if (workOf(r.type) !== w) return;
    const h = held(a, b, rs, i);
    if (best === null ? 0 < h : bt < h) { best = i; bt = h; }
  });
  return best;
}

export const leadOf = (a, b, rs) => { const w = dominant(a, b, rs); return w === 'idle' ? null : lead(a, b, rs, w); };

export const tailOf = (limit, ds) => ds.filter((d) => limit <= d);

export function recsOf(tree, off) {
  const out = [];
  const at = (sec) => toHundredths(sec * 1000) - off;
  const walk = (r) => {
    if (!r || typeof r.startTime !== 'number') return;
    const s = at(r.startTime);
    out.push({ type: r.type, s, e: typeof r.endTime === 'number' ? at(r.endTime) : s, src: r });
    for (const k of r.children ?? []) walk(k);
  };
  for (const r of tree) walk(r);
  return out.sort((x, y) => x.s - y.s || y.e - x.e);
}

export function framesOfVisit(tl) {
  const sps = spans(tl.f, tl.hiEnd, tl.ts);
  const off = clockOff(tl.tlA, tl.tlB, tl.a, tl.b);
  if (off === null) throw new Error('the Timeline and page clocks drift apart in the tl lane');
  const recs = recsOf(tl.tree, off);
  const ivs = sps.flatMap((sp, push) => {
    const fs = framesIn(sp, tl.f);
    return fs.slice(1).map((f, i) => ({ push, a: fs[i][0], b: f[0], d: f[0] - fs[i][0], y: f[1], m: f[2] }));
  });
  return { ivs, recs, off };
}

export function callerOf(rec) {
  const f = rec?.stackTrace?.callFrames?.[0];
  return f ? `${f.functionName || '(anonymous)'} ${String(f.url ?? '').split('/').pop()}:${f.lineNumber ?? '?'}` : null;
}

export function attributeVisit(tl, { limit = PUSH.overLimit } = {}) {
  const { ivs, recs } = framesOfVisit(tl);
  const p95 = pct(95, ivs.map((x) => x.d));
  const rows = ivs.map((iv) => {
    const near = recs.filter((r) => r.e > iv.a && r.s < iv.b);
    const w = dominant(iv.a, iv.b, near);
    const times = Object.fromEntries(BUSY_WORKS.map((k) => [k, workTime(iv.a, iv.b, near, k)]));
    const li = w === 'idle' ? null : lead(iv.a, iv.b, near, w);
    return { ...iv, work: w, times, wait: workTime(iv.a, iv.b, near, WAIT), busy: busy(iv.a, iv.b, near), sched: near.filter((r) => r.type === 'ScheduleStyleRecalculation').map((r) => callerOf(r.src)), lead: li === null ? null : { t: held(iv.a, iv.b, near, li), type: near[li].type, data: near[li].src.data ?? null, stack: near[li].src.stackTrace ?? null }, over: limit < iv.d, tail: p95 <= iv.d };
  });
  return { p95, rows };
}
