// Reduce a flip session (set flip) into the per-frame attribution tables. Decisions are device-flip-attr.mjs (Lean FlipAttr); this file
// reads raw lanes, groups by arm and prints. TS stand-in: the grouping and the table text.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { PUSH, pct, spanDts, spans } from './device-push.mjs';
import { rawName } from './device-phone-run.mjs';
import { attributeVisit, BUSY_WORKS, framesOfVisit, WAIT } from './device-flip-attr.mjs';
import { traceOf } from './device-push-run.mjs';

const WORKS = [...BUSY_WORKS, WAIT, 'idle'];
const NOT_BUSY = [WAIT, 'idle'];
const sumWorks = (o, ws) => ws.reduce((n, w) => n + o[w], 0);
const zero = () => Object.fromEntries(WORKS.map((w) => [w, 0]));
const med = (l) => { const s = [...l].sort((a, b) => a - b); return s.length ? s[Math.floor(s.length / 2)] : null; };
const where = (lead) => {
  if (!lead) return null;
  const d = lead.data ?? {};
  if (lead.type === 'FunctionCall' || lead.type === 'EvaluateScript') return `${lead.type} ${String(d.scriptName ?? '').split('/').pop()}:${d.scriptLine ?? '?'}:${d.scriptColumn ?? '?'}`;
  if (lead.type === 'EventDispatch') return `EventDispatch ${d.type ?? '?'}`;
  if (lead.type === 'Paint') return 'Paint';
  return lead.type;
};

export function framesStats(fr) {
  const sps = spans(fr.f, fr.hiEnd, fr.ts);
  const d = spanDts(sps, fr.f);
  return { n: d.length, p95: pct(95, d), p99: pct(99, d), max: pct(100, d), over: d.filter((x) => PUSH.overLimit < x).length };
}

const BUCKET = 50000;
const TYPES = ['RecalculateStyles', 'Layout', 'Paint', 'Composite', 'ScheduleStyleRecalculation', 'InvalidateLayout'];
const EVENT_GROUPS = { touch: /^(touch|pointer)/, transition: /^transition/, animation: /^animation/ };

/** Where the long frames sit (500 ms buckets since the touch start) and what the long and the other frames hold (record counts, record time clipped to the interval, event counts by group). */
function shape(tl, rows) {
  const sps = spans(tl.f, tl.hiEnd, tl.ts);
  const { recs } = framesOfVisit(tl);
  const byTime = {};
  const mix = { long: blank(), rest: blank() };
  const boxes = (tl.anim?.anims ?? []).filter((x) => x.rect && !/morph-module/.test(x.name ?? ''));
  const ownerOf = (c) => {
    const cx = (c[0] + c[2]) / 2, cy = (c[1] + c[5]) / 2;
    const hit = boxes.filter((x) => x.rect[0] <= cx && cx <= x.rect[0] + x.rect[2] && x.rect[1] <= cy && cy <= x.rect[1] + x.rect[3]);
    return hit.length ? [...new Set(hit.map((x) => String(x.name).replace(/_[A-Za-z0-9-]{6}$/, '')))].sort().join('+') : 'no animated box';
  };
  for (const r of rows) {
    const k = Math.floor((r.a - sps[r.push][0]) / BUCKET);
    const t = (byTime[k] ??= { long: 0, all: 0 });
    t.all += 1;
    if (r.over) t.long += 1;
    const m = mix[r.over ? 'long' : 'rest'];
    m.frames += 1;
    for (const x of recs) {
      if (!(x.e > r.a && x.s < r.b)) continue;
      if (TYPES.includes(x.type)) { m.n[x.type] += 1; m.cs[x.type] += Math.min(x.e, r.b) - Math.max(x.s, r.a); }
      if (x.type === 'Paint' && x.src.data?.clip) { m.clips += 1; const o = ownerOf(x.src.data.clip); m.owners[o] = (m.owners[o] ?? 0) + 1; }
      if (x.type === 'EventDispatch') for (const [g, re] of Object.entries(EVENT_GROUPS)) if (re.test(x.src.data?.type ?? '')) m.ev[g] += 1;
    }
  }
  return { byTime, mix };
}
const blank = () => ({ frames: 0, clips: 0, owners: {}, n: Object.fromEntries(TYPES.map((t) => [t, 0])), cs: Object.fromEntries(TYPES.map((t) => [t, 0])), ev: Object.fromEntries(Object.keys(EVENT_GROUPS).map((g) => [g, 0])) });

