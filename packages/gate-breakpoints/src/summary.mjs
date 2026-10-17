// Turns the raw run files into the comparison and the table. Every status, verdict, count and table cell is Lean's
// (lean/Fw/Gate, through fwcore: verdict.mjs); this file only groups the failing items for the report and prints.
// Deterministic: sorted keys, no clocks.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { loadAnchors, loadGen, expectFor, partJson, selectParts } from './spec.mjs';
import { context, evaluate, tallies } from './verdict.mjs';
import { report as settleReport } from './settle.mjs';

const ENGINES = ['chromium', 'playwright-webkit'];
/** The matchMedia rows of the table, as Lean names them (Fw.Gate.truthRows); the part rows follow. */
const TRUTH_ROWS = ['matchMedia orig=rewrite', 'matchMedia =Lean', 'matchMedia legacy text'];

/** The failing items of one state (Lean marks them), grouped by (part, kind, role, key) for the report. */
function failures(acc, label, ev, partIds) {
  const add = (part, items) => {
    for (const it of items) {
      const k = `${part}|${it.cls}|${it.role ?? ''}|${it.key}`;
      const e = acc.get(k) ?? { part, cls: it.cls, role: it.role ?? null, key: it.key, status: it.status, count: 0, first: null, labels: [] };
      e.count++;
      if (!e.first) e.first = { at: label, a: it.a, b: it.b, expect: it.expect ?? null, idx: it.idx ?? null };
      if (e.labels.length < 64) e.labels.push(label);
      acc.set(k, e);
    }
  };
  add('matchMedia', ev.truth.filter((t) => t.fails));
  for (const pid of partIds) add(pid, ev.fails[pid]);
}

/** The original-only properties whose values differ (Lean marks them), grouped by (part, role, key). */
function infoDiffs(acc, label, ev, partIds) {
  for (const pid of partIds) {
    for (const it of ev.infoDiffs[pid]) {
      const k = `${pid}|${it.role}|${it.key}`;
      const e = acc.get(k) ?? { part: pid, role: it.role, key: it.key, count: 0, first: null };
      e.count++;
      if (!e.first) e.first = { at: label, orig: it.a, rewrite: it.b };
      acc.set(k, e);
    }
  }
}

/** The settle wait of an arm record (probe arm {settle, raw} or sweep stop raw), or null for a run made before the wait. */
const waitOf = (arm) => (arm.raw ?? arm).settleWait ?? null;

/**
 * Lean's report (Fw.Gate.Settle.report, settle.mjs) for one state: 'unsettled' when either arm's wait ended unsettled. The
 * values' equality is not needed for that case, so true is passed; the entries name the arms that did not settle.
 */
function settleOf(label, state) {
  const w = { orig: waitOf(state.orig), rewrite: waitOf(state.rewrite) };
  if (!w.orig || !w.rewrite) return { unsettled: false, entry: null };
  const r = settleReport(w.orig.outcome, w.rewrite.outcome, true);
  if (r !== 'unsettled') return { unsettled: false, entry: null };
  const arms = ['orig', 'rewrite'].filter((a) => w[a].outcome === 'unsettled')
    .map((a) => ({ arm: a, frames: w[a].frames, waitedMs: w[a].waitedMs, running: w[a].running, stable: w[a].stable, hoverInside: w[a].hoverInside, parked: w[a].parked }));
  return { unsettled: true, entry: { at: label, arms } };
}

