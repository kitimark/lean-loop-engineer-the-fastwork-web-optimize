// Per-window, per-arm continuity tables from many trajectory-probe runs (task smoothness-probe, part A). Reads only.
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { reduceRaw } from './extract.mjs';
import { HERO_NODES, MORPH_NODES } from '../trajectory/registry.mjs';
import { quantile } from './reduce.mjs';

const ARTIFACTS = [
  ['trajectory-chromium', 'chromium'],
  ['trajectory-apple', 'macos-webkit'],
  ['trajectory-playwright-webkit', 'linux-webkit'],
];

const walk = (d) => readdirSync(d).flatMap((n) => { const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : [p]; });

/** The arm label: the original, the faithful rewrite (a cand arm with no flag is a second faithful sample), or the flagged rewrite. */
export const armLabel = (role, search) => (role === 'orig' ? 'orig' : role === 'base' || !search ? 'base' : `cand:${search.replace(/^\?fw=/, '')}`);

/** One record per run, engine, width, arm, ideal and window, with the per-node numbers. */
export function summarise(runId, engine, raw) {
  const out = [];
  const groups = new Map();
  for (const r of reduceRaw(raw)) {
    const k = [r.width, armLabel(r.role, r.search), r.ideal, r.window].join('|');
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(r);
  }
  for (const [k, nodes] of groups) {
    const [width, arm, ideal, window] = k.split('|');
    const judgedNodes = nodes.filter((n) => n.pushes.some((p) => p.judged));
    if (judgedNodes.length === 0) continue;
    const npush = Math.max(...nodes.map((n) => n.pushes.length));
    const defects = [];
    const tails = [];
    for (let i = 0; i < npush; i++) {
      let d = 0;
      let t = 0;
      for (const n of nodes) {
        const p = n.pushes[i];
        if (p?.judged) { d += p.m.stalls + p.m.jumps + p.m.reversals; t += p.m.tailSteps; }
      }
      defects.push(d);
      tails.push(t);
    }
    out.push({
      run: runId, engine, width: Number(width), arm, ideal, window, hash: raw.hash, baseHash: raw.baseHash, pushes: npush,
      judgedNodes: judgedNodes.length, flaggedNodes: judgedNodes.filter((n) => n.pushes.some((p) => p.flagged)).length,
      defectsPerPush: quantile(defects, 50), tailPerPush: quantile(tails, 50),
      nodes: Object.fromEntries(judgedNodes.map((n) => {
        const j = n.pushes.filter((p) => p.judged);
        const q = (f) => quantile(j.map((p) => p.m[f]), 50);
        return [n.node, { judged: j.length, flagged: j.filter((p) => p.flagged).length, stalls: q('stalls'), jumps: q('jumps'), reversals: q('reversals'), tail: q('tailSteps'), tailT: q('tailT'), peakRatio: q('peakRatio'), top: j.find((p) => p.top)?.top }];
      })),
    });
  }
  return out;
}

/** Summaries of every run directory under `dir` (`<dir>/<runId>/<artifact>/raw-*.json`); runs with a debug or refused flag are skipped. */
export function summariseAll(dir) {
  const out = [];
  const skipped = [];
  for (const id of readdirSync(dir).filter((n) => /^\d+$/.test(n)).sort()) {
    for (const [artifact, engine] of ARTIFACTS) {
      const ad = join(dir, id, artifact);
      if (!existsSync(ad)) continue;
      for (const f of walk(ad).filter((p) => /raw-.*\.json$/.test(p))) {
        const raw = JSON.parse(readFileSync(f, 'utf8'));
        if (raw.debug || raw.refused) { skipped.push({ run: id, engine, why: raw.refused ? 'refused' : `debug=${raw.debug}` }); continue; }
        out.push(...summarise(id, engine, raw));
      }
    }
  }
  return { records: out, skipped };
}

const med = (xs) => quantile(xs, 50);

const range = (xs) => [Math.min(...xs), Math.max(...xs)];
const defectsOf = (n) => n.stalls + n.jumps + n.reversals;

/** The part (anchors.json part) of each node id, for the table labels. */
const PART = new Map([...HERO_NODES, ...MORPH_NODES].map((n) => [n.id, n.part]));

/**
 * Per engine, width, window, ideal and arm: the numbers over runs (median of per-run medians, range, run ids), and for every node
 * (property) of the window the same per node: how many runs moved it, its stalls, jumps, reversals, defects (their sum), late tail
 * steps and peak ratio as a median over runs with the run ids and the range.
 */