export function visitAttr(dir, v) {
  const file = join(dir, rawName(v.index, v.arm, 'tl'));
  if (!existsSync(file)) return null;
  const tl = JSON.parse(readFileSync(file, 'utf8'));
  const { p95, rows } = attributeVisit(tl);
  const pick = (rs) => rs.reduce((m, r) => { m[r.work] += 1; return m; }, zero());
  const long = rows.filter((r) => r.over);
  const frames = framesStats({ f: tl.f, hiEnd: tl.hiEnd, ts: tl.ts });
  const fr = JSON.parse(readFileSync(join(dir, rawName(v.index, v.arm, 'frames')), 'utf8'));
  const lane = framesStats({ f: fr.f, hiEnd: fr.hiEnd, ts: fr.ts });
  const leads = {};
  for (const r of long) { const k = `${r.work}: ${where(r.lead) ?? '-'}`; leads[k] = (leads[k] ?? 0) + 1; }
  const sched = {};
  for (const r of long) if (BUSY_WORKS.includes(r.work)) for (const c of r.sched) sched[c ?? 'no script stack'] = (sched[c ?? 'no script stack'] ?? 0) + 1;
  const idleBusy = rows.filter((r) => r.work === 'idle').map((r) => Math.round((100 * r.busy) / r.d));
  return {
    index: v.index, arm: v.arm, round: v.round, position: v.position, intervals: rows.length, p95, max: Math.max(0, ...rows.map((r) => r.d)),
    over: long.length, overNotBusy: long.filter((r) => !BUSY_WORKS.includes(r.work)).length, sched, overByWork: pick(long), tailByWork: pick(rows.filter((r) => r.tail)), allByWork: pick(rows),
    overMs: long.reduce((n, r) => n + r.d, 0) / 100, busyShareOver: long.length ? Math.round((100 * long.reduce((n, r) => n + r.busy, 0)) / long.reduce((n, r) => n + r.d, 0)) : null,
    ...shape(tl, rows), framesTl: frames, framesLane: lane, leads, idleBusyPct: idleBusy, trace: traceOf(tl.ts, tl.tr),
    worst: [...long].sort((a, b) => b.d - a.d).slice(0, 5).map((r) => ({ push: r.push, d: r.d, work: r.work, times: r.times, busy: r.busy, lead: r.lead && { t: r.lead.t, type: r.lead.type, where: where(r.lead) } })),
    anim: tl.anim ? { n: tl.anim.n ?? null, error: tl.anim.error ?? null, nav: tl.anim.nav ?? null, groups: groupAnims(tl.anim.anims ?? []) } : null,
  };
}

function groupAnims(list) {
  const g = {};
  for (const a of list) {
    const k = `${a.kind} ${a.name ?? '-'} on ${a.target ?? '-'} [${(a.props ?? []).join(',')}] ${a.play}`;
    g[k] = (g[k] ?? 0) + 1;
  }
  return Object.entries(g).sort((x, y) => y[1] - x[1]).slice(0, 12).map(([k, n]) => ({ k, n }));
}

export function flipAttribution(dir, rows, arms) {
  const visits = rows.map((r) => visitAttr(dir, r)).filter(Boolean);
  const perArm = arms.map((a) => {
    const vs = visits.filter((v) => v.arm === a.id);
    const sum = (key) => Object.fromEntries(WORKS.map((w) => [w, vs.reduce((n, v) => n + v[key][w], 0)]));
    const leads = {};
    for (const v of vs) for (const [k, n] of Object.entries(v.leads)) leads[k] = (leads[k] ?? 0) + n;
    const sched = {};
    for (const v of vs) for (const [k, n] of Object.entries(v.sched)) sched[k] = (sched[k] ?? 0) + n;
    const byTime = {};
    const mix = { long: blank(), rest: blank() };
    for (const v of vs) {
      for (const [k, t] of Object.entries(v.byTime)) { const b = (byTime[k] ??= { long: 0, all: 0 }); b.long += t.long; b.all += t.all; }
      for (const kind of ['long', 'rest']) {
        const m = mix[kind], x = v.mix[kind];
        m.frames += x.frames;
        m.clips += x.clips;
        for (const [o, c] of Object.entries(x.owners)) m.owners[o] = (m.owners[o] ?? 0) + c;
        for (const t of TYPES) { m.n[t] += x.n[t]; m.cs[t] += x.cs[t]; }
        for (const g of Object.keys(EVENT_GROUPS)) m.ev[g] += x.ev[g];
      }
    }
    return {
      byTime, mix, sched: Object.entries(sched).sort((x, y) => y[1] - x[1]).slice(0, 5).map(([k, n]) => ({ k, n })), schedAll: Object.values(sched).reduce((n, x) => n + x, 0), overNotBusy: vs.reduce((n, v) => n + v.overNotBusy, 0), id: a.id, n: vs.length, over: vs.reduce((n, v) => n + v.over, 0), overByWork: sum('overByWork'), tailByWork: sum('tailByWork'), allByWork: sum('allByWork'),
      intervals: vs.reduce((n, v) => n + v.intervals, 0), p95Tl: med(vs.map((v) => v.p95)), maxTl: Math.max(0, ...vs.map((v) => v.max)), busyShareOver: med(vs.map((v) => v.busyShareOver).filter((x) => x !== null)),
      leads: Object.entries(leads).sort((x, y) => y[1] - x[1]).slice(0, 8).map(([k, n]) => ({ k, n })),
      anim: vs.find((v) => v.anim)?.anim ?? null,
    };
  });
  return { schema: 'fw.phone.flip-attr/1', limitCentiMs: PUSH.overLimit, works: WORKS, visits, perArm };
}