/** An unsettled state has no verdict: its rows are not comparable (never pass, never fail); unreachable stays unreachable. */
const unsettledRows = (rows) => Object.fromEntries(Object.entries(rows).map(([k, v]) => [k, String(v).startsWith('unreachable') ? v : 'not-comparable']));

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
    const PARTS = sel.covered;
    const byId = new Map(gen.matrix.probes.map((p) => [p.id, p]));
    const fails = new Map(), infos = new Map();

    // one fwcore run: every probe state, every sweep stop, every sweep's hysteresis pair (orig, rewrite)
    // The engine port names the cells the engine cannot reach (Lean Fw.Gate.Reach); runs made before the header carried it
    // have a port only for Chromium (WebKit's would be a guess: Apple or GLib).
    const port = run.header.port ?? (engine === 'chromium' ? 'chromium' : null);
    const ctx = context({ anchors, parts: PARTS, props: run.header.props, deviceEdges, port });
    const states = run.probes.map((rec) => {
      const g = byId.get(rec.id);
      return { requested: rec.env, orig: rec.orig, rewrite: rec.rewrite, expect: g.expect, expectNeutral: g.expectNeutral };
    });
    const vectors = run.sweeps.map((sw) => sw.stops.map((env) => expectFor(gen, env)));
    run.sweeps.forEach((sw, j) => sw.stops.forEach((env, i) => {
      const v = vectors[j][i];
      states.push({ requested: env, orig: sw.orig[i], rewrite: sw.rewrite[i], expect: v?.expect, expectNeutral: v?.expectNeutral });
    }));
    const stalePairs = run.sweeps.flatMap((sw) => ['orig', 'rewrite'].map((site) => ({ after: sw[site][sw.stops.length - 1], fresh: sw.freshFinal[site] })));
    const { states: evs, stale } = evaluate(ctx, states, stalePairs);
    const ROWS = [...TRUTH_ROWS, ...PARTS];
    if (evs.length > 0 && Object.keys(evs[0].rows).join('\n') !== ROWS.join('\n')) throw new Error(`fwcore rows ${Object.keys(evs[0].rows)} are not ${ROWS}`);

    const probeRows = [];
    const unsettledList = [];
    const waitStats = { samples: 0, unsettled: 0, totalWaitMs: 0, maxWaitMs: 0, totalFrames: 0 };
    const countWait = (state) => {
      for (const a of ['orig', 'rewrite']) {
        const w = waitOf(state[a]);
        if (!w) continue;
        waitStats.samples++; waitStats.totalWaitMs += w.waitedMs; waitStats.totalFrames += w.frames;
        waitStats.maxWaitMs = Math.max(waitStats.maxWaitMs, w.waitedMs);
        if (w.outcome === 'unsettled') waitStats.unsettled++;
      }
    };
    run.probes.forEach((rec, k) => {
      const ev = evs[k];
      countWait(rec);
      const st = settleOf(rec.id, rec);
      if (st.unsettled) { unsettledList.push(st.entry); ev.rows = unsettledRows(ev.rows); } else {
        failures(fails, rec.id, ev, PARTS);
        infoDiffs(infos, rec.id, ev, PARTS);
      }
      probeRows.push({
        id: rec.id, block: rec.block, achieved: ev.achieved, deviations: ev.dev, ...(st.unsettled ? { unsettled: true } : {}),
        settled: { orig: rec.orig.settle.splash ?? rec.orig.settle.ready, rewrite: rec.rewrite.settle.ready },
        verdicts: ev.rows, verdict: st.unsettled ? 'not-comparable' : ev.verdict, reach: ev.reach,
        truthCounts: ev.truthCounts,
        compared: ev.compared,
      });
    });

    let next = run.probes.length;
    const sweepStops = run.sweeps.map((sw, j) => sw.stops.map((env, i) => {
      const ev = evs[next++];
      const label = `${sw.id}#${i}@${env.width}x${env.height}`;
      countWait({ orig: sw.orig[i], rewrite: sw.rewrite[i] });
      const st = settleOf(label, { orig: sw.orig[i], rewrite: sw.rewrite[i] });
      if (st.unsettled) { unsettledList.push(st.entry); ev.rows = unsettledRows(ev.rows); } else {
        failures(fails, label, ev, PARTS);
        infoDiffs(infos, `${sw.id}#${i}`, ev, PARTS);
      }
      const v = vectors[j][i];
      return { i, width: env.width, height: env.height, achieved: ev.achieved, ...(st.unsettled ? { unsettled: true } : {}), vector: v ? v.from : null, verdicts: ev.rows };
    }));

    // table: rows = truth + parts, columns = blocks + sweeps; every cell is a Lean tally
    const blocks = gen.matrix.blocks.map((b) => b.id);
    const cells = [];
    for (const row of ROWS) {
      for (const b of blocks) cells.push({ verdicts: probeRows.filter((p) => p.block === b).map((p) => p.verdicts[row]), block: true });
      for (const stops of sweepStops) cells.push({ verdicts: stops.map((x) => x.verdicts[row]), block: false });
    }
    const tallied = tallies(cells);
    let c = 0;
    const table = {};
    const sweepVerdicts = run.sweeps.map(() => ({}));
    for (const row of ROWS) {
      table[row] = {};
      for (const b of blocks) table[row][b] = tallied[c++];
      run.sweeps.forEach((sw, j) => { const t = tallied[c++]; table[row][`sweep:${sw.id}`] = t; sweepVerdicts[j][row] = t.verdict; });
    }
    // hysteresis: the state after the sequence against a fresh load at the same final environment, per arm
    const sweepRows = run.sweeps.map((sw, j) => ({ id: sw.id, blurb: sw.blurb, stops: sweepStops[j], stale: { orig: stale[2 * j], rewrite: stale[2 * j + 1] }, verdicts: sweepVerdicts[j] }));

    const envRow = {};
    for (const b of blocks) { const ps = probeRows.filter((p) => p.block === b); envRow[b] = { achieved: ps.filter((p) => p.achieved).length, total: ps.length }; }

    const failList = [...fails.values()].sort((a, b) => b.count - a.count || (a.part + a.role + a.key < b.part + b.role + b.key ? -1 : 1));
    const infoList = [...infos.values()].sort((a, b) => b.count - a.count || (a.part + a.role + a.key < b.part + b.role + b.key ? -1 : 1));
    result.engines[engine] = { browser: run.header.browser, ...(sel.narrowed ? { parts: { covered: sel.covered, skipped: sel.skipped } } : {}), table, envAchieved: envRow, settleWait: waitStats, unsettled: unsettledList, probes: probeRows, sweeps: sweepRows, failures: failList, originOnlyDifferences: infoList };
    md.push(...render(engine, run.header, table, envRow, sweepRows, failList, infoList, blocks, anchors, sel, waitStats, unsettledList));
  }

  writeFileSync(join(outDir, 'summary.json'), JSON.stringify(result, null, 1) + '\n');
  writeFileSync(join(outDir, 'summary.md'), md.join('\n') + '\n');
  process.stdout.write(md.join('\n') + '\n');
  return result;
}

