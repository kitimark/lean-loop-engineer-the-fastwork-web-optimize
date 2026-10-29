export const BS_ARMS = ['bs-facts', 'bs-full-a', 'bs-hidden-a', 'bs-obs', 'bs-l1', 'bs-l2', 'bs-deep', 'bs-hold', 'bs-kill', 'bs-pause', 'bs-full-b', 'bs-hidden-b'];
export const BS_C = { minFrames: 40, minSpread: 50, bandDen: 4, maxDepth: 6, minValid: 2 };

export const rpf100 = (a) => (a.frames === 0 ? 0 : Math.floor((a.recalcs * 100) / a.frames));
const ok = (a) => BS_C.minFrames <= a.frames;
const readable = (as) => as.filter(ok);
export const hi = (j) => readable(j.full).map(rpf100).reduce((m, r) => Math.min(m, r), 100);
export const lo = (j) => readable(j.hidden).map(rpf100).reduce((m, r) => Math.max(m, r), 0);
const spread = (j) => Math.max(0, hi(j) - lo(j));
export const band = (j) => Math.floor(spread(j) / BS_C.bandDen);
const hasFrames = (j) => readable(j.full).length > 0 && readable(j.hidden).length > 0;
const contrast = (j) => BS_C.minSpread <= spread(j);

export function cls(j, a) {
  if (!ok(a)) return 'unread';
  if (rpf100(a) <= lo(j) + band(j)) return 'dropped';
  if (hi(j) - band(j) <= rpf100(a)) return 'kept';
  return 'between';
}

const kids = (j, parent) => j.parts.filter((p) => p.parent === parent);
const clsOf = (j, parent, c) => kids(j, parent).filter((p) => cls(j, p.arm) === c);

/** Level: { t: 'named', p } | { t: 'none' | 'several' | 'incomplete' | 'leaf' }. */
export function level(j, parent) {
  if (kids(j, parent).length === 0) {
    if (parent === '') return { t: 'incomplete' };
    const p = j.parts.find((x) => x.path === parent);
    return p && p.kids === 0 ? { t: 'leaf' } : { t: 'incomplete' };
  }
  if (clsOf(j, parent, 'unread').length > 0) return { t: 'incomplete' };
  const d = clsOf(j, parent, 'dropped');
  const b = clsOf(j, parent, 'between');
  if (d.length === 1 && b.length === 0) return { t: 'named', p: d[0].path };
  if (d.length === 0 && b.length === 0) return { t: 'none' };
  return { t: 'several' };
}

export function descend(j, fuel, parent) {
  if (fuel === 0) return [[], { t: 'incomplete' }];
  const l = level(j, parent);
  if (l.t !== 'named') return [[], l];
  const [rest, stop] = descend(j, fuel - 1, l.p);
  return [[l.p, ...rest], stop];
}

/** Res: { t: 'no-frames' | 'no-contrast' | 'incomplete' } | { t: 'found', path, stop }. */
export function res(j) {
  if (!hasFrames(j)) return { t: 'no-frames' };
  if (!contrast(j)) return { t: 'no-contrast' };
  const [path, stop] = descend(j, BS_C.maxDepth, '');
  if (path.length === 0 && stop.t === 'incomplete') return { t: 'incomplete' };
  return { t: 'found', path, stop };
}
export const resName = (r) => (r.t === 'found' ? `found ${r.path.join(' > ')} ${r.stop.t === 'named' ? `named ${r.stop.p}` : r.stop.t}` : r.t);
export const valid = (r) => r.t === 'found';

const NEXT = {
  named: 'read the WebKit path that restyles the named part, propose one same-look fix',
  several: 'one show-only arm per part',
  none: 'show-only arms: hiding one part does not drop the rate',
  inconclusive: 'rerun with contrast or more valid jobs',
};
const same = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

export function overall(rs) {
  const vs = rs.filter(valid);
  if (vs.length < BS_C.minValid) return { name: 'inconclusive', next: NEXT.inconclusive };
  const lead = vs[0].path;
  if (!vs.every((r) => same(r.path, lead))) return { name: 'several', next: NEXT.several };
  if (lead.length === 0) return vs.every((r) => r.stop.t === 'none') ? { name: 'none', next: NEXT.none } : { name: 'several', next: NEXT.several };
  return { name: `named ${lead.join(' > ')}`, next: NEXT.named };
}

export const KILL = 'kill';
export const ONLY = 'only';
export const PAUSE = 'pause';
export const ready = (j) => hasFrames(j) && contrast(j);
export const carrier = (j) => (ready(j) ? level(j, KILL) : { t: 'incomplete' });