const pctOf = (n, d) => (d ? `${Math.round((100 * n) / d)}%` : '-');

export function flipTables(attr, summary) {
  const out = ['', '## Frame attribution (tl lane: Timeline on, frames cut by the rAF times, work by the innermost record)', ''];
  out.push('Main-thread busy = script, style, layout, paint. `commitWait` is the WebKit `Composite` span (CA commit and flush; it ends after an off-main flush, so it is not main-thread busy). A frame under half busy is `commitWait` when that span fills half of it, else `idle`.', '');
  out.push('| arm | n | intervals | over 50 ms | ' + WORKS.join(' | ') + ' | not main-busy (commitWait + idle) | main-thread busy share of the over-50 time |', '|---|---|---|---|' + WORKS.map(() => '---').join('|') + '|---|---|');
  for (const a of attr.perArm) out.push(`| ${a.id} | ${a.n} | ${a.intervals} | ${a.over} | ${WORKS.map((w) => `${a.overByWork[w]} (${pctOf(a.overByWork[w], a.over)})`).join(' | ')} | ${a.overNotBusy} of ${a.over} | ${a.busyShareOver ?? '-'}% |`);
  out.push('', 'Tail (frames at or over the visit p95 of the tl lane):', '', '| arm | frames | ' + WORKS.join(' | ') + ' |', '|---|---|' + WORKS.map(() => '---').join('|') + '|');
  for (const a of attr.perArm) { const t = WORKS.reduce((n, w) => n + a.tailByWork[w], 0); out.push(`| ${a.id} | ${t} | ${WORKS.map((w) => `${a.tailByWork[w]} (${pctOf(a.tailByWork[w], t)})`).join(' | ')} |`); }
  out.push('', 'Lead records of the over-50 frames (dominant work: record):', '');
  for (const a of attr.perArm) { out.push(`- ${a.id}: ${a.leads.map((l) => `${l.k} x${l.n}`).join('; ') || 'none'}`); }
  out.push('', 'Style invalidations in the main-busy long frames (ScheduleStyleRecalculation records inside the interval; caller = top script frame of its stack; the Timeline names no element for them):', '');
  for (const a of attr.perArm) out.push(`- ${a.id}: ${a.schedAll} records; ${a.sched.map((l) => `${l.k} x${l.n}`).join('; ') || 'none'}`);
  out.push('', 'Running animations at the start of the pushes (first visit with a snapshot):', '');
  for (const a of attr.perArm) out.push(`- ${a.id}: ${a.anim ? (a.anim.error ? `error ${a.anim.error}` : `${a.anim.n} animations; ${a.anim.groups.map((g) => `${g.k} x${g.n}`).join('; ')}`) : 'none'}`);
  out.push('', 'Long frames (over 50 ms) by time since the touch start, long / all intervals of the tl lane:', '', '| arm | 0-0.5 s | 0.5-1 s | 1-1.5 s | later |', '|---|---|---|---|---|');
  for (const a of attr.perArm) {
    const at = (lo, hi) => Object.entries(a.byTime).filter(([k]) => lo <= Number(k) && Number(k) < hi).reduce((n, [, t]) => [n[0] + t.long, n[1] + t.all], [0, 0]);
    out.push(`| ${a.id} | ${at(0, 1).join(' / ')} | ${at(1, 2).join(' / ')} | ${at(2, 3).join(' / ')} | ${at(3, 1e9).join(' / ')} |`);
  }
  out.push('', 'Mean per interval of records overlapping it (record time in ms is the sum of the record lengths clipped to the interval, nested records counted in full):', '',
    '| arm | frames | n | style n | style ms | layout n | paint n | composite ms | touch+pointer events | transition events | animation events |', '|---|---|---|---|---|---|---|---|---|---|---|');
  for (const a of attr.perArm) for (const kind of ['long', 'rest']) {
    const m = a.mix[kind], f = Math.max(1, m.frames), per = (x) => (x / f).toFixed(1);
    out.push(`| ${a.id} | ${kind === 'long' ? 'over 50 ms' : 'other'} | ${m.frames} | ${per(m.n.RecalculateStyles)} | ${(m.cs.RecalculateStyles / 100 / f).toFixed(1)} | ${per(m.n.Layout)} | ${per(m.n.Paint)} | ${(m.cs.Composite / 100 / f).toFixed(1)} | ${per(m.ev.touch)} | ${per(m.ev.transition)} | ${per(m.ev.animation)} |`);
  }
  out.push('', 'Paint clip rectangles by the animated element box (snapshot of document.getAnimations() at the start of the pushes; morph tracks left out) that holds the clip centre; top five, share of all clips:', '');
  for (const a of attr.perArm) for (const kind of ['long', 'rest']) {
    const m = a.mix[kind];
    out.push(`- ${a.id}, ${kind === 'long' ? 'over 50 ms' : 'other'} (${m.clips} clips): ${Object.entries(m.owners).sort((x, y) => y[1] - x[1]).slice(0, 5).map(([o, c]) => `${Math.round((100 * c) / Math.max(1, m.clips))}% ${o}`).join('; ') || 'none'}`);
  }
  out.push('', 'Frames lane (the r2-comparable one), all visits of the arm pooled: frame intervals inside the push spans, those over 50 ms, and the worst interval:', '',
    '| arm | visits | intervals | over 50 ms | per 100 intervals | worst interval (ms) | Lean label against the base |', '|---|---|---|---|---|---|---|');
  for (const a of attr.perArm) {
    const vs = attr.visits.filter((v) => v.arm === a.id);
    const n = vs.reduce((t, v) => t + v.framesLane.n, 0), o = vs.reduce((t, v) => t + v.framesLane.over, 0);
    out.push(`| ${a.id} | ${vs.length} | ${n} | ${o} | ${(100 * o / Math.max(1, n)).toFixed(1)} | ${(Math.max(0, ...vs.map((v) => v.framesLane.max)) / 100).toFixed(1)} | ${(summary.arms ?? []).find((x) => x.id === a.id)?.label ?? '-'} |`);
  }
  const ms = (cs) => (cs / 100).toFixed(1);
  const medOf = (a, key) => med(attr.visits.filter((v) => v.arm === a.id).map((v) => v.framesTl[key]));
  out.push('', 'Frames lane (no Timeline) against the tl lane (Timeline on), median over the visits of the arm; ms:', '', '| arm | frames lane p95 | tl lane p95 | frames lane over 50 ms | tl lane over 50 ms | tl lane max |', '|---|---|---|---|---|---|');
  for (const a of attr.perArm) {
    const fa = (summary.arms ?? []).find((x) => x.id === a.id);
    out.push(`| ${a.id} | ${fa?.metrics?.p95 ? fa.metrics.p95.median / 100 : '-'} | ${ms(medOf(a, 'p95'))} | ${fa?.metrics?.over50 ? fa.metrics.over50.median : '-'} | ${medOf(a, 'over')} | ${ms(medOf(a, 'max'))} |`);
  }
  out.push('', 'Worst five over-50 frames per arm (ms; dominant work; lead record):', '');
  for (const a of attr.perArm) {
    const w = attr.visits.filter((v) => v.arm === a.id).flatMap((v) => v.worst.map((x) => ({ ...x, visit: v.index }))).sort((x, y) => y.d - x.d).slice(0, 5);
    out.push(`- ${a.id}: ${w.map((x) => `${ms(x.d)} ${x.work} (${x.lead?.where ?? '-'}, visit ${x.visit})`).join('; ')}`);
  }
  return out.join('\n') + '\n';
}
