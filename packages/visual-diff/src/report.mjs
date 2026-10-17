// Merge the <engine>.visual.json files of one or more shard directories into a table (markdown) and report.json.
// Display only: every verdict in the files is the Lean rule's (verdict.mjs); this file counts and prints.
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const findFiles = (dir) => readdirSync(dir).flatMap((n) => {
  const p = join(dir, n);
  if (statSync(p).isDirectory()) return findFiles(p);
  return n.endsWith('.visual.json') ? [p] : [];
});

export function loadRuns(dirs) {
  const files = dirs.flatMap((d) => (existsSync(d) ? findFiles(d) : []));
  return files.map((f) => ({ file: f, ...JSON.parse(readFileSync(f, 'utf8')) }));
}

const MARK = { pass: 'P', fail: 'F', unsettled: 'U', nc: '-', error: 'E' };
const markOf = (c) => (c.status === 'compared' ? MARK[c.verdict] : MARK[c.status]);

/** Rows per engine: part -> probe -> cell, and tallies. */
export function tabulate(runs) {
  const engines = {};
  for (const r of runs) {
    const e = (engines[r.header.engine] ??= { browser: r.header.browser, parts: new Set(), probes: [], cells: new Map(), buildIds: new Set() });
    const b = r.header.site.buildId;
    e.buildIds.add(typeof b === 'string' ? b : `${b.engine} mui ${b.mui} react ${b.react}`);
    for (const pid of r.header.parts) e.parts.add(pid);
    for (const p of r.probes) {
      if (!e.probes.includes(p.id)) e.probes.push(p.id);
      for (const c of p.cells) e.cells.set(`${c.part}|${p.id}`, c);
    }
  }
  return engines;
}

export function markdown(runs) {
  const engines = tabulate(runs);
  const lines = ['P pass, F fail beyond tolerance, U unsettled (the picture moved between two shots), - absent in both arms, E error', ''];
  const json = {};
  for (const [name, e] of Object.entries(engines)) {
    const parts = [...e.parts];
    const tally = { pass: 0, fail: 0, unsettled: 0, nc: 0, error: 0 };
    for (const c of e.cells.values()) tally[c.status === 'compared' ? c.verdict : c.status]++;
    lines.push(`## ${name} (${e.browser})`, '', `cells: ${[...Object.entries(tally)].map(([k, v]) => `${k} ${v}`).join(', ')}; build ${[...e.buildIds].join(', ')}`, '');
    lines.push(`| part | ${e.probes.join(' | ')} |`, `|---|${e.probes.map(() => '---').join('|')}|`);
    for (const pid of parts) lines.push(`| ${pid} | ${e.probes.map((p) => { const c = e.cells.get(`${pid}|${p}`); return c ? markOf(c) : '?'; }).join(' | ')} |`);
    const bad = [...e.cells.values()].filter((c) => c.status === 'compared' && c.verdict === 'fail');
    const byPart = new Map();
    for (const c of bad) byPart.set(c.part, [...(byPart.get(c.part) ?? []), c]);
    lines.push('', `parts failing at some probe (${byPart.size}): ${[...byPart.keys()].join(', ') || 'none'}`, '');
    if (byPart.size > 0) {
      lines.push('| part | failing probes | worst changed ppm | worst delta | size orig | size rewrite |', '|---|---|---|---|---|---|');
      for (const [pid, cs] of byPart) {
        const w = cs.reduce((m, c) => (c.ratioPpm > m.ratioPpm ? c : m), cs[0]);
        lines.push(`| ${pid} | ${cs.length}/${e.probes.length} | ${w.ratioPpm} | ${Math.max(...cs.map((c) => c.stats.maxDelta))} | ${w.size.orig.join('x')} | ${w.size.rewrite.join('x')} |`);
      }
      lines.push('');
    }
    json[name] = { browser: e.browser, tally, failingParts: [...byPart.keys()], probes: e.probes, parts };
  }
  return { text: lines.join('\n') + '\n', json };
}

export function report(dirs, outBase) {
  const runs = loadRuns(dirs);
  if (runs.length === 0) throw new Error(`no *.visual.json under ${dirs.join(', ')}`);
  const { text, json } = markdown(runs);
  if (outBase) { writeFileSync(`${outBase}.md`, text); writeFileSync(`${outBase}.json`, JSON.stringify(json, null, 1) + '\n'); }
  return text;
}