export function levelKept(j, parent) {
  if (kids(j, parent).length === 0) return { t: 'incomplete' };
  if (clsOf(j, parent, 'unread').length > 0) return { t: 'incomplete' };
  const k = clsOf(j, parent, 'kept');
  const b = clsOf(j, parent, 'between');
  if (k.length === 1 && b.length === 0) return { t: 'named', p: k[0].path };
  if (k.length === 0 && b.length === 0) return { t: 'none' };
  return { t: 'several' };
}
export const pauser = (j) => (ready(j) ? level(j, PAUSE) : { t: 'incomplete' });
export const holder = (j) => (ready(j) ? levelKept(j, ONLY) : { t: 'incomplete' });
export const levelName = (l) => (l.t === 'named' ? `named ${l.p}` : l.t);
export const decided = (l) => l.t !== 'incomplete' && l.t !== 'leaf';

export function overall2(ls) {
  const ds = ls.filter(decided);
  if (ds.length < BS_C.minValid) return { name: 'inconclusive', next: NEXT.inconclusive };
  const f = ds[0];
  if (f.t === 'named') return ds.every((l) => l.t === 'named' && l.p === f.p) ? { name: `named ${f.p}`, next: NEXT.named } : { name: 'several', next: NEXT.several };
  if (f.t === 'none') return ds.every((l) => l.t === 'none') ? { name: 'none', next: NEXT.none } : { name: 'several', next: NEXT.several };
  return { name: 'several', next: NEXT.several };
}

export const jobOfGolden = (g) => ({ full: g.full, hidden: g.hidden, parts: g.parts });

const rowOf = (report, arm) => report.rows.find((r) => r.arm === arm && r.bs);
const arm = (r) => ({ frames: r.frames, recalcs: r.recalcs });

/** Glue: one report (one WKTR job) to the Lean job. Parts the facts arm listed but no hide arm read are unread arms. */
export function reportToJob(report) {
  const reads = (names) => names.map((n) => rowOf(report, n)?.bs?.read).filter(Boolean).map(arm);
  const parts = [];
  for (const n of ['bs-l1', 'bs-l2', 'bs-deep', 'bs-kill', 'bs-hold', 'bs-pause']) for (const r of rowOf(report, n)?.bs?.reads ?? []) parts.push({ path: r.path, parent: r.parent, kids: r.kids, arm: arm(r) });
  for (const f of rowOf(report, 'bs-facts')?.bs?.parts ?? []) if (!parts.some((p) => p.path === f.path)) parts.push({ path: f.path, parent: f.parent, kids: f.kids, arm: { frames: 0, recalcs: 0 } });
  return { full: reads(['bs-full-a', 'bs-full-b']), hidden: reads(['bs-hidden-a', 'bs-hidden-b']), parts };
}

const top = (m, n) => Object.entries(m).sort((a, b) => b[1] - a[1]).slice(0, n);

export function bisectTally(report) {
  const lines = [];
  const j = reportToJob(report);
  const r = res(j);
  lines.push(`bisect: full ${j.full.map((a) => `${a.recalcs}/${a.frames}`).join(' ')} hidden ${j.hidden.map((a) => `${a.recalcs}/${a.frames}`).join(' ')} hi ${hi(j)} lo ${lo(j)} band ${band(j)}`);
  for (const p of j.parts) lines.push(`bisect: ${cls(j, p.arm).padEnd(8)} ${String(rpf100(p.arm)).padStart(3)} ${p.arm.recalcs}/${p.arm.frames} kids ${p.kids} ${p.path}`);
  lines.push(`bisect: why ${resName(r)}`);
  lines.push(`bisect: carrier ${levelName(carrier(j))} holder ${levelName(holder(j))} pauser ${levelName(pauser(j))}`);
  const pz = rowOf(report, 'bs-pause')?.bs;
  if (pz) lines.push(`bisect: pause groups ${JSON.stringify(pz.info)} reads [path, smil-elements, svgs] ${JSON.stringify((pz.reads ?? []).map((r) => [r.path, r.sm, r.n]))}`);
  const ks = rowOf(report, 'bs-kill')?.bs;
  if (ks) lines.push(`bisect: kill smil-elements ${JSON.stringify((ks.reads ?? []).map((r) => [r.path, r.sm]))}`);
  const obs = rowOf(report, 'bs-obs');
  const fr = obs?.rs?.frames ?? [];
  const kt = obs?.rs?.kt ?? [];
  const withR = fr.filter((f) => f.r > 0);
  const count = {};
  for (const f of fr) for (const k of f.k ?? []) { const key = typeof k === 'number' ? kt[k] : k; count[key] = (count[key] ?? 0) + 1; }
  lines.push(`bisect: obs frames ${fr.length} with recalc ${withR.length} keys ${JSON.stringify(top(count, 12))}`);
  const facts = rowOf(report, 'bs-facts')?.bs;
  if (facts) {
    lines.push(`bisect: body features ${JSON.stringify(facts.body)}`);
    lines.push(`bisect: rules ${JSON.stringify(facts.rules)} observers ${JSON.stringify(facts.cn)}`);
    for (const p of facts.parts) lines.push(`bisect: feat ${p.path} ${JSON.stringify(p.feat)}`);
  }
  return lines;
}
