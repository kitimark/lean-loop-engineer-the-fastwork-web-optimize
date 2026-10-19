// Port completeness check 5 (fonts) in a browser: per gate viewport, both arms are loaded and every text leaf with its computed
// first font family, weight and style, and the loaded faces of document.fonts, are read (fontsInPage) and judged by the
// Lean rule (lean/Fw/Port/Fonts.lean; golden-checked twin scripts/port/fonts.mjs). The rewrite is served as built.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { PIN_SRC, waitReady } from '../../gate-breakpoints/src/page.mjs';
import { siteDist, snapshotRoot, startServer } from '../../gate-breakpoints/src/serve.mjs';
import { loadGen, probeEnv } from '../../gate-breakpoints/src/spec.mjs';
import { check, excl, fontsInPage, rowsOf, split } from '../../../scripts/port/fonts.mjs';
import { LAUNCHERS } from './engines.mjs';

const CAP_MS = { orig: 20000, rewrite: 15000 };
const FACE_WAIT_MS = 10000;
const log = (...a) => process.stderr.write(a.join(' ') + '\n');

/** One arm at one viewport: load, (real pages) wait for readiness, read leaves and faces. */
export async function readArm(engine, env, { site, origin, path = '/', real = true }) {
  const s = await engine.open(env, { origin, path, init: real ? PIN_SRC : () => {} });
  try {
    if (real) await s.page.evaluate(waitReady, { site, capMs: CAP_MS[site] });
    return await s.page.evaluate(fontsInPage, { rows: rowsOf(site), waitMs: FACE_WAIT_MS });
  } finally { await s.close().catch(() => {}); }
}

const font = (u) => `${u.family} ${u.weight} ${u.style}`;
const faceKey = (f) => `${f.family} ${f.weight} ${f.style}`;

/** Group the font-change pairs of one viewport by (section, font before, font after). Reporting only. */
export function gapsOf(changes) {
  const by = new Map();
  for (const [m, e] of changes) {
    const k = `${m.sec} | ${font(m)} -> ${font(e)}`;
    const g = by.get(k) ?? { sec: m.sec, before: font(m), after: font(e), leaves: 0, texts: [] };
    g.leaves++;
    if (g.texts.length < 3) g.texts.push(m.text.slice(0, 40));
    by.set(k, g);
  }
  return [...by.values()];
}

/** The verdict of one viewport for the two arms' reports: the full lists, no cap. */
export function judge(id, O, R) {
  const v = check(excl, O, R);
  const sp = split(v.missing, v.extra);
  return {
    id, pass: v.pass,
    counts: {
      leaves: { orig: O.leaves.length, rewrite: R.leaves.length }, missing: v.missing.length, extra: v.extra.length,
      missingFaces: v.missingFaces.length, extraFaces: v.extraFaces.length,
      changes: sp.changes.length, moves: sp.moves.length, lost: sp.lost.length, added: sp.added.length,
    },
    settled: { orig: O.settled ?? null, rewrite: R.settled ?? null },
    polls: { orig: O.polls ?? null, rewrite: R.polls ?? null },
    deckTab: { orig: O.deckTab ?? null, rewrite: R.deckTab ?? null },
    changes: sp.changes.map(([m, e]) => ({ sec: m.sec, text: m.text, before: font(m), after: font(e) })),
    moves: sp.moves.map(([m, e]) => ({ text: m.text, font: font(m), from: m.sec, to: e.sec })),
    lost: sp.lost, added: sp.added,
    gaps: gapsOf(sp.changes),
    missing: v.missing, extra: v.extra, missingFaces: v.missingFaces, extraFaces: v.extraFaces,
    loaded: { orig: [...new Set(O.faces.filter((f) => f.status === 'loaded').map(faceKey))], rewrite: [...new Set(R.faces.filter((f) => f.status === 'loaded').map(faceKey))] },
  };
}

/** Run the check for the probes (ids of the gate's Lean matrix) on `engineName`; `targets` = { orig: {origin, path}, rewrite: {...}, real }. */
export async function fontsAtProbes({ engine, probes, targets, concurrency = 2 }) {
  const out = new Array(probes.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(concurrency, probes.length) }, async () => {
    for (;;) {
      const i = next++;
      if (i >= probes.length) return;
      const p = probes[i];
      const env = probeEnv(p);
      try {
        const [O, R] = await Promise.all(['orig', 'rewrite'].map((site) => readArm(engine, env, { site, ...targets[site], real: targets.real })));
        out[i] = judge(p.id, O, R);
      } catch (e) {
        out[i] = { id: p.id, pass: false, error: String(e.message).split('\n')[0] };
      }
      log(`  fonts ${engine.name}: ${p.id} ${out[i].pass ? 'pass' : out[i].error ? 'error' : 'FAIL'}`);
    }
  }));
  return out;
}

