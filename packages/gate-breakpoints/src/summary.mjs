// Turns the raw run files into the comparison and the table. All decisions are calls into verdict.mjs; this file only
// groups, counts and prints. Deterministic: sorted keys, no clocks.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { loadAnchors, loadGen, expectFor, partJson, selectParts } from './spec.mjs';
import { STATUS, cellVerdict, envDeviations, partItems, rollup, truthItems } from './verdict.mjs';

const ENGINES = ['chromium', 'playwright-webkit'];

const statuses = (items) => items.map((i) => i.status);
/** Rows of the table: the matchMedia checks split by what they compare, then the four parts. */
const TRUTH_ROWS = { 'matchMedia orig=rewrite': ['truth.AR', 'truth.neutral.AR'], 'matchMedia =Lean': ['truth.lean', 'truth.neutral.lean'], 'matchMedia legacy text': ['truth.legacy'] };
const rowsOf = (parts) => [...Object.keys(TRUTH_ROWS), ...parts];
const rowVerdicts = (ev, parts) => ({
  ...Object.fromEntries(Object.entries(TRUTH_ROWS).map(([row, cls]) => [row, cellVerdict(statuses(ev.truth.filter((i) => cls.includes(i.cls))))])),
  ...Object.fromEntries(parts.map((p) => [p, cellVerdict(statuses(ev.parts[p]))])),
});

/** Everything the table needs for one sampled state: env deviations, truth items, per-part items. */
function evaluateState({ requested, orig, rewrite, expect, expectNeutral, header, anchors, deviceEdges, parts: partIds }) {
  const dev = { orig: envDeviations(requested, orig.raw ?? orig, deviceEdges), rewrite: envDeviations(requested, rewrite.raw ?? rewrite, deviceEdges) };
  const achieved = dev.orig.length === 0 && dev.rewrite.length === 0;
  const o = orig.raw ?? orig, r = rewrite.raw ?? rewrite;
  const truth = truthItems(o, r, expect, expectNeutral, achieved);
  const parts = {};
  for (const pid of partIds) {
    const spec = anchors.parts[pid];
    parts[pid] = partItems(spec, o.parts[pid], r.parts[pid], header.props[pid], anchors);
  }
  return { dev, achieved, truth, parts };
}

function failures(acc, label, ev, partIds) {
  const add = (part, items) => {
    for (const it of items) {
      if (it.status === STATUS.equal || it.status === STATUS.na) continue;
      const k = `${part}|${it.cls}|${it.role ?? ''}|${it.key}`;
      const e = acc.get(k) ?? { part, cls: it.cls, role: it.role ?? null, key: it.key, status: it.status, count: 0, first: null, labels: [] };
      e.count++;
      if (!e.first) e.first = { at: label, a: it.a, b: it.b, expect: it.expect ?? null, idx: it.idx ?? null };
      if (e.labels.length < 64) e.labels.push(label);
      acc.set(k, e);
    }
  };
  add('matchMedia', ev.truth);
  for (const pid of partIds) add(pid, ev.parts[pid].filter((i) => i.cls !== 'info'));
}

function infoDiffs(acc, label, ev, partIds) {
  for (const pid of partIds) {
    for (const it of ev.parts[pid]) {
      if (it.cls !== 'info' || !it.differs) continue;
      const k = `${pid}|${it.role}|${it.key}`;
      const e = acc.get(k) ?? { part: pid, role: it.role, key: it.key, count: 0, first: null };
      e.count++;
      if (!e.first) e.first = { at: label, orig: it.a, rewrite: it.b };
      acc.set(k, e);
    }
  }
}

