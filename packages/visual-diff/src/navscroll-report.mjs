// Merge the <engine>.navscroll.json files of a run into tables (markdown) and a summary JSON. Display and counting only:
// every number comes from the records; the comparison functions are navscroll-analyze.mjs.
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { compareSweeps, compareTransitionFrames, describeTransition, eventSequence, lagSummary, pathError, transitions, wheelEdges } from './navscroll-analyze.mjs';

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
  const frameCmp = {};
  for (const t of o.transitions) {
    const z = p.transitions.find((x) => x.key === t.key);
    if (z) frameCmp[t.key] = { ...compareTransitionFrames(t, z), seq: { orig: eventSequence(t), port: eventSequence(z) } };
    else frameCmp[t.key] = null;
  }
  return {
    id: c.id, width: c.width, height: c.height,
    geo: { orig: pickGeo(o.geo), rewrite: pickGeo(p.geo) },
    ready: { orig: o.ready, rewrite: p.ready },
    edges: { down: { orig: edges(o.sweepDown), rewrite: edges(p.sweepDown) }, up: { orig: edges(o.sweepUp), rewrite: edges(p.sweepUp) } },
    sweep: { down: compareSweeps(o.sweepDown, p.sweepDown), up: compareSweeps(o.sweepUp, p.sweepUp) },
    settled: { ...settled, equalStates: settled.diff.hidden.length + settled.diff.cls.length + settled.diff.vis.length === 0, maxPosDelta: +settledPos.toFixed(2) },
    settledDiffs: settledDiffs(o.settled, p.settled),
    transitions: trans,
    frameCmp,
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
    L.push(`## ${eng} (${r.header.browser}), run ${runLabel(r.file)}`, '', `build ${typeof b === 'string' ? b : JSON.stringify(b)}; step ${r.header.params.STEP} px, ${r.header.params.FRAMES} frames per step`, '');
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
    L.push('', '### Transition frames, arm against arm (frame 0 = sample at the jump; flip = class change visible; move = translateY changed; start = transform start time; lag = move - flip)', '', '| width | edge | flip o/p | move o/p | lag o/p | start o/p | translateY of the first 6 frames, orig | port | curve diff from own first move (px) | event order o / p |', '|---|---|---|---|---|---|---|---|---|---|');
    for (const s of ok) {
      for (const [key, c] of Object.entries(s.frameCmp)) {
        if (!c) { L.push(`| ${s.id} | ${key} | edge captured in one arm only | | | | | | | |`); continue; }
        const pr = (x) => `${x.orig}/${x.port}`;
        L.push(`| ${s.id} | ${key} | ${pr(c.flip)} | ${pr(c.move)} | ${pr(c.lag)} | ${c.start.orig ?? '-'}/${c.start.port ?? '-'} | ${c.ty.orig.slice(0, 6).join(' ')} | ${c.ty.port.slice(0, 6).join(' ')} | ${c.aligned ?? '-'} | ${c.seq.orig ?? '-'} / ${c.seq.port ?? '-'} |`);
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

/** Live u of each hidden-state edge of a sweep, in order: [{ to, u }]. */
const edgeList = (sweep) => transitions(sweep).map((t) => ({ to: t.to, u: t.u }));

/** Port minus original live u per edge of a sweep ("n/a" when the arms found different numbers of edges). */
export function edgeDeltas(a, b) {
  const x = edgeList(a), y = edgeList(b);
  if (x.length !== y.length || x.some((e, i) => e.to !== y[i].to)) return `edges ${x.length} vs ${y.length}`;
  return x.map((e, i) => `${e.to ? 'on' : 'off'} ${(y[i].u - e.u) >= 0 ? '+' : ''}${(y[i].u - e.u).toFixed(2)}`).join(', ') || 'none';
}

/** Largest |port - orig| of the four wheel edges (px), or null when an edge is missing in one arm. */
export function wheelDelta(w) {
  if (!w.orig || !w.rewrite) return null;
  let m = 0;
  for (const k of ['downOn', 'downOff', 'upOn', 'upOff']) {
    if (w.orig[k] == null || w.rewrite[k] == null) return null;
    m = Math.max(m, Math.abs(w.rewrite[k] - w.orig[k]));
  }
  return m;
}

/**
 * One row per run, engine and width, every completed run given: the number of steps whose hidden flag differs (down/up), the
 * live-u difference of each edge, the held positions whose end state differs, the largest wheel edge difference, whether the
 * animation lists of the captured edges are equal between the arms, and the edges that were not captured in an arm.
 */
export function perRunRows(runs) {
  const rows = [];
  for (const r of runs) {
    for (const c of r.cases) {
      if (c.orig.error || c.rewrite.error || c.orig.absent || c.rewrite.absent) continue;
      const s = summarizeCase(c);
      const misses = [];
      let animsDiffer = 0;
      for (const [key, arms] of Object.entries(s.transitions)) {
        if (!arms.orig || !arms.rewrite) { misses.push(`${key} (${arms.orig ? 'port' : 'orig'} arm not captured)`); continue; }
        if (arms.orig.classFlipFrame < 0 || arms.rewrite.classFlipFrame < 0) { misses.push(`${key} (${arms.orig.classFlipFrame < 0 ? 'orig' : 'port'} arm never flips in the record)`); continue; }
        if (arms.orig.anims.join('|') !== arms.rewrite.anims.join('|')) animsDiffer++;
      }
      rows.push({
        run: runLabel(r.file), engine: r.header.engine, id: s.id,
        hiddenDiff: `${s.sweep.down.diff.hidden.length}/${s.sweep.up.diff.hidden.length}`,
        edgesDown: edgeDeltas(c.orig.sweepDown, c.rewrite.sweepDown), edgesUp: edgeDeltas(c.orig.sweepUp, c.rewrite.sweepUp),
        held: s.settledDiffs.map((d) => `u${d.uw} orig ${d.orig} | port ${d.rewrite}`),
        wheel: wheelDelta(s.wheel), animsDiffer, misses,
      });
    }
  }
  return rows;
}

export function perRunMarkdown(runs) {
  const rows = perRunRows(runs);
  const L = ['## Every run, every width (port minus original)', '',
    '| engine | run | width | hidden steps differ (down/up) | down edges, live u | up edges, live u | wheel max edge diff px | captured edges with other animations | captured-edge misses | held end states that differ |', '|---|---|---|---|---|---|---|---|---|---|'];
  for (const x of rows) L.push(`| ${x.engine} | ${x.run} | ${x.id} | ${x.hiddenDiff} | ${x.edgesDown} | ${x.edgesUp} | ${x.wheel ?? 'edge missing'} | ${x.animsDiffer} | ${x.misses.join('; ') || 'none'} | ${x.held.join('; ') || 'none'} |`);
  return { text: L.join('\n'), rows };
}

/** The run id of an artifact path (the digits of the run directory), or the file name. */
export const runLabel = (file) => /(\d{8,})/.exec(file)?.[1] ?? file;

/** Pooled lag table over every run given: how often the port's start lag is longer / shorter / equal on the same edge. */
export function pooledLag(runs) {
  const rows = [];
  for (const r of runs) {
    for (const c of r.cases) {
      if (c.orig.error || c.rewrite.error || c.orig.absent || c.rewrite.absent) continue;
      const s = summarizeCase(c);
      for (const [key, f] of Object.entries(s.frameCmp)) if (f) rows.push({ run: runLabel(r.file), engine: r.header.engine, id: c.id, key, orig: f.lag.orig, port: f.lag.port });
    }
  }
  const groups = lagSummary(rows);
  const L = ['## Transform start lag pooled over runs (frames from the class flip to the first translateY change; one value per run)', '',
    `runs: ${[...new Set(rows.map((x) => x.run))].join(', ')}`, '',
    '| engine | width | edge | orig lags | port lags | port longer | shorter | equal |', '|---|---|---|---|---|---|---|---|'];
  for (const g of groups) L.push(`| ${g.engine} | ${g.id} | ${g.key} | ${g.orig.join(' ')} | ${g.port.join(' ')} | ${g.longer} | ${g.shorter} | ${g.equal} |`);
  const sum = (eng, k) => groups.filter((g) => g.engine === eng).reduce((a, g) => a + g[k], 0);
  for (const eng of [...new Set(groups.map((g) => g.engine))]) L.push('', `${eng}: port longer ${sum(eng, 'longer')}, shorter ${sum(eng, 'shorter')}, equal ${sum(eng, 'equal')}`);
  return { text: L.join('\n'), groups };
}

export function report(dirs, outBase) {
  const runs = loadRuns(dirs);
  const { text, json } = markdown(runs);
  const pooled = pooledLag(runs);
  const perRun = perRunMarkdown(runs);
  if (outBase) {
    writeFileSync(`${outBase}.md`, perRun.text + '\n\n' + text + '\n\n' + pooled.text + '\n');
    writeFileSync(`${outBase}.json`, JSON.stringify({ ...json, perRun: perRun.rows, pooledLag: pooled.groups }, null, 1) + '\n');
  }
  return perRun.text + '\n\n' + text + '\n\n' + pooled.text + '\n';
}