export async function runFonts({ engineName, outDir, probeIds, concurrency = 2 }) {
  const { gen } = loadGen();
  const probes = probeIds.map((id) => gen.matrix.probes.find((p) => p.id === id) ?? (() => { throw new Error(`unknown probe ${id}`); })());
  const servers = { orig: await startServer(snapshotRoot()), rewrite: await startServer(siteDist()) };
  const engine = await LAUNCHERS[engineName]();
  try {
    const results = await fontsAtProbes({
      engine, probes, concurrency,
      targets: { real: true, orig: { origin: servers.orig.origin, path: '/' }, rewrite: { origin: servers.rewrite.origin, path: '/' } },
    });
    const file = join(outDir, `${engineName}.fonts.json`);
    mkdirSync(outDir, { recursive: true });
    writeFileSync(file, JSON.stringify({ schema: 'fw.port.fonts/1', engine: engineName, browser: await engine.version(), probes: results }, null, 1) + '\n');
    log(`wrote ${file}`);
    return { file, results };
  } finally {
    await engine.close();
    await Promise.all(Object.values(servers).map((s) => s.close()));
  }
}

const verdictOf = (r) => (r.pass ? 'pass' : r.error ? 'error' : 'FAIL');
const settledOf = (r) => (r.settled ? `${r.settled.orig ? 'y' : 'N'}/${r.settled.rewrite ? 'y' : 'N'}` : '-');

/**
 * Markdown of the results (step summary): per probe the counts of lost and added leaves and how they split into font changes,
 * ownership moves and unpaired text leaves, whether both reads settled, then the font-change gaps (the gap list is these pairs
 * only) and the ownership moves, the unpaired text leaves and the face differences of each failing probe.
 */
export function fontsTable(engineName, results) {
  const rows = results.map((r) => `| ${r.id} | ${verdictOf(r)} | ${r.counts ? `${r.counts.missing} / ${r.counts.extra}` : r.error} | ${r.counts ? `${r.counts.changes} / ${r.counts.moves} / ${r.counts.lost} / ${r.counts.added}` : ''} | ${r.counts ? `${r.counts.missingFaces} / ${r.counts.extraFaces}` : ''} | ${settledOf(r)} | ${r.deckTab ? `${r.deckTab.orig}/${r.deckTab.rewrite}` : ''} |`);
  const gaps = new Map();
  for (const r of results) for (const g of r.gaps ?? []) {
    const k = `${g.sec} | ${g.before} -> ${g.after}`;
    const o = gaps.get(k) ?? { ...g, leaves: 0, probes: 0, maxLeaves: 0 };
    o.probes++;
    o.maxLeaves = Math.max(o.maxLeaves, g.leaves);
    gaps.set(k, o);
  }
  const gapRows = [...gaps.values()].map((g) => `| ${g.sec} | ${g.before} | ${g.after} | ${g.maxLeaves} | ${g.probes} / ${results.length} | ${g.texts.join('; ')} |`);
  const detail = results.filter((r) => r.counts && !r.pass).flatMap((r) => [
    `- ${r.id}`,
    ...r.moves.slice(0, 6).map((m) => `  - moved "${m.text.slice(0, 40)}" ${m.font}: ${m.from} -> ${m.to}`),
    ...r.lost.slice(0, 6).map((u) => `  - lost ${u.sec} "${u.text.slice(0, 40)}" ${font(u)}`),
    ...r.added.slice(0, 6).map((u) => `  - added ${u.sec} "${u.text.slice(0, 40)}" ${font(u)}`),
    ...r.missingFaces.map((t) => `  - face lost ${t.join(' ')}`),
    ...r.extraFaces.map((t) => `  - face added ${t.join(' ')}`),
  ]);
  return [
    `### Port check 5 (fonts), ${engineName}`, '',
    '| probe | verdict | leaves lost / added | font changes / ownership moves / unpaired lost / unpaired added | faces lost / added | settled orig/rewrite | deck tab orig/rewrite |',
    '|---|---|---|---|---|---|---|', ...rows, '',
    '#### Font changes (same section and text, other family, weight or style)', '',
    '| section | before | after | leaves (max) | probes | sample texts |', '|---|---|---|---|---|---|', ...gapRows, '', ...detail, '',
  ].join('\n');
}

/** Compare fonts.json files of runs of one head: per probe the counts of each run, and whether they are equal in all of them. */
export function fontsCompare(files) {
  const runs = files.map((f) => JSON.parse(readFileSync(f, 'utf8')));
  const ids = [...new Set(runs.flatMap((r) => r.probes.map((p) => p.id)))];
  const cell = (r, id) => {
    const p = r.probes.find((x) => x.id === id);
    if (!p?.counts) return 'error';
    const c = p.counts;
    return `${c.leaves.orig}/${c.leaves.rewrite} ${c.missing}/${c.extra} ${c.changes}/${c.moves}/${c.lost}/${c.added}${p.settled && p.settled.orig && p.settled.rewrite ? '' : ' UNSETTLED'}`;
  };
  const rows = ids.map((id) => {
    const cs = runs.map((r) => cell(r, id));
    return `| ${id} | ${cs.join(' | ')} | ${new Set(cs).size === 1 ? 'same' : 'DIFFERS'} |`;
  });
  return [
    `### ${runs[0]?.engine ?? ''}: leaves orig/rewrite, lost/added, changes/moves/lost/added`, '',
    `| probe | ${files.map((_, i) => `run ${i + 1}`).join(' | ')} | stable |`, `|---|${files.map(() => '---|').join('')}---|`, ...rows, '',
  ].join('\n');
}
