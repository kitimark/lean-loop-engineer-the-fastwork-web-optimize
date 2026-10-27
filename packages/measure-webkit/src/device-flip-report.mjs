// Reduce a flip session (set flip) into the per-frame attribution tables. Decisions are device-flip-attr.mjs (Lean FlipAttr); this file
// reads raw lanes, groups by arm and prints. TS stand-in: the grouping and the table text.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { PUSH, pct, spanDts, spans } from './device-push.mjs';
import { rawName } from './device-phone-run.mjs';
import { attributeVisit, BUSY_WORKS } from './device-flip-attr.mjs';
import { traceOf } from './device-push-run.mjs';

const WORKS = [...BUSY_WORKS, 'idle'];
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

export function visitAttr(dir, v) {
  const file = join(dir, rawName(v.index, v.arm, 'tl'));
  if (!existsSync(file)) return null;
  const tl = JSON.parse(readFileSync(file, 'utf8'));
  const { p95, rows } = attributeVisit(tl);
  const pick = (rs) => rs.reduce((m, r) => { m[r.work] += 1; return m; }, zero());
  const long = rows.filter((r) => r.over);
  const frames = framesStats({ f: tl.f, hiEnd: tl.hiEnd, ts: tl.ts });
  const leads = {};
  for (const r of long) { const k = `${r.work}: ${where(r.lead) ?? '-'}`; leads[k] = (leads[k] ?? 0) + 1; }
  const idleBusy = rows.filter((r) => r.work === 'idle').map((r) => Math.round((100 * r.busy) / r.d));
  return {
    index: v.index, arm: v.arm, round: v.round, position: v.position, intervals: rows.length, p95, max: Math.max(0, ...rows.map((r) => r.d)),
    over: long.length, overByWork: pick(long), tailByWork: pick(rows.filter((r) => r.tail)), allByWork: pick(rows),
    overMs: long.reduce((n, r) => n + r.d, 0) / 100, busyShareOver: long.length ? Math.round((100 * long.reduce((n, r) => n + r.busy, 0)) / long.reduce((n, r) => n + r.d, 0)) : null,
    framesTl: frames, leads, idleBusyPct: idleBusy, trace: traceOf(tl.ts, tl.tr),
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
    return {
      id: a.id, n: vs.length, over: vs.reduce((n, v) => n + v.over, 0), overByWork: sum('overByWork'), tailByWork: sum('tailByWork'), allByWork: sum('allByWork'),
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
  out.push('| arm | n | intervals | over 50 ms | ' + WORKS.join(' | ') + ' | busy share of the over-50 frames |', '|---|---|---|---|' + WORKS.map(() => '---').join('|') + '|---|');
  for (const a of attr.perArm) out.push(`| ${a.id} | ${a.n} | ${a.intervals} | ${a.over} | ${WORKS.map((w) => `${a.overByWork[w]} (${pctOf(a.overByWork[w], a.over)})`).join(' | ')} | ${a.busyShareOver ?? '-'}% |`);
  out.push('', 'Tail (frames at or over the visit p95 of the tl lane):', '', '| arm | frames | ' + WORKS.join(' | ') + ' |', '|---|---|' + WORKS.map(() => '---').join('|') + '|');
  for (const a of attr.perArm) { const t = WORKS.reduce((n, w) => n + a.tailByWork[w], 0); out.push(`| ${a.id} | ${t} | ${WORKS.map((w) => `${a.tailByWork[w]} (${pctOf(a.tailByWork[w], t)})`).join(' | ')} |`); }
  out.push('', 'Lead records of the over-50 frames (dominant work: record):', '');
  for (const a of attr.perArm) { out.push(`- ${a.id}: ${a.leads.map((l) => `${l.k} x${l.n}`).join('; ') || 'none'}`); }
  out.push('', 'Running animations at the start of the pushes (first visit with a snapshot):', '');
  for (const a of attr.perArm) out.push(`- ${a.id}: ${a.anim ? (a.anim.error ? `error ${a.anim.error}` : `${a.anim.n} animations; ${a.anim.groups.map((g) => `${g.k} x${g.n}`).join('; ')}`) : 'none'}`);
  void summary;
  return out.join('\n') + '\n';
}
