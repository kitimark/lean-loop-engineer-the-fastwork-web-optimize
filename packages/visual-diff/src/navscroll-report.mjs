// Merge the <engine>.navscroll.json files of a run into tables (markdown) and a summary JSON. Display and counting only:
// every number comes from the records; the comparison functions are navscroll-analyze.mjs.
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { compareSweeps, describeTransition, pathError, transitions, wheelEdges } from './navscroll-analyze.mjs';

const findFiles = (dir) => readdirSync(dir).flatMap((n) => {
  const p = join(dir, n);
  if (statSync(p).isDirectory()) return findFiles(p);
  return n.endsWith('.navscroll.json') ? [p] : [];
});

export const loadRuns = (dirs) => dirs.flatMap((d) => (existsSync(d) ? findFiles(d) : [])).map((f) => ({ file: f, ...JSON.parse(readFileSync(f, 'utf8')) }));

const edges = (sweep) => transitions(sweep).map((t) => `${t.to ? 'on' : 'off'} ${t.uBefore}->${t.u}`).join('; ') || 'never hidden';

const pickGeo = (g) => ({ vh: g.vh, secTop: Math.round(g.secTop), secH: Math.round(g.secH), stickyPosition: g.stickyPosition, stickyCssTop: g.stickyCssTop, stickyH: Math.round(g.stickyH) });

/** The shown and the hidden end state of a transition record, and its path error against the browser's own easing. */
function transitionOf(t) {
  const last = t.frames[t.frames.length - 1];
  const shown = t.to ? t.before : last;
  const hidden = t.to ? last : t.before;
  const [from, to] = t.to ? [shown, hidden] : [hidden, shown];
  return { ...describeTransition(t), u: t.u, uBefore: t.uBefore, path: pathError(t.frames, t.anims, { ty: from.ty, op: from.op }, { ty: to.ty, op: to.op }) };
}

const series = (r) => [...(r.early ?? []).map((e) => `${e.t}ms ${e.hidden ? 'H' : 'V'}`), `end ${r.hidden ? 'H' : 'V'}`].join(', ');

/** The held positions where the arms' hidden flag differs at the end, with the flag after 50, 250, 500 ms and at the end (H hidden, V visible). */
export function settledDiffs(orig, rewrite) {
  const byUw = new Map(rewrite.map((r) => [r.uw, r]));
  const out = [];
  for (const o of orig) {
    const p = byUw.get(o.uw);
    if (p && o.hidden !== p.hidden) out.push({ uw: o.uw, u: { orig: o.u, rewrite: p.u }, orig: series(o), rewrite: series(p) });
  }
  return out;
}

/** One width of one engine: the numbers of every table. */
export function summarizeCase(c) {
  if (c.orig.error || c.rewrite.error) return { id: c.id, error: { orig: c.orig.error ?? null, rewrite: c.rewrite.error ?? null } };
  if (c.orig.absent || c.rewrite.absent) return { id: c.id, absent: { orig: !!c.orig.absent, rewrite: !!c.rewrite.absent } };
  const o = c.orig, p = c.rewrite;
  const settled = compareSweeps(o.settled, p.settled);
  const byUw = new Map(p.settled.map((r) => [r.uw, r]));
  let settledPos = 0;
  for (const x of o.settled) {
    const z = byUw.get(x.uw);
    if (z) settledPos = Math.max(settledPos, Math.abs(x.ty - z.ty), Math.abs(x.top - z.top));
  }
  const trans = {};
  for (const arm of [o, p]) for (const t of arm.transitions) (trans[t.key] ??= {})[arm.site] = transitionOf(t);
  return {
    id: c.id, width: c.width, height: c.height,
    geo: { orig: pickGeo(o.geo), rewrite: pickGeo(p.geo) },
    ready: { orig: o.ready, rewrite: p.ready },
    edges: { down: { orig: edges(o.sweepDown), rewrite: edges(p.sweepDown) }, up: { orig: edges(o.sweepUp), rewrite: edges(p.sweepUp) } },
    sweep: { down: compareSweeps(o.sweepDown, p.sweepDown), up: compareSweeps(o.sweepUp, p.sweepUp) },
    settled: { ...settled, equalStates: settled.diff.hidden.length + settled.diff.cls.length + settled.diff.vis.length === 0, maxPosDelta: +settledPos.toFixed(2) },
    settledDiffs: settledDiffs(o.settled, p.settled),
    transitions: trans,
    wheel: { orig: o.wheel ? wheelEdges(o.wheel) : null, rewrite: p.wheel ? wheelEdges(p.wheel) : null },
  };
}

