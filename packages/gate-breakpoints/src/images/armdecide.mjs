// Reads the result files of the drawn-size arm (armv2.mjs, schema fw.images.arm2/1; one per engine, rep and shard) and sets them
// down as tables: the decision of each part per policy and engine (armplan.partDecisionWithCopies, the twin of
// ImageArm.partDecisionWithCopies, each cell on its own), the cells behind it with their counts, and the decoded-memory saving.
// Nothing is measured or decided here: a missing or truncated file is an error, an error row is an error cell, and a cell whose copies
// the reps did not agree on (armplan.disputedCopy) is a `nc` cell.
//   node src/images/cli.mjs arm decide --in DIR[,DIR...] [--out FILE.md] [--run-id ID] [--sha SHA] [--splice NOTE.md]
//     [--engines chromium,playwright-webkit] [--reps r1,r2,r3] [--shards 3]
import { readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { disputedCopy, partDecisionWithCopies } from './armplan.mjs';

const walk = (d) => readdirSync(d).flatMap((n) => {
  const p = join(d, n);
  return statSync(p).isDirectory() ? walk(p) : /^arm-.*\.json$/.test(n) ? [p] : [];
});

/** Load the result files under `dirs` (a file path is taken as it is). */
export function loadResults(dirs) {
  const files = dirs.flatMap((d) => (statSync(d).isDirectory() ? walk(d) : [d]));
  return files.map((f) => ({ path: f, ...JSON.parse(readFileSync(f, 'utf8')) })).filter((j) => j.schema === 'fw.images.arm2/1');
}

export const repOf = (tag) => tag.replace(/-s\d+$/, '');
const word = (c) => c?.v ?? 'error';
const push = (m, k, v) => (m.get(k) ?? m.set(k, []).get(k)).push(v);

/**
 * The problems that make a result set unusable: for each engine x rep x shard the file `<rep>-s<shard>` must exist exactly once,
 * not be truncated, list the probes of its shard (`probesOf(shard)`), and hold for each of them an error row or a row for every
 * policy x part. Returns the list of messages (empty when complete).
 */
export function checkComplete(results, { engines, reps, shards, probesOf }) {
  const bad = [];
  for (const engine of engines) {
    for (const rep of reps) {
      for (let shard = 1; shard <= shards; shard++) {
        const tag = `${rep}-s${shard}`;
        const here = results.filter((r) => r.engine === engine && r.tag === tag);
        const id = `${engine} ${tag}`;
        if (here.length !== 1) { bad.push(`${id}: ${here.length} result files, want 1`); continue; }
        const r = here[0];
        if (r.truncated) bad.push(`${id}: truncated`);
        const want = probesOf(`${shard}/${shards}`);
        if (JSON.stringify(r.probes) !== JSON.stringify(want)) bad.push(`${id}: probes ${JSON.stringify(r.probes)} are not the shard's ${JSON.stringify(want)}`);
        for (const probe of want) {
          const rows = r.rows.filter((x) => x.probe === probe);
          if (rows.some((x) => x.error)) continue;
          for (const policy of r.policies ?? []) {
            for (const part of r.parts ?? []) {
              const n = rows.filter((x) => x.policy === policy && x.part === part).length;
              if (n !== 1) bad.push(`${id}: probe ${probe} has ${n} rows for ${policy} ${part}, want 1`);
            }
          }
        }
      }
    }
  }
  const known = new Set(engines.flatMap((e) => reps.flatMap((rp) => Array.from({ length: shards }, (_, i) => `${e}|${rp}-s${i + 1}`))));
  for (const r of results) if (!known.has(`${r.engine}|${r.tag}`)) bad.push(`${r.engine} ${r.tag}: not an expected result file`);
  return bad;
}

/**
 * Every cell of every result file as one record { policy, engine, rep, probe, width, dpr, part, base, drawn, files, saving, ppm,
 * delta, error, disputed }. An error row (the probe's audit failed) is one error cell for every policy and part of the file. Under
 * the `exact` policy a cell is `disputed` when one of the part's copied files was planned with another copy (or none) in another rep
 * of the same engine and probe: a copy in one rep that the audit of another rep puts under a transform is not a 1:1 copy.
 */
export function cellsOf(results) {
  const reps = new Map();
  const plans = new Map();
  for (const r of results) {
    const rep = repOf(r.tag);
    for (const row of r.rows) if (!row.error) (reps.get(`${r.engine}|${row.probe}`) ?? reps.set(`${r.engine}|${row.probe}`, new Set()).get(`${r.engine}|${row.probe}`)).add(rep);
    for (const f of r.files ?? []) {
      const k = `${r.engine}|${f.probe}|${rep}`;
      (plans.get(k) ?? plans.set(k, new Map()).get(k)).set(f.url, f);
    }
  }
  const out = [];
  for (const r of results) {
    const rep = repOf(r.tag);
    for (const row of r.rows) {
      if (row.error) {
        for (const policy of r.policies ?? []) {
          for (const part of r.parts ?? []) out.push({ policy, engine: r.engine, rep, probe: row.probe, width: row.width, dpr: row.dpr, part, base: 'error', drawn: 'error', files: null, saving: 0, ppm: null, delta: null, error: true, disputed: false });
        }
        continue;
      }
      let disputed = false;
      if (row.policy === 'exact' && row.files > 0) {
        const mine = [...(plans.get(`${r.engine}|${row.probe}|${rep}`)?.values() ?? [])].filter((f) => f.exact && f.parts.includes(row.part));
        const all = [...(reps.get(`${r.engine}|${row.probe}`) ?? [])];
        disputed = mine.some((f) => disputedCopy(all.map((rp) => plans.get(`${r.engine}|${row.probe}|${rp}`)?.get(f.url)?.exact ?? null)));
      }
      out.push({ policy: row.policy, engine: r.engine, rep, probe: row.probe, width: row.width, dpr: row.dpr, part: row.part, base: word(row.base), drawn: word(row.drawn), files: row.files, saving: row.saving, ppm: row.drawn?.ppm ?? null, delta: row.drawn?.delta ?? null, error: false, disputed });
    }
  }
  return out;
}

/** A cell as the Lean `CopyCell`: an error cell has unknown copies (it counts as one that has copies); a disputed cell is not comparable. */
export const leanCell = (c) => ({ copy: c.error || c.files > 0, base: c.base, drawn: c.disputed ? 'nc' : c.drawn });

/**
 * Decisions: for each (policy, engine, part) the cells of every probe and rep, decided one by one by the Lean twin, per engine and over
 * both engines (engine `all`). Returns [{ policy, engine, part, decision, cells, copyCells, errors, disputed, worst }].
 */
export function decide(results) {
  const by = new Map();
  for (const c of cellsOf(results)) for (const e of [c.engine, 'all']) push(by, `${c.policy}|${e}|${c.part}`, c);
  const out = [];
  for (const [k, cells] of [...by].sort(([a], [b]) => a.localeCompare(b))) {
    const [policy, engine, part] = k.split('|');
    const withCopy = cells.filter((c) => leanCell(c).copy);
    out.push({
      policy, engine, part,
      decision: partDecisionWithCopies(cells.map(leanCell)),
      cells: cells.length,
      copyCells: withCopy.length,
      errors: cells.filter((c) => c.error).length,
      disputed: cells.filter((c) => c.disputed).length,
      worst: Math.max(-1, ...withCopy.filter((c) => !c.disputed).map((c) => c.ppm ?? -1)),
    });
  }
  return out;
}

const kib = (n) => `${(n / 1024).toFixed(1)}`;
const open = (w) => (w === 'pass' || w === 'fail' ? w : 'open');
const COLS = ['pass>pass', 'pass>fail', 'fail>pass', 'fail>fail', 'pass>open', 'fail>open', 'open>pass', 'open>fail', 'open>open'];

export const SECTIONS = ['runs', 'coverage', 'decision', 'did', 'fails', 'saving', 'cells', 'why'];

/** The tables as markdown; `opts.sections` picks some of SECTIONS (default all but `cells`), `opts.runId` and `opts.sha` head them. */
export function tablesMd(results, opts = {}) {
  const want = new Set(opts.sections ?? SECTIONS.filter((s) => s !== 'cells'));
  const head = [opts.runId ? `run ${opts.runId}` : null, opts.sha ? `commit ${String(opts.sha).slice(0, 8)}` : null].filter(Boolean).join(', ');
  const tag = head ? ` (${head})` : '';
  const L = [];
  const dec = decide(results);
  const cells = cellsOf(results);
  const copyCells = cells.filter((c) => leanCell(c).copy);
  if (want.has('runs')) {
    L.push(`### Runs${tag}`, '', ...results.map((r) => `- ${r.engine} ${r.tag} (${r.browser ?? '?'}${r.truncated ? ', TRUNCATED' : ''}): ${r.probes.length} probes`), '');
  }
  if (want.has('coverage') && opts.matrix) L.push(...coverageMd(cells, opts.matrix, tag));
  const engines = [...new Set(dec.map((d) => d.engine))].filter((e) => e !== 'all').sort();
  const parts = [...new Set(dec.map((d) => d.part))];
  if (want.has('decision')) {
    for (const policy of [...new Set(dec.map((d) => d.policy))]) {
      L.push(`### Decision per part, policy ${policy}${tag}`, '', `| part | ${engines.map((e) => `${e} (cells with a copy of all, worst ppm)`).join(' | ')} | both engines |`, `|---|${engines.map(() => '---|').join('')}---|`);
      for (const part of parts) {
        const ds = engines.map((e) => dec.find((d) => d.policy === policy && d.engine === e && d.part === part));
        const show = (d) => (d ? `${d.decision} (${d.copyCells} of ${d.cells}, ${d.worst})` : '-');
        const both = dec.find((d) => d.policy === policy && d.engine === 'all' && d.part === part)?.decision ?? '-';
        L.push(`| ${part} | ${ds.map(show).join(' | ')} | ${both} |`);
      }
      L.push('');
    }
  }
  const groups = new Map();
  for (const x of copyCells) push(groups, `${x.policy}|${x.engine}|${x.part}`, x);
  if (want.has('did')) {
    L.push(`### What the cells did${tag} (base verdict > drawn verdict; open = unsettled, invalid, nc or error; disputed = the reps did not agree on the file's copy, left out of the columns)`, '', `| policy | engine | part | cells with a copy | ${COLS.join(' | ')} | disputed | error | mean saving KiB per cell |`, `|---|---|---|---|${COLS.map(() => '---|').join('')}---|---|---|`);
    for (const [k, xs] of [...groups].sort(([a1], [b1]) => a1.localeCompare(b1))) {
      const [policy, engine, part] = k.split('|');
      const live = xs.filter((x) => !x.disputed && !x.error);
      const n = (c) => live.filter((x) => `${open(x.base)}>${open(x.drawn)}` === c).length;
      L.push(`| ${policy} | ${engine} | ${part} | ${xs.length} | ${COLS.map(n).join(' | ')} | ${xs.filter((x) => x.disputed).length} | ${xs.filter((x) => x.error).length} | ${kib(live.reduce((t, x) => t + x.saving, 0) / Math.max(1, live.length))} |`);
    }
    L.push('');
  }
  if (want.has('fails')) {
    L.push(`### Cells where the copy fails and the baseline passes${tag} (reps with that / reps with a copy; per rep: base>drawn initials, drawn ppm / delta, ~ = disputed)`, '', '| policy | engine | probe | width@dpr | part | reps | per rep | files |', '|---|---|---|---|---|---|---|---|');
    const byCell = new Map();
    for (const x of copyCells) push(byCell, `${x.policy}|${x.engine}|${x.probe}|${x.part}`, x);
    for (const [k, xs] of [...byCell].sort(([a1], [b1]) => a1.localeCompare(b1))) {
      const bad = xs.filter((x) => x.base === 'pass' && x.drawn === 'fail' && !x.disputed);
      if (bad.length === 0) continue;
      const [policy, engine, probe, part] = k.split('|');
      const per = xs.map((x) => `${x.base[0]}>${x.drawn[0]} ${x.ppm ?? '-'}/${x.delta ?? '-'}${x.disputed ? '~' : ''}`).join(', ');
      L.push(`| ${policy} | ${engine} | ${probe} | ${xs[0].width}@${xs[0].dpr} | ${part} | ${bad.length}/${xs.length} | ${per} | ${xs[0].files} |`);
    }
    L.push('');
  }
  if (want.has('saving')) {
    // one value per policy, engine, part and probe: the first rep (in tag order) whose cell has a copy and is not disputed
    const first = new Map();
    for (const x of [...copyCells].sort((a, b) => a.rep.localeCompare(b.rep))) if (!x.disputed && !x.error && !first.has(`${x.policy}|${x.engine}|${x.part}|${x.probe}`)) first.set(`${x.policy}|${x.engine}|${x.part}|${x.probe}`, x);
    L.push(`### Decoded saving per part and probe${tag} (KiB, 4 bytes per pixel, natural size minus copy size; decision of the part in brackets)`, '', '| policy | engine | part | decision | files (max) | KiB min | KiB median | KiB max | probes |', '|---|---|---|---|---|---|---|---|---|');
    const sg = new Map();
    for (const x of first.values()) push(sg, `${x.policy}|${x.engine}|${x.part}`, x);
    for (const [k, xs] of [...sg].sort(([a1], [b1]) => a1.localeCompare(b1))) {
      const [policy, engine, part] = k.split('|');
      const v = xs.map((x) => x.saving).sort((p1, p2) => p1 - p2);
      const d = dec.find((x) => x.policy === policy && x.engine === engine && x.part === part)?.decision;
      L.push(`| ${policy} | ${engine} | ${part} | ${d} | ${Math.max(...xs.map((x) => x.files))} | ${kib(v[0])} | ${kib(v[Math.floor(v.length / 2)])} | ${kib(v[v.length - 1])} | ${xs.length} |`);
    }
    L.push('');
  }
  if (want.has('cells')) {
    L.push(`### Cells${tag} (probe, base verdict, drawn verdict, ppm of the drawn run, files with a copy, decoded saving KiB)`, '', '| policy | engine | probe | width@dpr | part | rep | base | drawn | drawn ppm / delta | files | saving KiB |', '|---|---|---|---|---|---|---|---|---|---|---|');
    for (const c of copyCells) L.push(`| ${c.policy} | ${c.engine} | ${c.probe} | ${c.width}@${c.dpr} | ${c.part} | ${c.rep} | ${c.base} | **${c.drawn}**${c.disputed ? ' ~' : ''} | ${c.ppm ?? '-'} / ${c.delta ?? '-'} | ${c.files ?? '?'} | ${kib(c.saving)} |`);
    L.push('');
  }
  if (want.has('why')) L.push(...whyMd(results, tag));
  return L.join('\n');
}

/** Which width x DPR pairs of the gate matrix (`matrix`: [{ width, dpr }]) the cells cover, and the pairs they do not. Every claim of the tables holds at the probed pairs only. */
function coverageMd(cells, matrix, tag) {
  const pair = (w, d) => `${w}@${d}`;
  const probed = new Set(cells.map((c) => pair(c.width, c.dpr)));
  const all = [...new Set(matrix.map((p) => pair(p.width, p.dpr)))];
  const gaps = all.filter((x) => !probed.has(x));
  const byDpr = (xs) => [1, 2, 3].map((d) => `DPR ${d}: ${xs.filter((x) => x.endsWith(`@${d}`)).map((x) => x.split('@')[0]).join(' ') || '-'}`).join('; ');
  return [`### Coverage${tag}`, '', `Probed width x DPR pairs: ${probed.size} of ${all.length} in the gate matrix (${matrix.length} probes). Every verdict below holds at the 22 probe ids of arm-probes.json only; other gate probes at a probed pair (reduced motion, hover/pointer crosses, other heights) are not probed.`, '',
    `- probed: ${byDpr([...probed].sort((a, b) => parseFloat(a) - parseFloat(b)))}`, `- not probed: ${byDpr(gaps.sort((a, b) => parseFloat(a) - parseFloat(b)))}`, ''];
}

/**
 * Why files have no exact copy, per engine and probe, over all reps together: a file counts as `ok` only when every rep planned the
 * same exact copy; when the reps disagree it counts as `disputed`; otherwise it counts under the reason all reps gave.
 */
function whyMd(results, tag) {
  const by = new Map();
  for (const r of results) {
    for (const f of r.files ?? []) {
      const m = by.get(`${r.engine}|${f.probe}`) ?? by.set(`${r.engine}|${f.probe}`, new Map()).get(`${r.engine}|${f.probe}`);
      push(m, f.url, { rep: repOf(r.tag), f });
    }
  }
  const nReps = (engine, probe) => new Set(results.filter((r) => r.engine === engine && r.rows.some((x) => x.probe === probe && !x.error)).map((r) => repOf(r.tag))).size;
  const label = new Map(cellsOf(results).map((c) => [c.probe, `${c.width}@${c.dpr}`]));
  const per = [];
  for (const [k, m] of [...by].sort(([a], [b]) => a.localeCompare(b))) {
    const [engine, probe] = k.split('|');
    const counts = {};
    for (const entries of m.values()) {
      const whys = new Set(entries.map((e) => e.f.why));
      const seenReps = new Set(entries.map((e) => e.rep));
      const plans = entries.map((e) => e.f.exact ?? null);
      let w;
      if (seenReps.size < nReps(engine, probe)) w = 'disputed';
      else if (whys.size === 1) w = whys.has('ok') && disputedCopy(plans) ? 'disputed' : [...whys][0];
      else w = 'disputed';
      counts[w] = (counts[w] ?? 0) + 1;
    }
    per.push({ engine, probe, label: label.get(probe) ?? '', counts });
  }
  const kinds = [...new Set(per.flatMap((x) => Object.keys(x.counts)))].sort((a, b) => (a === 'ok' ? -1 : b === 'ok' ? 1 : a.localeCompare(b)));
  return [`### Why a file has no exact copy${tag} (files per engine and probe; all reps together, \`disputed\` = the reps differ)`, '', `| engine | probe | width@dpr | ${kinds.join(' | ')} |`, `|---|---|---|${kinds.map(() => '---|').join('')}`,
    ...per.map((x) => `| ${x.engine} | ${x.probe} | ${x.label} | ${kinds.map((w) => x.counts[w] ?? 0).join(' | ')} |`), ''];
}

/** The note's generated block: the sections the committed note holds, between the begin and end markers. */
export const NOTE_SECTIONS = ['runs', 'coverage', 'decision', 'did', 'fails', 'why'];
export const BEGIN = '<!-- arm-tables:begin -->';
export const END = '<!-- arm-tables:end -->';

/** `note` with the text between the markers replaced by `block`. */
export function splice(note, block) {
  const a = note.indexOf(BEGIN);
  const b = note.indexOf(END);
  if (a < 0 || b < a) throw new Error(`the note has no ${BEGIN} ... ${END} block`);
  return `${note.slice(0, a + BEGIN.length)}\n\n${block.trim()}\n\n${note.slice(b)}`;
}

export async function decideCli(_args, { arg, list }) {
  const results = loadResults(list(arg('in')).map((d) => resolve(d)));
  if (results.length === 0) throw new Error(`no arm result files in ${arg('in')}`);
  const { probeIds } = await import('./armv2.mjs');
  const bad = checkComplete(results, { engines: list(arg('engines', 'chromium,playwright-webkit')), reps: list(arg('reps', 'r1,r2,r3')), shards: Number(arg('shards', '3')), probesOf: (shard) => probeIds({ shard }) });
  if (bad.length > 0) {
    console.error(`arm decide: the result set is incomplete (${bad.length}):\n${bad.slice(0, 40).map((m) => `  ${m}`).join('\n')}`);
    process.exitCode = 1;
    return;
  }
  const { loadGen } = await import('../spec.mjs');
  const o = { runId: arg('run-id', null), sha: arg('sha', null), matrix: loadGen().gen.matrix.probes };
  const md = tablesMd(results, { ...o, sections: process.argv.includes('--cells') ? SECTIONS : undefined });
  if (arg('out')) writeFileSync(resolve(arg('out')), md + '\n');
  if (arg('splice')) {
    const f = resolve(arg('splice'));
    writeFileSync(f, splice(readFileSync(f, 'utf8'), tablesMd(results, { ...o, sections: NOTE_SECTIONS })));
  }
  console.log(md);
}