export function byArm(records) {
  const g = new Map();
  for (const r of records) {
    const k = [r.engine, r.width, r.window, r.ideal, r.arm].join('|');
    if (!g.has(k)) g.set(k, []);
    g.get(k).push(r);
  }
  return [...g.entries()].map(([k, rs]) => {
    const [engine, width, window, ideal, arm] = k.split('|');
    const rng = (f) => range(rs.map((r) => r[f]));
    const ids = [...new Set(rs.flatMap((r) => Object.keys(r.nodes)))];
    const nodes = Object.fromEntries(ids.map((id) => {
      const has = rs.filter((r) => r.nodes[id]);
      const vals = has.map((r) => ({ run: r.run, ...r.nodes[id], defects: defectsOf(r.nodes[id]) }));
      const m = (f) => med(vals.map((v) => v[f]));
      return [id, { part: PART.get(id) ?? null, runs: has.map((r) => r.run), moved: has.length, ofRuns: rs.length, flagged: m('flagged'), stalls: m('stalls'), jumps: m('jumps'), reversals: m('reversals'),
        defects: m('defects'), defectsRange: range(vals.map((v) => v.defects)), tail: m('tail'), tailRange: range(vals.map((v) => v.tail)), peakRatio: m('peakRatio'), peakRatioRange: range(vals.map((v) => v.peakRatio)) }];
    }));
    return { engine, width: Number(width), window, ideal, arm, runs: rs.length, runIds: rs.map((r) => r.run), judgedNodes: med(rs.map((r) => r.judgedNodes)),
      flaggedNodes: med(rs.map((r) => r.flaggedNodes)), flaggedNodesRange: rng('flaggedNodes'), defectsPerPush: med(rs.map((r) => r.defectsPerPush)),
      defectsRange: rng('defectsPerPush'), tailPerPush: med(rs.map((r) => r.tailPerPush)), tailRange: rng('tailPerPush'), nodes };
  }).sort((a, b) => (a.engine + a.width + a.window + a.ideal).localeCompare(b.engine + b.width + b.window + b.ideal) || a.arm.localeCompare(b.arm));
}

const rg = (v, [lo, hi]) => (lo === hi ? `${v}` : `${v} (${lo}-${hi})`);
const cellKey = (r) => [r.engine, r.width, r.window, r.ideal].join('|');
const head = (k) => { const [e, w, win, id] = k.split('|'); return `${e} ${w}px, ${win}, ideal ${id}`; };

/** Cells of one (engine, width, window, ideal) block: the rows of its arms by node. */
function blocks(rows) {
  const b = new Map();
  for (const r of rows) {
    if (!b.has(cellKey(r))) b.set(cellKey(r), []);
    b.get(cellKey(r)).push(r);
  }
  return b;
}

/**
 * Where two arms differ in one block: per node and per measure (defects, late tail steps), the arm's median is outside the other arm's
 * run-to-run range (min-max of per-run medians). A cell with a node that moved in one arm and not in the other is listed as `moved`.
 * A TS stand-in (descriptive: it picks cells to read, it does not decide anything).
 */
export function differences(rows, armA, armsB) {
  const out = [];
  for (const [k, rs] of blocks(rows)) {
    const a = rs.find((r) => r.arm === armA);
    if (!a) continue;
    for (const r of rs.filter((x) => armsB(x.arm))) {
      for (const id of new Set([...Object.keys(a.nodes), ...Object.keys(r.nodes)])) {
        const na = a.nodes[id];
        const nb = r.nodes[id];
        if (!na || !nb) { out.push({ block: k, node: id, measure: 'moved', ref: na ? `${na.moved}/${na.ofRuns} runs` : 'not moving', arm: r.arm, val: nb ? `${nb.moved}/${nb.ofRuns} runs` : 'not moving', dir: na ? 'arm not moving' : 'arm moving', refRuns: a.runIds, armRuns: r.runIds }); continue; }
        for (const [m, rf] of [['defects', 'defectsRange'], ['tail', 'tailRange']]) {
          const [lo, hi] = na[rf];
          if (nb[m] < lo || nb[m] > hi) out.push({ block: k, node: id, measure: m, ref: rg(na[m], na[rf]), arm: r.arm, val: `${nb[m]}`, dir: nb[m] > hi ? 'higher' : 'lower', refRuns: a.runIds, armRuns: r.runIds });
        }
      }
    }
  }
  return out;
}