export function summarize(outDir, { parts: requested = null } = {}) {
  const { gen, sha256 } = loadGen();
  const anchors = loadAnchors();
  const deviceEdges = gen.edgePairs.deviceWidth;
  const result = { schema: 'fw.gate-breakpoints.summary/1', genSha256: sha256, engines: {} };
  const md = [];

  for (const engine of ENGINES) {
    const file = join(outDir, `${engine}.json`);
    if (!existsSync(file)) continue;
    const run = JSON.parse(readFileSync(file, 'utf8'));
    if (run.header.gen.sha256 !== sha256) throw new Error(`${engine}: run was made against another breakpoints.gen.json`);
    // Parts covered: what the run collected (header.parts when the run was narrowed, else all), optionally narrowed further
    // here. Selection only; a part the run did not collect cannot be asked for.
    const allIds = Object.keys(anchors.parts);
    const runCovered = run.header.parts ? run.header.parts.covered : allIds;
    const missingFromRun = (requested ?? []).filter((id) => allIds.includes(id) && !runCovered.includes(id));
    if (missingFromRun.length > 0) throw new Error(`${engine}: --parts ${missingFromRun.join(', ')} not collected by this run (it covered ${runCovered.join(', ')})`);
    const sel = selectParts(allIds, requested === null ? runCovered : requested);
    const PARTS = sel.covered, ROWS = rowsOf(PARTS);
    const byId = new Map(gen.matrix.probes.map((p) => [p.id, p]));
    const fails = new Map(), infos = new Map();
    const probeRows = [];

    for (const rec of run.probes) {
      const g = byId.get(rec.id);
      const ev = evaluateState({ requested: rec.env, orig: rec.orig, rewrite: rec.rewrite, expect: g.expect, expectNeutral: g.expectNeutral, header: run.header, anchors, deviceEdges, parts: PARTS });
      failures(fails, rec.id, ev, PARTS);
      infoDiffs(infos, rec.id, ev, PARTS);
      probeRows.push({
        id: rec.id, block: rec.block, achieved: ev.achieved, deviations: ev.dev,
        settled: { orig: rec.orig.settle.splash ?? rec.orig.settle.ready, rewrite: rec.rewrite.settle.ready },
        verdicts: rowVerdicts(ev, PARTS),
        truthCounts: countBy(ev.truth),
        compared: Object.fromEntries(PARTS.map((p) => [p, ev.parts[p].filter((i) => i.cls !== 'info' && i.status !== STATUS.na).length])),
      });
    }

    const sweepRows = [];
    for (const sw of run.sweeps) {
      const stopRows = sw.stops.map((env, i) => {
        const v = expectFor(gen, env);
        const ev = evaluateState({ requested: env, orig: sw.orig[i], rewrite: sw.rewrite[i], expect: v?.expect, expectNeutral: v?.expectNeutral, header: run.header, anchors, deviceEdges, parts: PARTS });
        failures(fails, `${sw.id}#${i}@${env.width}x${env.height}`, ev, PARTS);
        infoDiffs(infos, `${sw.id}#${i}`, ev, PARTS);
        return { i, width: env.width, height: env.height, achieved: ev.achieved, vector: v ? v.from : null, verdicts: rowVerdicts(ev, PARTS) };
      });
      // hysteresis: the state after the sequence against a fresh load at the same final environment, per arm
      const lastI = sw.stops.length - 1;
      const stale = {};
      for (const site of ['orig', 'rewrite']) {
        const items = PARTS.flatMap((pid) => partItems(anchors.parts[pid], sw[site][lastI].parts[pid], sw.freshFinal[site].raw.parts[pid], run.header.props[pid], anchors));
        stale[site] = { compared: items.filter((x) => x.cls !== 'info' && x.status !== STATUS.na).length, differ: items.filter((x) => x.cls !== 'info' && (x.status === STATUS.differ || x.status === STATUS.missing)).length };
      }
      sweepRows.push({ id: sw.id, blurb: sw.blurb, stops: stopRows, stale, verdicts: Object.fromEntries(ROWS.map((k) => [k, rollup(stopRows.map((s) => s.verdicts[k]))])) });
    }

    // table: rows = truth + parts, columns = blocks + sweeps
    const blocks = gen.matrix.blocks.map((b) => b.id);
    const table = {};
    for (const row of ROWS) {
      table[row] = {};
      for (const b of blocks) {
        const ps = probeRows.filter((p) => p.block === b);
        const vs = ps.map((p) => p.verdicts[row]);
        table[row][b] = ps.length === 0 ? { verdict: 'not-run', failing: 0, total: 0 } : { verdict: rollup(vs), failing: vs.filter((v) => v === 'fail').length, total: vs.filter((v) => v !== 'not-comparable').length };
      }
      for (const s of sweepRows) {
        const vs = s.stops.map((x) => x.verdicts[row]);
        table[row][`sweep:${s.id}`] = { verdict: s.verdicts[row], failing: vs.filter((v) => v === 'fail').length, total: vs.filter((v) => v !== 'not-comparable').length };
      }
    }
    const envRow = {};
    for (const b of blocks) { const ps = probeRows.filter((p) => p.block === b); envRow[b] = { achieved: ps.filter((p) => p.achieved).length, total: ps.length }; }

    const failList = [...fails.values()].sort((a, b) => b.count - a.count || (a.part + a.role + a.key < b.part + b.role + b.key ? -1 : 1));
    const infoList = [...infos.values()].sort((a, b) => b.count - a.count || (a.part + a.role + a.key < b.part + b.role + b.key ? -1 : 1));
    result.engines[engine] = { browser: run.header.browser, ...(sel.narrowed ? { parts: { covered: sel.covered, skipped: sel.skipped } } : {}), table, envAchieved: envRow, probes: probeRows, sweeps: sweepRows, failures: failList, originOnlyDifferences: infoList };
    md.push(...render(engine, run.header, table, envRow, sweepRows, failList, infoList, blocks, anchors, sel));
  }

  writeFileSync(join(outDir, 'summary.json'), JSON.stringify(result, null, 1) + '\n');
  writeFileSync(join(outDir, 'summary.md'), md.join('\n') + '\n');
  process.stdout.write(md.join('\n') + '\n');
  return result;
}