/** A table cell (Lean's tally: verdict, failing / comparable probes, unreachable probes). `unreachable:<reason>` = every probe
 *  of the cell is unreachable on this engine port (proved in Fw.Gate.Reach); mixed cells show the unreachable count after. */
const cell = (c) => {
  if (c.verdict.startsWith('unreachable')) return `UNREACHABLE ${c.unreachable} (${c.verdict.slice('unreachable:'.length)})`;
  const base = c.verdict === 'pass' ? 'pass' : c.verdict === 'fail' ? `FAIL ${c.failing}/${c.total}` : c.verdict === 'not-comparable' ? 'NC' : '-';
  return c.unreachable > 0 ? `${base} +${c.unreachable} unreachable` : base;
};

function render(engine, header, table, envRow, sweepRows, failList, infoList, blocks, anchors, sel, waitStats, unsettledList) {
  const cols = [...blocks, ...sweepRows.map((s) => `sweep:${s.id}`)];
  const out = [`## ${engine} (${header.browser})`, '', `Rows: matchMedia of the 30 conditions + 4 neutral queries, original vs rewrite; against Lean's expected value (compared only where the env was achieved on both arms and a vector exists, else NC); the legacy max-/min- text against the range text; then the anchors of each part. Cells: pass / FAIL probes-failing/probes-comparable / NC = not comparable / UNREACHABLE n (reason) = every probe of the cell is a cell this engine port cannot build (Lean-proved reach rule), \`+n unreachable\` = n such probes left out of the count / - = block not run.`, ''];
  // No silent narrowing: a narrowed verdict says which parts it covers and which it does not. matchMedia rows are
  // part-independent (every load collects them), so they stay in the table.
  if (sel.narrowed) out.push(`**Narrowed to parts: ${sel.covered.join(', ')}. Skipped (no verdict for them): ${sel.skipped.join(', ')}.** The matchMedia rows are not part-specific and are kept.`, '');
  out.push(`| row | ${cols.join(' | ')} |`, `|---|${cols.map(() => '---').join('|')}|`);
  out.push(`| env achieved | ${blocks.map((b) => `${envRow[b].achieved}/${envRow[b].total}`).join(' | ')} | ${sweepRows.map(() => '').join(' | ')} |`);
  for (const row of Object.keys(table)) out.push(`| ${row} | ${cols.map((c) => cell(table[row][c])).join(' | ')} |`);
  out.push('', `Settle wait (Lean Fw.Gate.Settle): ${waitStats.samples} arm samples waited ${waitStats.totalWaitMs} ms in total (max ${waitStats.maxWaitMs} ms); ${waitStats.unsettled} ended UNSETTLED. A state with an unsettled arm has no verdict (its rows are NC) and its items are not in the failing list.`);
  for (const u of unsettledList.slice(0, 40)) out.push(`- UNSETTLED ${u.at}: ${u.arms.map((a) => `${a.arm} (frames ${a.frames}, ${a.waitedMs} ms, running ${a.running}, quiet run ${a.stable}, pointer in target ${a.hoverInside}, parked ${a.parked})`).join('; ')}`);
  if (unsettledList.length > 40) out.push(`- ... ${unsettledList.length - 40} more in summary.json`);
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