/** The table as markdown: run index, the cells where arms differ, then one block per engine, width, window and ideal with a row per node and arm. */
export function markdown(rows) {
  const lines = [];
  const all = [...new Set(rows.flatMap((r) => r.runIds))].sort();
  const code = new Map(all.map((id, i) => [id, `R${i + 1}`]));
  const codes = (ids) => (ids.length > 6 ? `${ids.length} runs (see Runs per arm)` : ids.map((id) => code.get(id)).join(','));
  lines.push('Runs are cited by code; the index is at the end. Per node (property): the median over runs of the per-run median over pushes, with the min-max of the per-run medians in brackets. `defects` = stalls + jumps + reversals; `tail` = late tail steps; `peak` = peak shown step over peak ideal step (1000 = equal). Measured values, not thresholds.', '');
  const dOrigBase = differences(rows, 'orig', (a) => a === 'base');
  lines.push('### Cells where the faithful rewrite (base) differs from the original beyond the original\'s run-to-run range', '');
  lines.push('| engine, width, window, ideal | property | measure | orig (range) | base | direction | orig runs | base runs |', '| --- | --- | --- | --- | --- | --- | --- | --- |');
  for (const d of dOrigBase) lines.push(`| ${head(d.block)} | ${d.node} | ${d.measure} | ${d.ref} | ${d.val} | ${d.dir} | ${codes(d.refRuns)} | ${codes(d.armRuns)} |`);
  if (dOrigBase.length === 0) lines.push('| none | | | | | | | |');
  lines.push('', '### Cells where a flagged rewrite differs from the faithful rewrite (base) beyond base\'s run-to-run range', '');
  lines.push('| engine, width, window, ideal | property | measure | base (range) | arm | arm value | direction | arm runs |', '| --- | --- | --- | --- | --- | --- | --- | --- |');
  const dFlags = differences(rows, 'base', (a) => a.startsWith('cand:'));
  for (const d of dFlags) lines.push(`| ${head(d.block)} | ${d.node} | ${d.measure} | ${d.ref} | ${d.arm} | ${d.val} | ${d.dir} | ${codes(d.armRuns)} |`);
  if (dFlags.length === 0) lines.push('| none | | | | | | | |');
  lines.push('', '### Per window, property and arm', '');
  for (const [k, rs] of blocks(rows)) {
    lines.push(`**${head(k)}**`, '', '| property | part | arm | runs moved / runs | defects | stalls | jumps | reversals | tail | peak | run codes |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    const ids = [...new Set(rs.flatMap((r) => Object.keys(r.nodes)))];
    for (const id of ids) for (const r of rs) {
      const n = r.nodes[id];
      if (!n) { lines.push(`| ${id} | ${PART.get(id) ?? ''} | ${r.arm} | 0 / ${r.runs} | - | - | - | - | - | - | |`); continue; }
      lines.push(`| ${id} | ${n.part ?? ''} | ${r.arm} | ${n.moved} / ${n.ofRuns} | ${rg(n.defects, n.defectsRange)} | ${n.stalls} | ${n.jumps} | ${n.reversals} | ${rg(n.tail, n.tailRange)} | ${rg(n.peakRatio, n.peakRatioRange)} | ${codes(n.runs)} |`);
    }
    lines.push('');
  }
  lines.push('### Window totals per arm (all properties of the window summed per push)', '', '| engine, width, window, ideal | arm | runs | nodes moving | nodes flagged | defects per push | tail steps per push |', '| --- | --- | --- | --- | --- | --- | --- |');
  for (const r of rows) lines.push(`| ${head(cellKey(r))} | ${r.arm} | ${r.runs} | ${r.judgedNodes} | ${rg(r.flaggedNodes, r.flaggedNodesRange)} | ${rg(r.defectsPerPush, r.defectsRange)} | ${rg(r.tailPerPush, r.tailRange)} |`);
  lines.push('', '### Runs per arm (every run behind the counts above)', '', '| engine, width, window, ideal | arm | run codes |', '| --- | --- | --- |');
  for (const r of rows) lines.push(`| ${head(cellKey(r))} | ${r.arm} | ${r.runIds.map((id) => code.get(id)).join(',')} |`);
  lines.push('', '### Run index', '', all.map((id) => `${code.get(id)} = ${id}`).join('; '));
  return lines.join('\n');
}
