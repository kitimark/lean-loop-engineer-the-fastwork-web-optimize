// Per-window, per-arm continuity tables from many trajectory-probe runs (task smoothness-probe, part A). Reads only.
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { reduceRaw } from './extract.mjs';
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

/** Per engine, width, window, ideal and arm: the numbers over runs (median of per-run medians, range, run ids). */
export function byArm(records) {
  const g = new Map();
  for (const r of records) {
    const k = [r.engine, r.width, r.window, r.ideal, r.arm].join('|');
    if (!g.has(k)) g.set(k, []);
    g.get(k).push(r);
  }
  return [...g.entries()].map(([k, rs]) => {
    const [engine, width, window, ideal, arm] = k.split('|');
    const rng = (f) => [Math.min(...rs.map((r) => r[f])), Math.max(...rs.map((r) => r[f]))];
    return { engine, width: Number(width), window, ideal, arm, runs: rs.length, runIds: rs.map((r) => r.run), judgedNodes: med(rs.map((r) => r.judgedNodes)),
      flaggedNodes: med(rs.map((r) => r.flaggedNodes)), flaggedNodesRange: rng('flaggedNodes'), defectsPerPush: med(rs.map((r) => r.defectsPerPush)),
      defectsRange: rng('defectsPerPush'), tailPerPush: med(rs.map((r) => r.tailPerPush)), tailRange: rng('tailPerPush') };
  }).sort((a, b) => (a.engine + a.width + a.window + a.ideal).localeCompare(b.engine + b.width + b.window + b.ideal) || a.arm.localeCompare(b.arm));
}

/** The table as markdown, one block per engine and width. */
export function markdown(rows) {
  const lines = [];
  let head = '';
  for (const r of rows) {
    const h = `${r.engine} ${r.width}px, ${r.window}, ideal ${r.ideal}`;
    if (h !== head) {
      head = h;
      lines.push('', `**${h}**`, '', '| arm | runs | nodes moving | nodes flagged | defects per push | tail steps per push |', '| --- | --- | --- | --- | --- | --- |');
    }
    const rg = (v, [lo, hi]) => (lo === hi ? `${v}` : `${v} (${lo}-${hi})`);
    lines.push(`| ${r.arm} | ${r.runs} | ${r.judgedNodes} | ${rg(r.flaggedNodes, r.flaggedNodesRange)} | ${rg(r.defectsPerPush, r.defectsRange)} | ${rg(r.tailPerPush, r.tailRange)} |`);
  }
  return lines.join('\n');
}
