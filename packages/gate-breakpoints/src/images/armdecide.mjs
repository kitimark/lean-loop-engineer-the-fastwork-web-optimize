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

export function tablesMd(results, opts = {}) {
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
  // what the cells did: base verdict -> drawn verdict, counted per (policy, engine, part)
  const cls = (c) => `${c.base === 'pass' ? 'pass' : c.base === 'fail' ? 'fail' : 'open'}>${c.drawn === 'pass' ? 'pass' : c.drawn === 'fail' ? 'fail' : 'open'}`;
  const COLS = ['pass>pass', 'pass>fail', 'fail>pass', 'fail>fail', 'pass>open', 'fail>open', 'open>pass', 'open>fail', 'open>open'];
  const rowsAll = results.flatMap((r) => r.rows.filter((x) => !x.error && x.files > 0).map((x) => ({ ...x, engine: r.engine, rep: r.tag.replace(/-s\d+$/, '') })));
  const groups = new Map();
  for (const x of rowsAll) (groups.get(`${x.policy}|${x.engine}|${x.part}`) ?? groups.set(`${x.policy}|${x.engine}|${x.part}`, []).get(`${x.policy}|${x.engine}|${x.part}`)).push(x);
  L.push('### What the cells did (base verdict > drawn verdict; open = unsettled, invalid, nc or error)', '', `| policy | engine | part | cells | ${COLS.join(' | ')} | mean saving KiB per cell |`, `|---|---|---|---|${COLS.map(() => '---|').join('')}---|`);
  for (const [k, xs] of [...groups].sort(([a1], [b1]) => a1.localeCompare(b1))) {
    const [policy, engine, part] = k.split('|');
    const n = (c) => xs.filter((x) => cls({ base: word(x.base), drawn: word(x.drawn) }) === c).length;
    L.push(`| ${policy} | ${engine} | ${part} | ${xs.length} | ${COLS.map(n).join(' | ')} | ${kib(xs.reduce((t, x) => t + x.saving, 0) / xs.length)} |`);
  }
  L.push('');
  // the cells that would change the look: drawn fails where the baseline passes, with how many reps did it
  L.push('### Cells where the copy fails and the baseline passes (reps with that / reps with a copy)', '', '| policy | engine | probe | width@dpr | part | reps | drawn ppm / delta per rep | files |', '|---|---|---|---|---|---|---|---|');
  const byCell = new Map();
  for (const x of rowsAll) (byCell.get(`${x.policy}|${x.engine}|${x.probe}|${x.part}`) ?? byCell.set(`${x.policy}|${x.engine}|${x.probe}|${x.part}`, []).get(`${x.policy}|${x.engine}|${x.probe}|${x.part}`)).push(x);
  for (const [k, xs] of [...byCell].sort(([a1], [b1]) => a1.localeCompare(b1))) {
    const bad = xs.filter((x) => word(x.base) === 'pass' && word(x.drawn) === 'fail');
    if (bad.length === 0) continue;
    const [policy, engine, probe, part] = k.split('|');
    L.push(`| ${policy} | ${engine} | ${probe} | ${xs[0].width}@${xs[0].dpr} | ${part} | ${bad.length}/${xs.length} | ${xs.map((x) => `${word(x.base)[0]}>${word(x.drawn)[0]} ${x.drawn?.ppm ?? '-'}/${x.drawn?.delta ?? '-'}`).join(', ')} | ${xs[0].files} |`);
  }
  L.push('');
  // the decoded memory a part's copies save, per probe (one value per probe: the first rep; the plan is the same in every rep)
  const savingRows = new Map();
  for (const x of rowsAll) { const k = `${x.policy}|${x.engine}|${x.part}|${x.probe}`; if (!savingRows.has(k)) savingRows.set(k, x); }
  L.push('### Decoded saving per part and probe (KiB, 4 bytes per pixel, natural size minus copy size; decision of the part in brackets)', '', `| policy | engine | part | decision | files (max) | KiB min | KiB median | KiB max | probes |`, '|---|---|---|---|---|---|---|---|---|');
  const sg = new Map();
  for (const x of savingRows.values()) (sg.get(`${x.policy}|${x.engine}|${x.part}`) ?? sg.set(`${x.policy}|${x.engine}|${x.part}`, []).get(`${x.policy}|${x.engine}|${x.part}`)).push(x);
  for (const [k, xs] of [...sg].sort(([a1], [b1]) => a1.localeCompare(b1))) {
    const [policy, engine, part] = k.split('|');
    const v = xs.map((x) => x.saving).sort((p1, p2) => p1 - p2);
    const d = dec.find((x) => x.policy === policy && x.engine === engine && x.part === part)?.decision;
    L.push(`| ${policy} | ${engine} | ${part} | ${d} | ${Math.max(...xs.map((x) => x.files))} | ${kib(v[0])} | ${kib(v[Math.floor(v.length / 2)])} | ${kib(v[v.length - 1])} | ${xs.length} |`);
  }
  L.push('');
  if (opts.cells) {
    L.push('### Cells (probe, base verdict, drawn verdict, ppm of the drawn run, files with a copy, decoded saving KiB)', '', '| policy | engine | probe | width@dpr | part | rep | base | drawn | drawn ppm / delta | files | saving KiB |', '|---|---|---|---|---|---|---|---|---|---|---|');
    for (const r of results) {
      for (const row of r.rows) {
        if (row.error || row.files === 0) continue;
        L.push(`| ${row.policy} | ${r.engine} | ${row.probe} | ${row.width}@${row.dpr} | ${row.part} | ${r.tag} | ${word(row.base)} ${row.base?.ppm ?? ''} | **${word(row.drawn)}** | ${row.drawn?.ppm ?? '-'} / ${row.drawn?.delta ?? '-'} | ${row.files} | ${kib(row.saving)} |`);
      }
    }
    L.push('');
  }
  // why files have no exact copy: each (engine, probe) is counted once, from the first result file that has it
  const seen = new Set();
  const per = [];
  for (const r of results) {
    for (const probe of r.probes) {
      const k = `${r.engine}|${probe}`;
      const fs = r.files.filter((f) => f.probe === probe);
      if (seen.has(k) || fs.length === 0) continue;
      seen.add(k);
      const dp = r.rows.find((x) => x.probe === probe);
      per.push({ engine: r.engine, probe, label: dp ? `${dp.width}@${dp.dpr}` : '', fs });
    }
  }
  const kinds = [...new Set(per.flatMap((x) => x.fs.map((f) => f.why)))].sort((a, b) => (a === 'ok' ? -1 : b === 'ok' ? 1 : a.localeCompare(b)));
  L.push('### Why a file has no exact copy (files per engine and probe)', '', `| engine | probe | width@dpr | ${kinds.join(' | ')} |`, `|---|---|---|${kinds.map(() => '---|').join('')}`);
  for (const x of per.sort((a, b) => a.engine.localeCompare(b.engine) || a.probe.localeCompare(b.probe))) L.push(`| ${x.engine} | ${x.probe} | ${x.label} | ${kinds.map((w) => x.fs.filter((f) => f.why === w).length).join(' | ')} |`);
  L.push('');
  return L.join('\n');
}

export async function decideCli(_args, { arg, list }) {
  const results = loadResults(list(arg('in')).map((d) => resolve(d)));
  if (results.length === 0) throw new Error(`no arm result files in ${arg('in')}`);
  const md = tablesMd(results, { cells: process.argv.includes('--cells') });
  if (arg('out')) writeFileSync(resolve(arg('out')), md + '\n');
  console.log(md);
}