function countBy(items) {
  const c = {};
  for (const it of items) { const k = `${it.cls}:${it.status}`; c[k] = (c[k] ?? 0) + 1; }
  return Object.fromEntries(Object.entries(c).sort());
}

const cell = (c) => (c.verdict === 'pass' ? 'pass' : c.verdict === 'fail' ? `FAIL ${c.failing}/${c.total}` : c.verdict === 'not-comparable' ? 'NC' : '-');

function render(engine, header, table, envRow, sweepRows, failList, infoList, blocks, anchors, sel) {
  const cols = [...blocks, ...sweepRows.map((s) => `sweep:${s.id}`)];
  const out = [`## ${engine} (${header.browser})`, '', `Rows: matchMedia of the 30 conditions + 4 neutral queries, original vs rewrite; against Lean's expected value (compared only where the env was achieved on both arms and a vector exists, else NC); the legacy max-/min- text against the range text; then the anchors of each part. Cells: pass / FAIL probes-failing/probes-comparable / NC = not comparable / - = block not run.`, ''];
  // No silent narrowing: a narrowed verdict says which parts it covers and which it does not. matchMedia rows are
  // part-independent (every load collects them), so they stay in the table.
  if (sel.narrowed) out.push(`**Narrowed to parts: ${sel.covered.join(', ')}. Skipped (no verdict for them): ${sel.skipped.join(', ')}.** The matchMedia rows are not part-specific and are kept.`, '');
  out.push(`| row | ${cols.join(' | ')} |`, `|---|${cols.map(() => '---').join('|')}|`);
  out.push(`| env achieved | ${blocks.map((b) => `${envRow[b].achieved}/${envRow[b].total}`).join(' | ')} | ${sweepRows.map(() => '').join(' | ')} |`);
  for (const row of Object.keys(table)) out.push(`| ${row} | ${cols.map((c) => cell(table[row][c])).join(' | ')} |`);
  out.push('', 'Sweep hysteresis (state after the sequence vs a fresh load at the same final env, per arm; items differing / compared):', '');
  for (const s of sweepRows) out.push(`- ${s.id}: orig ${s.stale.orig.differ}/${s.stale.orig.compared}, rewrite ${s.stale.rewrite.differ}/${s.stale.rewrite.compared}`);
  out.push('', 'Failing items (count = probes or stops where the item differed; first example):', '', '| part | kind | role | key | count | first at | orig | rewrite | lean |', '|---|---|---|---|---|---|---|---|---|');
  for (const f of failList.slice(0, 60)) out.push(`| ${f.part} | ${f.cls} | ${f.role ?? ''} | ${f.key} | ${f.count} | ${f.first.at} | ${JSON.stringify(f.first.a)} | ${JSON.stringify(f.first.b)} | ${f.first.expect === null ? '' : JSON.stringify(f.first.expect)} |`);
  if (failList.length > 60) out.push(`| ... | | | | ${failList.length - 60} more distinct items in summary.json | | | | |`);
  out.push('', `Properties only the original declares for a compared element (information, not in any verdict): ${infoList.length} distinct (part, role, property); top 25:`, '', '| part | role | property | probes differing | first at | orig | rewrite |', '|---|---|---|---|---|---|---|');
  for (const f of infoList.slice(0, 25)) out.push(`| ${f.part} | ${f.role} | ${f.key} | ${f.count} | ${f.first.at} | ${JSON.stringify(f.first.orig)} | ${JSON.stringify(f.first.rewrite)} |`);
  out.push('');
  return out;
}
