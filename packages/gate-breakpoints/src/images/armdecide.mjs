// Reads the result files of the drawn-size arm (armv2.mjs, schema fw.images.arm2/1; one per engine, shard and rep) and sets them
// down as tables: the decision of each part per policy and engine (armplan.partDecision, the twin of ImageArm.partDecision, each
// cell on its own), the cells behind it with their counts, and the decoded-memory saving of the admissible parts. Nothing is
// measured or decided here.
//   node src/images/cli.mjs arm decide --in DIR[,DIR...] [--out FILE.md]
import { readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { partDecision } from './armplan.mjs';

const walk = (d) => readdirSync(d).flatMap((n) => {
  const p = join(d, n);
  return statSync(p).isDirectory() ? walk(p) : /^arm-.*\.json$/.test(n) ? [p] : [];
});

/** Load the result files under `dirs` (a file path is taken as it is). */
export function loadResults(dirs) {
  const files = dirs.flatMap((d) => (statSync(d).isDirectory() ? walk(d) : [d]));
  return files.map((f) => ({ path: f, ...JSON.parse(readFileSync(f, 'utf8')) })).filter((j) => j.schema === 'fw.images.arm2/1');
}

const word = (c) => c?.v ?? 'error';

/**
 * Decisions: for each (policy, engine, part) the cells of every probe and rep, decided one by one.
 * Returns [{ policy, engine, part, decision, cells: n, copies: n (cells with at least one copy) }].
 * A part none of whose cells has a copy is `noCopy` (nothing was drawn differently, so nothing was decided).
 */
export function decide(results) {
  const by = new Map();
  for (const r of results) {
    for (const row of r.rows) {
      if (row.error) continue;
      const cell = { base: word(row.base), drawn: word(row.drawn), files: row.files, probe: row.probe, ppm: row.drawn?.ppm ?? null, rep: r.tag };
      // per engine, and over both engines (engine `all`): every cell is decided on its own
      for (const e of [r.engine, 'all']) {
        const k = `${row.policy}|${e}|${row.part}`;
        (by.get(k) ?? by.set(k, []).get(k)).push(cell);
      }
    }
  }
  const out = [];
  for (const [k, cells] of [...by].sort(([a], [b]) => a.localeCompare(b))) {
    const [policy, engine, part] = k.split('|');
    const withCopy = cells.filter((c) => c.files > 0);
    out.push({ policy, engine, part, decision: withCopy.length === 0 ? 'noCopy' : partDecision(withCopy), cells: withCopy.length, copies: cells.length, worst: Math.max(-1, ...withCopy.map((c) => c.ppm ?? -1)) });
  }
  return out;
}

const kib = (n) => `${(n / 1024).toFixed(1)}`;

export function tablesMd(results) {
  const L = [];
  const runs = results.map((r) => `${r.engine} ${r.tag} (${r.browser ?? '?'}${r.truncated ? ', TRUNCATED' : ''})`);
  L.push(`### Runs`, '', ...runs.map((x) => `- ${x}`), '');
  const dec = decide(results);
  const engines = [...new Set(dec.map((d) => d.engine))].filter((e) => e !== 'all').sort();
  const parts = [...new Set(dec.map((d) => d.part))];
  for (const policy of [...new Set(dec.map((d) => d.policy))]) {
    L.push(`### Decision per part, policy ${policy}`, '', `| part | ${engines.map((e) => `${e} (cells, worst ppm)`).join(' | ')} | both |`, `|---|${engines.map(() => '---|').join('')}---|`);
    for (const part of parts) {
      const ds = engines.map((e) => dec.find((d) => d.policy === policy && d.engine === e && d.part === part));
      const cell = (d) => (d ? `${d.decision} (${d.cells}, ${d.worst})` : '-');
      const both = dec.find((d) => d.policy === policy && d.engine === 'all' && d.part === part)?.decision ?? '-';
      L.push(`| ${part} | ${ds.map(cell).join(' | ')} | ${both} |`);
    }
    L.push('');
  }
  // the cells behind the decisions
  L.push('### Cells (probe, base verdict, drawn verdict, ppm of the drawn run, files with a copy, decoded saving KiB)', '', '| policy | engine | probe | width@dpr | part | rep | base | drawn | drawn ppm / delta | files | saving KiB |', '|---|---|---|---|---|---|---|---|---|---|---|');
  for (const r of results) {
    for (const row of r.rows) {
      if (row.error || row.files === 0) continue;
      L.push(`| ${row.policy} | ${r.engine} | ${row.probe} | ${row.width}@${row.dpr} | ${row.part} | ${r.tag} | ${word(row.base)} ${row.base?.ppm ?? ''} | **${word(row.drawn)}** | ${row.drawn?.ppm ?? '-'} / ${row.drawn?.delta ?? '-'} | ${row.files} | ${kib(row.saving)} |`);
    }
  }
  L.push('');
  // why files have no exact copy, counted over the first result of each engine
  const first = engines.map((e) => results.find((r) => r.engine === e)).filter(Boolean);
  L.push('### Why a file has no exact copy (files per probe, first run of each engine)', '', '| engine | probe | ok | notImg | cropped | scaled | fractional | noSaving | disagree | other |', '|---|---|---|---|---|---|---|---|---|---|');
  for (const r of first) {
    for (const probe of r.probes) {
      const fs = r.files.filter((f) => f.probe === probe);
      if (fs.length === 0) continue;
      const n = (w) => fs.filter((f) => f.why === w).length;
      const known = ['ok', 'notImg', 'cropped', 'scaled', 'fractional', 'noSaving', 'disagree'];
      L.push(`| ${r.engine} | ${probe} | ${known.map(n).join(' | ')} | ${fs.filter((f) => !known.includes(f.why)).length} |`);
    }
  }
  L.push('');
  return L.join('\n');
}

export async function decideCli(_args, { arg, list }) {
  const results = loadResults(list(arg('in')).map((d) => resolve(d)));
  if (results.length === 0) throw new Error(`no arm result files in ${arg('in')}`);
  const md = tablesMd(results);
  if (arg('out')) writeFileSync(resolve(arg('out')), md + '\n');
  console.log(md);
}