const first = (list) => (list.length ? `${list.length} (first u=${list[0].uw})` : '0');

export function markdown(runs) {
  const L = [];
  const json = {};
  for (const r of runs) {
    const eng = r.header.engine;
    const b = r.header.site.buildId;
    L.push(`## ${eng} (${r.header.browser})`, '', `build ${typeof b === 'string' ? b : JSON.stringify(b)}; step ${r.header.params.STEP} px, ${r.header.params.FRAMES} frames per step`, '');
    const sums = r.cases.map(summarizeCase);
    json[eng] = sums;
    const ok = sums.filter((s) => !s.error && !s.absent);
    for (const s of sums) if (s.error || s.absent) L.push(`${s.id}: ${JSON.stringify(s.error ?? s.absent)}`, '');
    L.push('### Hidden state through the section (sweep, one record per frame)', '', '| width | arm | sticky | section top/height | down edges (u before->at) | up edges |', '|---|---|---|---|---|---|');
    for (const s of ok) {
      for (const arm of ['orig', 'rewrite']) {
        const g = s.geo[arm];
        L.push(`| ${s.id} | ${arm} | ${g.stickyPosition} top ${g.stickyCssTop} | ${g.secTop}/${g.secH} | ${s.edges.down[arm]} | ${s.edges.up[arm]} |`);
      }
    }
    L.push('', '### Per-step difference (orig vs rewrite, same u grid)', '', '| width | steps | hidden differs down | class list differs down | hidden differs up | class list differs up | max sticky top delta px | max nav top delta px | settled states differ | settled max position delta px |', '|---|---|---|---|---|---|---|---|---|---|');
    for (const s of ok) {
      L.push(`| ${s.id} | ${s.sweep.down.matched} | ${first(s.sweep.down.diff.hidden)} | ${first(s.sweep.down.diff.cls)} | ${first(s.sweep.up.diff.hidden)} | ${first(s.sweep.up.diff.cls)} | ${Math.max(s.sweep.down.maxStickyTopDelta, s.sweep.up.maxStickyTopDelta)} | ${Math.max(s.sweep.down.maxNavTopDelta, s.sweep.up.maxNavTopDelta)} | ${s.settled.equalStates ? 'no' : first(s.settled.diff.hidden)} | ${s.settled.maxPosDelta} |`);
    }
    L.push('', '### Held positions whose hidden flag differs at the end (H hidden, V visible; live u in brackets)', '', '| width | u asked | orig | rewrite |', '|---|---|---|---|');
    for (const s of ok) for (const d of s.settledDiffs) L.push(`| ${s.id} | ${d.uw} | [${d.u.orig}] ${d.orig} | [${d.u.rewrite}] ${d.rewrite} |`);
    L.push('', '### Transition (native rAF; elapsed from the animation start time; error against the browser-reported easing)', '', '| width | event | arm | animations | frames | end hidden / ty / op / vis | transform max err px | opacity max err |', '|---|---|---|---|---|---|---|---|');
    for (const s of ok) {
      for (const [key, arms] of Object.entries(s.transitions)) {
        for (const arm of ['orig', 'rewrite']) {
          const t = arms[arm];
          if (!t) { L.push(`| ${s.id} | ${key} | ${arm} | none | | | | |`); continue; }
          L.push(`| ${s.id} | ${key} | ${arm} | ${t.anims.join('; ')} | ${t.frames} | ${t.end.hidden} / ${t.end.ty} / ${t.end.op} / ${t.end.vis} | ${t.path.transform?.maxErr ?? '-'} | ${t.path.opacity?.maxErr ?? '-'} |`);
        }
      }
    }
    L.push('', '### Real wheel events (100 px / 60 ms; u of the first hidden / first visible frame)', '', '| width | arm | down on | down off | up on | up off | peak u |', '|---|---|---|---|---|---|---|');
    for (const s of ok) {
      for (const arm of ['orig', 'rewrite']) {
        const w = s.wheel[arm];
        if (w) L.push(`| ${s.id} | ${arm} | ${w.downOn} | ${w.downOff} | ${w.upOn} | ${w.upOff} | ${w.peakU} |`);
      }
    }
    L.push('');
  }
  return { text: L.join('\n'), json };
}

export function report(dirs, outBase) {
  const { text, json } = markdown(loadRuns(dirs));
  if (outBase) {
    writeFileSync(`${outBase}.md`, text + '\n');
    writeFileSync(`${outBase}.json`, JSON.stringify(json, null, 1) + '\n');
  }
  return text + '\n';
}
